import Vision
import CoreVideo
import CoreGraphics
import TrackerCamCore

/// A drawable skeleton for one subject in one frame. Joint points are normalized [0,1] in the
/// displayed (full-frame) image, top-left origin — so the overlay maps them with the same
/// `PreviewGeometry.textureDrawRect` the box overlay uses. `bones` index into `joints`.
struct SkeletonOverlay: Identifiable, Sendable, Equatable {
    enum Kind: Sendable { case human, animal }
    struct Joint: Sendable, Equatable {
        var x: CGFloat
        var y: CGFloat
        var confidence: CGFloat
    }
    struct Bone: Sendable, Equatable { var a: Int; var b: Int }

    let id: Int
    let kind: Kind
    let joints: [Joint]
    let bones: [Bone]
}

/// Live, on-device skeleton tracking for the camera feed.
///
/// Runs Vision body-pose on each (downscaled) frame and returns drawable skeletons. Human pose is
/// primary (`VNDetectHumanBodyPoseRequest`); cats/dogs can be added via `VNDetectAnimalBodyPoseRequest`
/// (see the seam below). An actor so inference runs off the main actor; it returns only Sendable
/// value types, so the non-Sendable pixel buffer never escapes.
///
/// SIMULATOR: body pose is ANE-backed and does NOT run in the simulator (espresso: missing
/// cnn_human_pose weights) — validate on device.
actor LiveSkeletonTracker {
    /// Master human-joint order; the index of each name in this array is its joint index in the output.
    private static let humanOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .neck,
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
        .root,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle,
    ]

    /// Human skeleton bones as (jointName, jointName) pairs; resolved to indices per frame.
    private static let humanBonePairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.neck, .nose),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    private let minConfidence: Float = 0.15

    /// Detect skeletons in the (already downscaled) frame. `imageSize` is its pixel size; results are
    /// normalized to [0,1] so they're resolution-independent for the overlay. Takes the Sendable
    /// `FramePayload` so the non-Sendable pixel buffer never crosses the actor boundary directly.
    func skeletons(in payload: FramePayload, imageSize: TCSize) -> [SkeletonOverlay] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: payload.pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results, !observations.isEmpty else {
            return []
        }

        var out: [SkeletonOverlay] = []
        for (i, observation) in observations.enumerated() {
            guard let points = try? observation.recognizedPoints(.all) else { continue }
            if let overlay = Self.makeHumanOverlay(id: i, points: points, minConfidence: minConfidence) {
                out.append(overlay)
            }
        }
        return out
    }

    private static func makeHumanOverlay(
        id: Int,
        points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
        minConfidence: Float
    ) -> SkeletonOverlay? {
        // Build joints in master order; track which names map to which output index.
        var joints: [SkeletonOverlay.Joint] = []
        var indexOf: [VNHumanBodyPoseObservation.JointName: Int] = [:]
        for name in humanOrder {
            guard let p = points[name], p.confidence >= minConfidence else { continue }
            indexOf[name] = joints.count
            // Vision: normalized, origin bottom-left → convert to top-left for the overlay.
            joints.append(SkeletonOverlay.Joint(
                x: CGFloat(p.location.x),
                y: CGFloat(1 - p.location.y),
                confidence: CGFloat(p.confidence)))
        }
        guard joints.count >= 3 else { return nil }   // too few joints to be a real subject

        var bones: [SkeletonOverlay.Bone] = []
        for (a, b) in humanBonePairs {
            if let ia = indexOf[a], let ib = indexOf[b] {
                bones.append(SkeletonOverlay.Bone(a: ia, b: ib))
            }
        }
        return SkeletonOverlay(id: id, kind: .human, joints: joints, bones: bones)
    }

    // MARK: - Animal (cat/dog) seam
    //
    // Cats and dogs have a NATIVE Vision model: `VNDetectAnimalBodyPoseRequest` →
    // `VNAnimalBodyPoseObservation` (~25 joints: ears, nose, neck, four legs w/ paws, tail). Horses do
    // NOT (they need a custom Core ML keypoint model). To add cat/dog: run the request here, map its
    // `JointName` group to `SkeletonOverlay.Joint`/`Bone` exactly like the human path, and merge the
    // results. Kept out of the first robust build to keep the human path simple and verified first.
}
