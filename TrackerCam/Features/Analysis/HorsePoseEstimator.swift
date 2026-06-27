import CoreML
import CoreVideo
import os
import TrackerCamCore

private let horseLog = Logger(subsystem: "com.trackercam.app", category: "analysis.horsepose")

/// Horse body-angle estimation — the LONG POLE of this feature.
///
/// There is NO native (Vision / MediaPipe) animal-pose model, so horse joint angles require a custom
/// **animal-keypoint Core ML model** (e.g. trained on AP-10K / a horse-specific keypoint set and
/// exported with coremltools). This is a real research/data task; until that model exists the rest of
/// the pipeline (rider angles, horse *box* from RF-DETR, annotation) works without it.
///
/// This file defines the seam so the model is a drop-in: implement the `HorsePosing` protocol against
/// the bundled model and the analyzer/annotator pick it up automatically. The contract (keypoint names,
/// input/output) is pinned in ANALYSIS_SPEC.md.
///
/// Suggested keypoint set (extend as the model dictates):
enum TCHorseJoint: String, CaseIterable, Sendable {
    case nose, poll, withers, croup, tailBase
    case leftForeHoof, rightForeHoof, leftHindHoof, rightHindHoof
    case leftKnee, rightKnee, leftHock, rightHock   // fore "knee" = carpus; hind = hock
}

protocol HorsePosing: Sendable {
    var isModelLoaded: Bool { get }
    func skeleton(in pixelBuffer: CVPixelBuffer, imageSize: TCSize, box: TCRect?) -> TCSkeleton?
}

/// Placeholder implementation: reports `isModelLoaded == false` and returns nil until a real
/// `Horse_keypoints.mlpackage` (conforming to ANALYSIS_SPEC.md) is bundled and wired here.
final class CoreMLHorsePoseEstimator: HorsePosing, @unchecked Sendable {
    private static let resourceName = "Horse_keypoints"
    let isModelLoaded: Bool

    static var isBundledModelAvailable: Bool {
        Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") != nil
    }

    init() {
        isModelLoaded = Self.isBundledModelAvailable
        if !isModelLoaded {
            horseLog.notice("Horse-keypoint model absent — horse angles disabled (the long-pole model; see ANALYSIS_SPEC.md)")
        }
        // TODO: when a model is available, load MLModel + build the keypoint decode here.
    }

    func skeleton(in pixelBuffer: CVPixelBuffer, imageSize: TCSize, box: TCRect?) -> TCSkeleton? {
        guard isModelLoaded else { return nil }
        // TODO: run the model, decode heatmaps/regressed keypoints → TCSkeleton(TCHorseJoint keys).
        return nil
    }
}
