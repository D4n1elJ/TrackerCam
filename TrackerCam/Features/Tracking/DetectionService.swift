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

    /// Model-free path: attention-based saliency picks the dominant subject (the moving horse stands
    /// out against the static arena); a detected human (rider) overlapping or above it forms the
    /// compound target. Confidence is the saliency confidence. No trained model needed.
    private func detectWithSaliency(in pixelBuffer: CVPixelBuffer, sourceSize: TCSize) throws -> Detection? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([saliencyRequest, humanRequest])

        guard let saliency = saliencyRequest.results?.first as? VNSaliencyImageObservation,
              let objects = saliency.salientObjects, !objects.isEmpty else { return nil }

        // Rank salient regions by confidence × center-proximity × size (same heuristic as the model path).
        let frameCenter = TCPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)
        let diag = (sourceSize.width * sourceSize.width + sourceSize.height * sourceSize.height).squareRoot()
        let ranked: [(TCRect, Double)] = objects.map {
            (VisionGeometry.pixelRect(fromNormalized: TCRect($0.boundingBox), imageSize: sourceSize), Double($0.confidence))
        }
        let best = ranked.max { score($0, frameCenter, diag, sourceSize) < score($1, frameCenter, diag, sourceSize) }!

        // Associate a rider: a detected human overlapping the subject, or directly above it (rider on horse).
        let people = humanRequest.results?.map {
            VisionGeometry.pixelRect(fromNormalized: TCRect($0.boundingBox), imageSize: sourceSize)
        } ?? []
        let rider = people.first {
            $0.iou(best.0) > 0 || (abs($0.center.x - best.0.center.x) < best.0.width && $0.midY <= best.0.midY)
        }

        let compound = CropMath.compoundSubject(horse: best.0, rider: rider, padding: 0)
        return Detection(pixelRect: compound, confidence: best.1)
    }

    private func score(_ h: (TCRect, Double), _ center: TCPoint, _ diag: Double, _ size: TCSize) -> Double {
        let c = h.0.center
        let dist = ((c.x - center.x) * (c.x - center.x) + (c.y - center.y) * (c.y - center.y)).squareRoot()
        let centerProximity = 1.0 - min(1.0, dist / (diag / 2))
        let sizeWeight = min(1.0, h.0.area / (size.width * size.height))
        return h.1 * (0.5 + 0.5 * centerProximity) * (0.5 + 0.5 * sizeWeight)
    }
}
