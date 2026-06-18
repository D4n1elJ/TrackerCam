import Vision
import CoreML
import CoreVideo
import TrackerCamCore

/// Core ML horse/person detection → compound (horse+rider) target selection. Plan §8.
///
/// MODEL (plan §8 / §7): expects a YOLO26n Core ML model exporting the COCO classes (`horse`, `person`).
/// YOLO26 is end-to-end / NMS-free, so no in-app non-maximum suppression is needed for the standard
/// export. Drop `YOLO26n_horse.mlpackage` into the app bundle (see Resources/Models) before Phase 3.
/// A plain (non-actor) `@unchecked Sendable` class: it holds only the immutable Vision model, and
/// runs synchronously within the caller's isolation domain so the non-Sendable pixel buffer never
/// crosses an actor boundary. Vision's `perform` is CPU-bound; the caller throttles it by cadence.
final class DetectionService: @unchecked Sendable {
    struct Detection: Sendable {
        var pixelRect: TCRect
        var confidence: Double
    }

    private let visionModel: VNCoreMLModel?
    /// Reused across detections (configured once). Detection is coalesced to a single in-flight
    /// call by the caller, so reuse is safe and avoids a per-cadence request allocation.
    private let request: VNCoreMLRequest?

    /// Model-free subject acquisition (no trained model required). Objectness-based saliency returns
    /// bounding boxes for distinct foreground objects (the horse stands out against the arena), and
    /// human-rectangle detection finds the rider to form the compound target. Both are built into
    /// Vision, so the app can auto-acquire with pure math — no Core ML model needed.
    /// (Objectness, not attention: attention returns a gaze heatmap with often-empty `salientObjects`.)
    private let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
    private let humanRequest = VNDetectHumanRectanglesRequest()
    private var previousMotionSample: [UInt8]?

    static var isBundledModelAvailable: Bool {
        Bundle.main.url(forResource: "YOLO26n_horse", withExtension: "mlmodelc") != nil
    }

    static var isAutoAcquireAvailable: Bool { true }

    init() {
        // Lazily load the bundled model; nil until the .mlpackage is added (Phase 3).
        if let url = Bundle.main.url(forResource: "YOLO26n_horse", withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: url),
           let vn = try? VNCoreMLModel(for: model) {
            visionModel = vn
            let req = VNCoreMLRequest(model: vn)
            req.imageCropAndScaleOption = .scaleFill
            request = req
        } else {
            visionModel = nil
            request = nil
        }
    }

    var isModelLoaded: Bool { visionModel != nil }

    /// The app can always auto-acquire a subject: a trained model is preferred when present, but the
    /// saliency+human fallback needs none. Gate auto-acquisition on this, not `isModelLoaded`.
    var canAutoAcquire: Bool { Self.isAutoAcquireAvailable }

    /// Best compound subject (+rider) in source-pixel coordinates, or nil. Uses the Core ML model when
    /// bundled, otherwise falls back to model-free saliency+human detection.
    func detectCompoundTarget(in pixelBuffer: CVPixelBuffer,
                              sourceSize: TCSize,
                              confidenceThreshold: Double) throws -> Detection? {
        if request != nil,
           let modelHit = try detectWithModel(in: pixelBuffer, sourceSize: sourceSize,
                                              confidenceThreshold: confidenceThreshold) {
            return modelHit
        }
        return try detectWithSaliency(in: pixelBuffer, sourceSize: sourceSize)
    }

    /// Core ML path (plan §8). Returns nil if no model or no horse found.
    private func detectWithModel(in pixelBuffer: CVPixelBuffer,
                                 sourceSize: TCSize,
                                 confidenceThreshold: Double) throws -> Detection? {
        guard let request else { return nil }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])

        let recognized = (request.results as? [VNRecognizedObjectObservation]) ?? []
        var horses: [(TCRect, Double)] = []
        var people: [TCRect] = []
        for obs in recognized {
            guard let label = obs.labels.first, Double(obs.confidence) >= confidenceThreshold else { continue }
            let pixel = VisionGeometry.pixelRect(fromNormalized: TCRect(obs.boundingBox), imageSize: sourceSize)
            switch label.identifier {
            case "horse": horses.append((pixel, Double(obs.confidence)))
            case "person": people.append(pixel)
            default: break
            }
        }
        guard !horses.isEmpty else { return nil }

        // Select the best horse: confidence × center proximity × size (plan §8 Selection Heuristics).
        let frameCenter = TCPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)
        let diag = (sourceSize.width * sourceSize.width + sourceSize.height * sourceSize.height).squareRoot()
        let best = horses.max { a, b in score(a, frameCenter, diag, sourceSize) < score(b, frameCenter, diag, sourceSize) }!

        // Associate a rider whose box overlaps the upper horse region (plan §8 Compound target).
        let rider = people.first { $0.iou(best.0) > 0.0 && $0.midY <= best.0.midY }

        let compound = CropMath.compoundSubject(horse: best.0, rider: rider, padding: 0)
        return Detection(pixelRect: compound, confidence: best.1)
    }

    /// Model-free path: objectness saliency picks a foreground subject; human rectangles help choose
    /// a rider-associated subject. If saliency returns no boxes, a human rectangle is expanded into a
    /// conservative horse+rider candidate so auto/refocus still has a subject to seed.
    private func detectWithSaliency(in pixelBuffer: CVPixelBuffer, sourceSize: TCSize) throws -> Detection? {
        let motion = Self.detectMotion(in: pixelBuffer, sourceSize: sourceSize, previous: &previousMotionSample)
        let horseColor = Self.detectBrownForeground(in: pixelBuffer, sourceSize: sourceSize)
        let foreground = Self.detectDarkForeground(in: pixelBuffer, sourceSize: sourceSize)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([saliencyRequest, humanRequest])
        } catch {
            return Self.preferredFallback(horseColor: horseColor, motion: motion, foreground: foreground, sourceSize: sourceSize)
        }

        let frameCenter = TCPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)
        let diag = (sourceSize.width * sourceSize.width + sourceSize.height * sourceSize.height).squareRoot()
        let people = humanRequest.results?.map {
            (VisionGeometry.pixelRect(fromNormalized: TCRect($0.boundingBox), imageSize: sourceSize),
             Double($0.confidence))
        } ?? []

        guard let saliency = saliencyRequest.results?.first as? VNSaliencyImageObservation,
              let objects = saliency.salientObjects, !objects.isEmpty else {
            return Self.humanFallback(people: people, sourceSize: sourceSize, frameCenter: frameCenter, diag: diag) ??
                Self.preferredFallback(horseColor: horseColor, motion: motion, foreground: foreground, sourceSize: sourceSize)
        }

        // Rank salient regions by confidence, center proximity, size, and rider association.
        let ranked: [(TCRect, Double)] = objects.map {
            let rect = VisionGeometry.pixelRect(fromNormalized: TCRect($0.boundingBox), imageSize: sourceSize)
            var score = score((rect, Double($0.confidence)), frameCenter, diag, sourceSize)
            if people.contains(where: { Self.isRider($0.0, associatedWith: rect) }) {
                score *= 2.0
            }
            if let motion, rect.iou(motion.pixelRect.expanded(byFraction: 0.8)) > 0 {
                score *= 1.8
            }
            if let horseColor, rect.iou(horseColor.pixelRect.expanded(byFraction: 0.8)) > 0 {
                score *= 2.2
            }
            if let foreground, rect.iou(foreground.pixelRect.expanded(byFraction: 0.8)) > 0 {
                score *= 1.5
            }
            return (rect, score)
        }
        let best = ranked.max { $0.1 < $1.1 }!

        if people.isEmpty, let horseColor {
            if let motion, horseColor.pixelRect.iou(motion.pixelRect.expanded(byFraction: 0.8)) == 0 {
                return motion
            }
            return horseColor
        }
        if people.isEmpty, let motion, best.0.iou(motion.pixelRect.expanded(byFraction: 0.8)) == 0 {
            return motion
        }
        if people.isEmpty, motion == nil, let foreground, best.0.iou(foreground.pixelRect.expanded(byFraction: 0.8)) == 0 {
            return foreground
        }

        // Associate a rider: a detected human overlapping the subject, or directly above it.
        let rider = people.map(\.0).first {
            Self.isRider($0, associatedWith: best.0)
        }

        let compound = CropMath.compoundSubject(horse: best.0, rider: rider, padding: 0)
        return Detection(pixelRect: compound, confidence: best.1)
    }

    private static func isRider(_ person: TCRect, associatedWith subject: TCRect) -> Bool {
        person.iou(subject) > 0 || (abs(person.center.x - subject.center.x) < subject.width && person.midY <= subject.midY)
    }

    private static func humanFallback(people: [(TCRect, Double)],
                                      sourceSize: TCSize,
                                      frameCenter: TCPoint,
                                      diag: Double) -> Detection? {
        guard let rider = people.max(by: {
            scoreHuman($0, frameCenter, diag, sourceSize) < scoreHuman($1, frameCenter, diag, sourceSize)
        }) else { return nil }

        let w = min(sourceSize.width * 0.45, max(rider.0.width * 4.0, sourceSize.width * 0.12))
        let h = min(sourceSize.height * 0.55, max(rider.0.height * 3.8, sourceSize.height * 0.18))
        let candidate = TCRect(x: rider.0.midX - w * 0.5,
                               y: rider.0.minY - rider.0.height * 0.45,
                               width: w,
                               height: h)
        return Detection(pixelRect: clamp(candidate, sourceSize: sourceSize),
                         confidence: max(0.35, rider.1))
    }

    private static func scoreHuman(_ h: (TCRect, Double), _ center: TCPoint, _ diag: Double, _ size: TCSize) -> Double {
        let c = h.0.center
        let dist = ((c.x - center.x) * (c.x - center.x) + (c.y - center.y) * (c.y - center.y)).squareRoot()
        let centerProximity = 1.0 - min(1.0, dist / (diag / 2))
        let sizeWeight = min(1.0, h.0.area / (size.width * size.height * 0.06))
        return h.1 * (0.6 + 0.4 * centerProximity) * (0.5 + 0.5 * sizeWeight)
    }

    private static func preferredFallback(horseColor: Detection?,
                                          motion: Detection?,
                                          foreground: Detection?,
                                          sourceSize: TCSize) -> Detection? {
        if let horseColor, let motion {
            if horseColor.pixelRect.iou(motion.pixelRect.expanded(byFraction: 0.8)) > 0 ||
                motion.pixelRect.iou(horseColor.pixelRect.expanded(byFraction: 0.8)) > 0 {
                return Detection(pixelRect: clamp(horseColor.pixelRect.union(motion.pixelRect), sourceSize: sourceSize),
                                 confidence: max(horseColor.confidence, motion.confidence))
            }
            return motion
        }
        return horseColor ?? motion ?? foreground
    }

    private static func clamp(_ rect: TCRect, sourceSize: TCSize) -> TCRect {
        let w = min(max(1, rect.width), sourceSize.width)
        let h = min(max(1, rect.height), sourceSize.height)
        let x = min(max(0, rect.x), sourceSize.width - w)
        let y = min(max(0, rect.y), sourceSize.height - h)
        return TCRect(x: x, y: y, width: w, height: h)
    }

    private static func detectMotion(in pixelBuffer: CVPixelBuffer,
                                     sourceSize: TCSize,
                                     previous: inout [UInt8]?) -> Detection? {
        let gridW = 64
        let gridH = 36
        guard let sample = sampleLumaGrid(pixelBuffer, gridW: gridW, gridH: gridH) else {
            previous = nil
            return nil
        }

        guard let prev = previous, prev.count == sample.count else {
            previous = sample
            return nil
        }
        previous = sample

        var minX = gridW
        var minY = gridH
        var maxX = -1
        var maxY = -1
        var changed = 0
        for i in 0..<sample.count {
            let delta = abs(Int(sample[i]) - Int(prev[i]))
            guard delta > 18 else { continue }
            let x = i % gridW
            let y = i / gridW
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
            changed += 1
        }

        guard changed >= 8, maxX >= minX, maxY >= minY else { return nil }
        let cellW = sourceSize.width / Double(gridW)
        let cellH = sourceSize.height / Double(gridH)
        let padX = cellW * 4
        let padY = cellH * 4
        let motionRect = TCRect(x: Double(minX) * cellW - padX,
                                y: Double(minY) * cellH - padY,
                                width: Double(maxX - minX + 1) * cellW + padX * 2,
                                height: Double(maxY - minY + 1) * cellH + padY * 2)
        let targetW = min(sourceSize.width * 0.36, max(motionRect.width * 2.2, sourceSize.width * 0.14))
        let targetH = min(sourceSize.height * 0.48, max(motionRect.height * 2.6, sourceSize.height * 0.22))
        let subjectRect = TCRect(x: motionRect.midX - targetW * 0.5,
                                 y: motionRect.maxY - targetH * 0.88,
                                 width: targetW,
                                 height: targetH)
        let clamped = clamp(subjectRect, sourceSize: sourceSize)
        guard clamped.area >= sourceSize.width * sourceSize.height * 0.01,
              clamped.area <= sourceSize.width * sourceSize.height * 0.28 else {
            return nil
        }
        return Detection(pixelRect: clamped, confidence: min(0.85, 0.35 + Double(changed) / 120.0))
    }

    private static func detectDarkForeground(in pixelBuffer: CVPixelBuffer,
                                             sourceSize: TCSize) -> Detection? {
        let gridW = 96
        let gridH = 54
        guard let sample = sampleLumaGrid(pixelBuffer, gridW: gridW, gridH: gridH) else { return nil }

        var visited = [Bool](repeating: false, count: sample.count)
        var best: (rect: TCRect, score: Double, count: Int)?
        let frameCenter = TCPoint(x: sourceSize.width * 0.5, y: sourceSize.height * 0.56)
        let cellW = sourceSize.width / Double(gridW)
        let cellH = sourceSize.height / Double(gridH)

        for start in 0..<sample.count {
            guard !visited[start] else { continue }
            let sx = start % gridW
            let sy = start / gridW
            guard isForegroundLuma(sample[start], gridY: sy, gridH: gridH) else {
                visited[start] = true
                continue
            }

            var stack = [start]
            visited[start] = true
            var minX = sx
            var minY = sy
            var maxX = sx
            var maxY = sy
            var count = 0

            while let idx = stack.popLast() {
                let x = idx % gridW
                let y = idx / gridW
                count += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)

                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                for (nx, ny) in neighbors where nx >= 0 && nx < gridW && ny >= 0 && ny < gridH {
                    let nidx = ny * gridW + nx
                    guard !visited[nidx] else { continue }
                    visited[nidx] = true
                    if isForegroundLuma(sample[nidx], gridY: ny, gridH: gridH) {
                        stack.append(nidx)
                    }
                }
            }

            guard count >= 10 else { continue }
            let rect = TCRect(x: Double(minX) * cellW,
                              y: Double(minY) * cellH,
                              width: Double(maxX - minX + 1) * cellW,
                              height: Double(maxY - minY + 1) * cellH)
            let aspect = rect.width / max(rect.height, 1)
            guard rect.area >= sourceSize.width * sourceSize.height * 0.002,
                  rect.area <= sourceSize.width * sourceSize.height * 0.16,
                  aspect >= 0.35, aspect <= 4.5 else { continue }

            let dx = rect.center.x - frameCenter.x
            let dy = rect.center.y - frameCenter.y
            let centerProximity = 1.0 - min(1.0, hypot(dx, dy) / hypot(sourceSize.width, sourceSize.height))
            let sizeScore = min(1.0, rect.area / (sourceSize.width * sourceSize.height * 0.035))
            let verticalBand = rect.midY >= sourceSize.height * 0.24 && rect.midY <= sourceSize.height * 0.86 ? 1.0 : 0.35
            let score = (0.45 + 0.35 * centerProximity + 0.20 * sizeScore) * verticalBand
            if best == nil || score > best!.score {
                best = (rect, score, count)
            }
        }

        guard let best else { return nil }
        let targetW = min(sourceSize.width * 0.45, max(best.rect.width * 1.9, sourceSize.width * 0.14))
        let targetH = min(sourceSize.height * 0.60, max(best.rect.height * 2.2, sourceSize.height * 0.24))
        let subjectRect = TCRect(x: best.rect.midX - targetW * 0.5,
                                 y: best.rect.maxY - targetH * 0.86,
                                 width: targetW,
                                 height: targetH)
        return Detection(pixelRect: clamp(subjectRect, sourceSize: sourceSize),
                         confidence: min(0.78, 0.42 + Double(best.count) / 180.0))
    }

    private static func detectBrownForeground(in pixelBuffer: CVPixelBuffer,
                                              sourceSize: TCSize) -> Detection? {
        let gridW = 96
        let gridH = 54
        guard let sample = sampleRGBGrid(pixelBuffer, gridW: gridW, gridH: gridH) else { return nil }

        var visited = [Bool](repeating: false, count: sample.count)
        var best: (rect: TCRect, score: Double, count: Int)?
        let frameCenter = TCPoint(x: sourceSize.width * 0.5, y: sourceSize.height * 0.58)
        let cellW = sourceSize.width / Double(gridW)
        let cellH = sourceSize.height / Double(gridH)

        for start in 0..<sample.count {
            guard !visited[start] else { continue }
            let sx = start % gridW
            let sy = start / gridW
            guard isHorseColor(sample[start], gridY: sy, gridH: gridH) else {
                visited[start] = true
                continue
            }

            var stack = [start]
            visited[start] = true
            var minX = sx
            var minY = sy
            var maxX = sx
            var maxY = sy
            var count = 0

            while let idx = stack.popLast() {
                let x = idx % gridW
                let y = idx / gridW
                count += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)

                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                for (nx, ny) in neighbors where nx >= 0 && nx < gridW && ny >= 0 && ny < gridH {
                    let nidx = ny * gridW + nx
                    guard !visited[nidx] else { continue }
                    visited[nidx] = true
                    if isHorseColor(sample[nidx], gridY: ny, gridH: gridH) {
                        stack.append(nidx)
                    }
                }
            }

            guard count >= 3 else { continue }
            let rect = TCRect(x: Double(minX) * cellW,
                              y: Double(minY) * cellH,
                              width: Double(maxX - minX + 1) * cellW,
                              height: Double(maxY - minY + 1) * cellH)
            let aspect = rect.width / max(rect.height, 1)
            guard rect.area >= sourceSize.width * sourceSize.height * 0.00045,
                  rect.area <= sourceSize.width * sourceSize.height * 0.12,
                  aspect >= 0.45, aspect <= 5.5 else { continue }

            let dx = rect.center.x - frameCenter.x
            let dy = rect.center.y - frameCenter.y
            let centerProximity = 1.0 - min(1.0, hypot(dx, dy) / hypot(sourceSize.width, sourceSize.height))
            let sizeScore = min(1.0, rect.area / (sourceSize.width * sourceSize.height * 0.025))
            let verticalBand = rect.midY >= sourceSize.height * 0.35 && rect.midY <= sourceSize.height * 0.86 ? 1.0 : 0.0
            guard verticalBand > 0 else { continue }
            let score = (0.40 + 0.35 * centerProximity + 0.25 * sizeScore) * verticalBand
            if best == nil || score > best!.score {
                best = (rect, score, count)
            }
        }

        guard let best else { return nil }
        let targetW = min(sourceSize.width * 0.46, max(best.rect.width * 2.5, sourceSize.width * 0.16))
        let targetH = min(sourceSize.height * 0.62, max(best.rect.height * 3.0, sourceSize.height * 0.28))
        let subjectRect = TCRect(x: best.rect.midX - targetW * 0.5,
                                 y: best.rect.maxY - targetH * 0.88,
                                 width: targetW,
                                 height: targetH)
        return Detection(pixelRect: clamp(subjectRect, sourceSize: sourceSize),
                         confidence: min(0.86, 0.50 + Double(best.count) / 150.0))
    }

    private static func sampleLumaGrid(_ pixelBuffer: CVPixelBuffer,
                                       gridW: Int,
                                       gridH: Int) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        var sample = [UInt8](repeating: 0, count: gridW * gridH)
        if CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
           let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yPlane = base.assumingMemoryBound(to: UInt8.self)
            for gy in 0..<gridH {
                let py = min(height - 1, max(0, (gy * height) / gridH))
                for gx in 0..<gridW {
                    let px = min(width - 1, max(0, (gx * width) / gridW))
                    sample[gy * gridW + gx] = yPlane[py * stride + px]
                }
            }
            return sample
        }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for gy in 0..<gridH {
            let py = min(height - 1, max(0, (gy * height) / gridH))
            for gx in 0..<gridW {
                let px = min(width - 1, max(0, (gx * width) / gridW))
                let offset = py * stride + px * 4
                let b = Double(bytes[offset])
                let g = Double(bytes[offset + 1])
                let r = Double(bytes[offset + 2])
                sample[gy * gridW + gx] = UInt8(max(0, min(255, 0.299 * r + 0.587 * g + 0.114 * b)))
            }
        }
        return sample
    }

    private static func sampleRGBGrid(_ pixelBuffer: CVPixelBuffer,
                                      gridW: Int,
                                      gridH: Int) -> [(r: UInt8, g: UInt8, b: UInt8)]? {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 0 else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        var sample = [(r: UInt8, g: UInt8, b: UInt8)](repeating: (0, 0, 0), count: gridW * gridH)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for gy in 0..<gridH {
            let py = min(height - 1, max(0, (gy * height) / gridH))
            for gx in 0..<gridW {
                let px = min(width - 1, max(0, (gx * width) / gridW))
                let offset = py * stride + px * 4
                sample[gy * gridW + gx] = (r: bytes[offset + 2], g: bytes[offset + 1], b: bytes[offset])
            }
        }
        return sample
    }

    private static func isForegroundLuma(_ luma: UInt8, gridY: Int, gridH: Int) -> Bool {
        gridY > gridH / 5 && luma < 112
    }

    private static func isHorseColor(_ rgb: (r: UInt8, g: UInt8, b: UInt8), gridY: Int, gridH: Int) -> Bool {
        guard Double(gridY) / Double(gridH) > 0.34 else { return false }
        let r = Int(rgb.r)
        let g = Int(rgb.g)
        let b = Int(rgb.b)
        let luma = (77 * r + 150 * g + 29 * b) / 256
        let chroma = max(r, g, b) - min(r, g, b)
        return luma >= 30 && luma <= 128 &&
            chroma >= 22 &&
            r >= g - 4 &&
            g >= b + 6 &&
            r >= b + 18
    }

    private func score(_ h: (TCRect, Double), _ center: TCPoint, _ diag: Double, _ size: TCSize) -> Double {
        let c = h.0.center
        let dist = ((c.x - center.x) * (c.x - center.x) + (c.y - center.y) * (c.y - center.y)).squareRoot()
        let centerProximity = 1.0 - min(1.0, dist / (diag / 2))
        let sizeWeight = min(1.0, h.0.area / (size.width * size.height))
        return h.1 * (0.5 + 0.5 * centerProximity) * (0.5 + 0.5 * sizeWeight)
    }
}
