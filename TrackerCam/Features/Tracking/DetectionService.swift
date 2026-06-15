import Vision
import CoreML
import CoreVideo
import TrackerCamCore

/// Core ML horse/person detection → compound (horse+rider) target selection. Plan §8.
///
/// MODEL (plan §8 / §7): expects a YOLO26n Core ML model exporting the COCO classes (`horse`, `person`).
/// YOLO26 is end-to-end / NMS-free, so no in-app non-maximum suppression is needed for the standard
/// export. Drop `YOLO26n_horse.mlpackage` into the app bundle (see Resources/Models) before Phase 3.
actor DetectionService {
    struct Detection: Sendable {
        var pixelRect: TCRect
        var confidence: Double
    }

    private let visionModel: VNCoreMLModel?

    init() {
        // Lazily load the bundled model; nil until the .mlpackage is added (Phase 3).
        if let url = Bundle.main.url(forResource: "YOLO26n_horse", withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: url),
           let vn = try? VNCoreMLModel(for: model) {
            visionModel = vn
        } else {
            visionModel = nil
        }
    }

    var isModelLoaded: Bool { visionModel != nil }

    /// Returns the best compound horse+rider target in source-pixel coordinates, or nil.
    func detectCompoundTarget(in pixelBuffer: CVPixelBuffer,
                              sourceSize: TCSize,
                              confidenceThreshold: Double) async throws -> Detection? {
        guard let visionModel else { return nil }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
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

    private func score(_ h: (TCRect, Double), _ center: TCPoint, _ diag: Double, _ size: TCSize) -> Double {
        let c = h.0.center
        let dist = ((c.x - center.x) * (c.x - center.x) + (c.y - center.y) * (c.y - center.y)).squareRoot()
        let centerProximity = 1.0 - min(1.0, dist / (diag / 2))
        let sizeWeight = min(1.0, h.0.area / (size.width * size.height))
        return h.1 * (0.5 + 0.5 * centerProximity) * (0.5 + 0.5 * sizeWeight)
    }
}
