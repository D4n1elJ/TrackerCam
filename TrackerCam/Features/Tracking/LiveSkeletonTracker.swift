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
/// Runs Vision body-pose on each (downscaled) frame and returns drawable skeletons:
///   • Humans  — `VNDetectHumanBodyPoseRequest`  (green)
///   • Cats/dogs — `VNDetectAnimalBodyPoseRequest` (orange, iOS 17+)
/// Horses have NO native model (they'd need a custom Core ML keypoint model), so they aren't covered.
///
/// An actor so inference runs off the main actor; it returns only Sendable value types, so the
/// non-Sendable pixel buffer never escapes.
///
/// SIMULATOR: body pose is ANE-backed and does NOT run in the simulator (espresso: missing pose
/// weights) — validate on device.
actor LiveSkeletonTracker {
    /// Whether to also run animal (cat/dog) pose each frame. Humans are always detected.
    var detectAnimals: Bool = true

    private let minConfidence: Float = 0.15

    func setDetectAnimals(_ on: Bool) { detectAnimals = on }

    /// Detect skeletons in the (already downscaled) frame. `imageSize` is its pixel size; results are
    /// normalized to [0,1] so they're resolution-independent for the overlay. Takes the Sendable
    /// `FramePayload` so the non-Sendable pixel buffer never crosses the actor boundary directly.
    func skeletons(in payload: FramePayload, imageSize: TCSize) -> [SkeletonOverlay] {
        let handler = VNImageRequestHandler(cvPixelBuffer: payload.pixelBuffer, orientation: .up, options: [:])

        var requests: [VNRequest] = []
        let humanRequest = VNDetectHumanBodyPoseRequest()
        requests.append(humanRequest)
        let animalRequest = detectAnimals ? VNDetectAnimalBodyPoseRequest() : nil
        if let animalRequest { requests.append(animalRequest) }

        guard (try? handler.perform(requests)) != nil else { return [] }

        var out: [SkeletonOverlay] = []

        // Humans (ids 0…).
        for (i, observation) in (humanRequest.results ?? []).enumerated() {
            guard let points = try? observation.recognizedPoints(.all) else { continue }
            if let overlay = Self.makeOverlay(id: i, kind: .human,
                                              order: Self.humanOrder, bonePairs: Self.humanBonePairs,
                                              points: points, minConfidence: minConfidence) {
                out.append(overlay)
            }
        }

        // Cats/dogs (ids 1000…, so they never collide with human ids).
        if let animalRequest {
            for (i, observation) in (animalRequest.results ?? []).enumerated() {
                guard let points = try? observation.recognizedPoints(.all) else { continue }
                if let overlay = Self.makeOverlay(id: 1000 + i, kind: .animal,
                                                  order: Self.animalOrder, bonePairs: Self.animalBonePairs,
                                                  points: points, minConfidence: minConfidence) {
                    out.append(overlay)
                }
            }
        }

        return out
    }

    /// Generic overlay builder shared by human and animal paths. `Name` is the Vision JointName type.
    private static func makeOverlay<Name: Hashable>(
        id: Int,
        kind: SkeletonOverlay.Kind,
        order: [Name],
        bonePairs: [(Name, Name)],
        points: [Name: VNRecognizedPoint],
        minConfidence: Float
    ) -> SkeletonOverlay? {
        var joints: [SkeletonOverlay.Joint] = []
        var indexOf: [Name: Int] = [:]
        for name in order {
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
        for (a, b) in bonePairs {
            if let ia = indexOf[a], let ib = indexOf[b] {
                bones.append(SkeletonOverlay.Bone(a: ia, b: ib))
            }
        }
        return SkeletonOverlay(id: id, kind: kind, joints: joints, bones: bones)
    }

    // MARK: - Human joint topology

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

    // MARK: - Animal (cat/dog) joint topology

    private static let animalOrder: [VNAnimalBodyPoseObservation.JointName] = [
        .nose, .neck,
        .leftEarTop, .rightEarTop,
        .leftEye, .rightEye,
        .leftFrontElbow, .leftFrontKnee, .leftFrontPaw,
        .rightFrontElbow, .rightFrontKnee, .rightFrontPaw,
        .leftBackElbow, .leftBackKnee, .leftBackPaw,
        .rightBackElbow, .rightBackKnee, .rightBackPaw,
        .tailTop, .tailMiddle, .tailBottom,
    ]

    private static let animalBonePairs: [(VNAnimalBodyPoseObservation.JointName, VNAnimalBodyPoseObservation.JointName)] = [
        // Head + spine.
        (.nose, .neck),
        (.neck, .leftEarTop), (.neck, .rightEarTop),
        (.neck, .tailTop), (.tailTop, .tailMiddle), (.tailMiddle, .tailBottom),
        // Front legs (hang off the neck/shoulders).
        (.neck, .leftFrontElbow), (.leftFrontElbow, .leftFrontKnee), (.leftFrontKnee, .leftFrontPaw),
        (.neck, .rightFrontElbow), (.rightFrontElbow, .rightFrontKnee), (.rightFrontKnee, .rightFrontPaw),
        // Back legs (hang off the hips/tail base).
        (.tailTop, .leftBackElbow), (.leftBackElbow, .leftBackKnee), (.leftBackKnee, .leftBackPaw),
        (.tailTop, .rightBackElbow), (.rightBackElbow, .rightBackKnee), (.rightBackKnee, .rightBackPaw),
    ]
}
