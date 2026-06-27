import Vision
import CoreML
import CoreVideo
import os
import TrackerCamCore

private let detLog = Logger(subsystem: "com.trackercam.app", category: "analysis.detect")

/// Horse + rider box detection for offline clip analysis.
///
/// Primary backend: **RF-DETR exported to Core ML** (Roboflow). RF-DETR is a real-time DETR; trained
/// on a horse+rider dataset and exported with class-label metadata, Vision wraps its outputs as
/// `VNRecognizedObjectObservation` — a drop-in just like the existing `YOLO26n_horse` detector
/// (see TrackerCam/Features/Analysis/ANALYSIS_SPEC.md for the exact contract).
///
/// Until the model is bundled, `RFDETRDetector` reports `isModelLoaded == false` and the analyzer
/// falls back to the app's existing motion/saliency acquisition or runs pose on the whole frame.
struct SubjectBoxes: Sendable {
    var horse: TCRect?
    var rider: TCRect?
}

protocol SubjectDetecting: Sendable {
    var isModelLoaded: Bool { get }
    /// Detect the most confident horse and rider boxes in `pixelBuffer` (top-left pixel space).
    func detect(in pixelBuffer: CVPixelBuffer, imageSize: TCSize) -> SubjectBoxes
}

final class RFDETRDetector: SubjectDetecting, @unchecked Sendable {
    /// Compiled model resource name (drop `RFDETR_horse_rider.mlpackage` into TrackerCam/ML/).
    private static let resourceName = "RFDETR_horse_rider"

    private let request: VNCoreMLRequest?
    var isModelLoaded: Bool { request != nil }

    static var isBundledModelAvailable: Bool {
        Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") != nil
    }

    init() {
        if let url = Bundle.main.url(forResource: Self.resourceName, withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: url),
           let vn = try? VNCoreMLModel(for: model) {
            let req = VNCoreMLRequest(model: vn)
            req.imageCropAndScaleOption = .scaleFill
            request = req
            detLog.notice("RF-DETR model loaded")
        } else {
            request = nil
            detLog.notice("RF-DETR model absent — detection disabled (drop \(Self.resourceName).mlpackage into TrackerCam/ML/)")
        }
    }

    func detect(in pixelBuffer: CVPixelBuffer, imageSize: TCSize) -> SubjectBoxes {
        guard let request else { return SubjectBoxes() }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results as? [VNRecognizedObjectObservation] else {
            return SubjectBoxes()
        }

        var bestHorse: (TCRect, Float)?
        var bestRider: (TCRect, Float)?
        for obs in results {
            guard let label = obs.labels.first else { continue }
            let rect = VisionGeometry.pixelRect(fromNormalized: TCRect(obs.boundingBox), imageSize: imageSize)
            switch label.identifier {
            case "horse":
                if bestHorse == nil || obs.confidence > bestHorse!.1 { bestHorse = (rect, obs.confidence) }
            case "person", "rider":
                if bestRider == nil || obs.confidence > bestRider!.1 { bestRider = (rect, obs.confidence) }
            default:
                continue
            }
        }
        return SubjectBoxes(horse: bestHorse?.0, rider: bestRider?.0)
    }
}
