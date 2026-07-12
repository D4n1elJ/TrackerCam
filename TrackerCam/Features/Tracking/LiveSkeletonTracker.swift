import Vision
import CoreVideo
import CoreGraphics
import os
import TrackerCamCore

private let skeletonLog = Logger(subsystem: "com.trackercam.app", category: "live-skeleton")

/// Which subjects to detect. Exposed to the UI as a segmented toggle.
enum SkeletonSubjectMode: String, CaseIterable, Sendable {
    case human, animal, both
    var label: String {
        switch self {
        case .human: return "People"
        case .animal: return "Cat/Dog"
        case .both: return "Both"
        }
    }
    var detectsHuman: Bool { self != .animal }
    var detectsAnimal: Bool { self != .human }
}

/// A drawable skeleton for one subject in one frame. Joints are a FIXED-LENGTH array aligned to the
/// kind's master joint order (so the index of a joint is stable frame-to-frame — required for
/// temporal smoothing). Absent/low-confidence joints have `confidence == 0`. Points are normalized
/// [0,1] in the displayed full-frame image, top-left origin; `bones` index into `joints`.
struct SkeletonOverlay: Identifiable, Sendable, Equatable {
    enum Kind: Sendable { case human, animal }
    struct Joint: Sendable, Equatable {
        var x: CGFloat
        var y: CGFloat
        var confidence: CGFloat
        var isPresent: Bool { confidence > 0 }
    }
    struct Bone: Sendable, Equatable { var a: Int; var b: Int }

    var id: Int
    let kind: Kind
    var joints: [Joint]
    let bones: [Bone]

    /// Centroid of present joints (normalized), for matching subjects across frames.
    var centroid: CGPoint? {
        let present = joints.filter(\.isPresent)
        guard !present.isEmpty else { return nil }
        let n = CGFloat(present.count)
        return CGPoint(x: present.reduce(0) { $0 + $1.x } / n,
                       y: present.reduce(0) { $0 + $1.y } / n)
    }
}

/// Live, on-device skeleton tracking for the camera feed.
///
///   • Humans   — `VNDetectHumanBodyPoseRequest`   (green)
///   • Cats/dogs — `VNDetectAnimalBodyPoseRequest`  (orange, iOS 17+)
/// Horses have NO native model (they'd need a custom Core ML keypoint model), so they aren't covered.
///
/// An actor so inference + smoothing run off the main actor; returns only Sendable value types, so the
/// non-Sendable pixel buffer never escapes. Output is temporally smoothed (EMA per joint, with a short
/// hold over momentary dropouts) so the overlay doesn't jitter.
///
/// SIMULATOR: body pose is ANE-backed and usually fails with missing espresso weights. After the
/// first hard failure we short-circuit and log once so the live pipeline doesn't spam espresso.
actor LiveSkeletonTracker {
    private(set) var mode: SkeletonSubjectMode = .both
    func setMode(_ m: SkeletonSubjectMode) { mode = m; previous = [] }

    private let minConfidence: Float = 0.15
    /// Current-frame weight for position EMA (lower = smoother, higher = more responsive).
    private let positionAlpha: CGFloat = 0.5
    /// Confidence multiplier applied when a joint is missing this frame but was present last frame —
    /// holds it briefly so a one-frame dropout doesn't flicker the limb.
    private let dropoutDecay: CGFloat = 0.55
    /// Max normalized centroid distance for matching a subject to the previous frame.
    private let matchThreshold: CGFloat = 0.2

    private var previous: [SkeletonOverlay] = []
    /// True after Vision/espresso reports pose models unavailable (typical on Simulator).
    private var poseModelsUnavailable = false
    private var didLogUnavailable = false

    /// Detect + smooth skeletons in the (already downscaled) frame. Results are normalized [0,1].
    func skeletons(in payload: FramePayload, imageSize: TCSize) -> [SkeletonOverlay] {
        if poseModelsUnavailable {
            return []
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: payload.pixelBuffer, orientation: .up, options: [:])

        var requests: [VNRequest] = []
        let humanRequest = mode.detectsHuman ? VNDetectHumanBodyPoseRequest() : nil
        let animalRequest = mode.detectsAnimal ? VNDetectAnimalBodyPoseRequest() : nil
        if let humanRequest { requests.append(humanRequest) }
        if let animalRequest { requests.append(animalRequest) }
        guard !requests.isEmpty else {
            previous = []
            return []
        }

        do {
            try handler.perform(requests)
        } catch {
            markUnavailable(reason: error.localizedDescription)
            previous = []
            return []
        }

        var raw: [SkeletonOverlay] = []
        for (i, obs) in (humanRequest?.results ?? []).enumerated() {
            if let pts = try? obs.recognizedPoints(.all),
               let o = Self.makeOverlay(id: i, kind: .human, order: Self.humanOrder,
                                        boneIndices: Self.humanBones, points: pts, minConfidence: minConfidence) {
                raw.append(o)
            }
        }
        for (i, obs) in (animalRequest?.results ?? []).enumerated() {
            if let pts = try? obs.recognizedPoints(.all),
               let o = Self.makeOverlay(id: 1000 + i, kind: .animal, order: Self.animalOrder,
                                        boneIndices: Self.animalBones, points: pts, minConfidence: minConfidence) {
                raw.append(o)
            }
        }

        // Simulator often returns empty while espresso spam-logs missing weights — stop after one try.
#if targetEnvironment(simulator)
        if raw.isEmpty {
            markUnavailable(reason: "empty results (likely missing espresso model weights)")
            previous = []
            return []
        }
#endif

        let smoothed = smooth(raw)
        previous = smoothed
        return smoothed
    }

    private func markUnavailable(reason: String) {
        poseModelsUnavailable = true
        guard !didLogUnavailable else { return }
        didLogUnavailable = true
        skeletonLog.warning("Body/animal pose unavailable — skipping further requests (\(reason, privacy: .public)). Common on Simulator; device path is unaffected until a real failure.")
    }

    // MARK: - Temporal smoothing

    private func smooth(_ current: [SkeletonOverlay]) -> [SkeletonOverlay] {
        guard !previous.isEmpty else { return current }
        var usedPrev = Set<Int>()
        var result: [SkeletonOverlay] = []
        for cur in current {
            guard let curC = cur.centroid else { result.append(cur); continue }
            var bestIdx: Int?
            var bestDist = CGFloat.greatestFiniteMagnitude
            for (i, prev) in previous.enumerated()
            where !usedPrev.contains(i) && prev.kind == cur.kind {
                guard let prevC = prev.centroid else { continue }
                let d = hypot(curC.x - prevC.x, curC.y - prevC.y)
                if d < bestDist { bestDist = d; bestIdx = i }
            }
            if let bestIdx, bestDist <= matchThreshold {
                usedPrev.insert(bestIdx)
                result.append(blend(prev: previous[bestIdx], cur: cur))
            } else {
                result.append(cur)
            }
        }
        return result
    }

    /// EMA-blend matched skeletons joint-by-joint (indices are stable). Missing current joints fade
    /// from the previous position so brief dropouts don't flicker.
    private func blend(prev: SkeletonOverlay, cur: SkeletonOverlay) -> SkeletonOverlay {
        var joints = cur.joints
        for i in joints.indices where i < prev.joints.count {
            let p = prev.joints[i]
            let c = cur.joints[i]
            if c.isPresent && p.isPresent {
                joints[i] = SkeletonOverlay.Joint(
                    x: p.x + (c.x - p.x) * positionAlpha,
                    y: p.y + (c.y - p.y) * positionAlpha,
                    confidence: c.confidence)
            } else if !c.isPresent && p.isPresent {
                // Hold the last position with decaying confidence (drops out after a few frames).
                let held = p.confidence * dropoutDecay
                joints[i] = SkeletonOverlay.Joint(x: p.x, y: p.y,
                                                  confidence: held >= CGFloat(minConfidence) ? held : 0)
            }
        }
        var out = cur
        out.id = prev.id        // keep identity stable across frames for SwiftUI
        out.joints = joints
        return out
    }

    // MARK: - Overlay construction (fixed-length, slot-stable)

    private static func makeOverlay<Name: Hashable>(
        id: Int,
        kind: SkeletonOverlay.Kind,
        order: [Name],
        boneIndices: [SkeletonOverlay.Bone],
        points: [Name: VNRecognizedPoint],
        minConfidence: Float
    ) -> SkeletonOverlay? {
        var joints: [SkeletonOverlay.Joint] = []
        joints.reserveCapacity(order.count)
        var presentCount = 0
        for name in order {
            if let p = points[name], p.confidence >= minConfidence {
                presentCount += 1
                joints.append(SkeletonOverlay.Joint(x: CGFloat(p.location.x),
                                                    y: CGFloat(1 - p.location.y),   // bottom-left → top-left
                                                    confidence: CGFloat(p.confidence)))
            } else {
                joints.append(SkeletonOverlay.Joint(x: 0, y: 0, confidence: 0))
            }
        }
        guard presentCount >= 3 else { return nil }
        return SkeletonOverlay(id: id, kind: kind, joints: joints, bones: boneIndices)
    }

    /// Resolve name-pair bones into stable index-pair bones against a master order.
    private static func bones<Name: Hashable>(_ pairs: [(Name, Name)], in order: [Name]) -> [SkeletonOverlay.Bone] {
        let indexOf = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return pairs.compactMap { a, b in
            guard let ia = indexOf[a], let ib = indexOf[b] else { return nil }
            return SkeletonOverlay.Bone(a: ia, b: ib)
        }
    }

    // MARK: - Human topology

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
    private static let humanBones: [SkeletonOverlay.Bone] = bones([
        (.neck, .nose),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ], in: humanOrder)

    // MARK: - Animal (cat/dog) topology

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
    private static let animalBones: [SkeletonOverlay.Bone] = bones([
        (.nose, .neck),
        (.neck, .leftEarTop), (.neck, .rightEarTop),
        (.neck, .tailTop), (.tailTop, .tailMiddle), (.tailMiddle, .tailBottom),
        (.neck, .leftFrontElbow), (.leftFrontElbow, .leftFrontKnee), (.leftFrontKnee, .leftFrontPaw),
        (.neck, .rightFrontElbow), (.rightFrontElbow, .rightFrontKnee), (.rightFrontKnee, .rightFrontPaw),
        (.tailTop, .leftBackElbow), (.leftBackElbow, .leftBackKnee), (.leftBackKnee, .leftBackPaw),
        (.tailTop, .rightBackElbow), (.rightBackElbow, .rightBackKnee), (.rightBackKnee, .rightBackPaw),
    ], in: animalOrder)
}
