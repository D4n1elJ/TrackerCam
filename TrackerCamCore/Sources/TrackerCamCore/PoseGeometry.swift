// Framework-free pose geometry for clip analysis (rider + horse).
//
// The analysis pipeline (Vision body pose / RF-DETR / a horse-keypoint model) produces named 2D
// landmarks. The MATH on those landmarks — joint angles, segment inclinations — lives here so it is
// portable and unit-testable without the platform SDK, exactly like the rest of TrackerCamCore.
//
// Coordinates: points are in a top-left origin image space (x right, y down), normalized [0,1] OR in
// pixels — the angle math is scale-invariant, so either works as long as a single skeleton is
// self-consistent. The iOS layer fills these in from VNRecognizedPoint / Core ML keypoint outputs.

import Foundation

/// A single detected landmark with a detector confidence in [0,1].
public struct TCJoint: Equatable, Sendable {
    public var point: TCPoint
    public var confidence: Double
    public init(point: TCPoint, confidence: Double) {
        self.point = point
        self.confidence = confidence
    }
}

/// A named set of landmarks for one subject in one frame. Keys are detector-defined strings
/// (`TCRiderJoint` raw values for the rider; a horse model defines its own). Generic on purpose so
/// the same geometry serves both rider and horse skeletons.
public struct TCSkeleton: Equatable, Sendable {
    public private(set) var joints: [String: TCJoint]

    public init(joints: [String: TCJoint] = [:]) { self.joints = joints }

    public mutating func set(_ name: String, _ joint: TCJoint) { joints[name] = joint }

    /// A joint, only if it clears `minConfidence` (so low-confidence noise is ignored by callers).
    public func joint(_ name: String, minConfidence: Double = 0.1) -> TCJoint? {
        guard let j = joints[name], j.confidence >= minConfidence else { return nil }
        return j
    }

    public func point(_ name: String, minConfidence: Double = 0.1) -> TCPoint? {
        joint(name, minConfidence: minConfidence)?.point
    }

    /// Mean confidence across present joints (a crude per-frame quality signal).
    public var meanConfidence: Double {
        guard !joints.isEmpty else { return 0 }
        return joints.values.reduce(0) { $0 + $1.confidence } / Double(joints.count)
    }

    public func completeness(requiredJoints: some Collection<String>) -> Double {
        guard !requiredJoints.isEmpty else { return 0 }
        let present = requiredJoints.reduce(0) { count, name in
            joint(name) == nil ? count : count + 1
        }
        return Double(present) / Double(requiredJoints.count)
    }
}

/// Confidence-aware exponential smoothing for per-frame skeletons.
///
/// `positionAlpha` is the current-frame weight. Lower values reduce jitter more; higher values follow
/// fast motion more closely. Missing/low-confidence joints are not carried forward indefinitely: if a
/// frame has no usable joints, smoothing resets so stale posture cannot leak into later analysis.
public struct TCSkeletonSmoother: Sendable {
    public var positionAlpha: Double
    public var confidenceAlpha: Double
    public var minConfidence: Double

    private var previous: TCSkeleton?

    public init(positionAlpha: Double = 0.45,
                confidenceAlpha: Double = 0.55,
                minConfidence: Double = 0.2) {
        self.positionAlpha = positionAlpha
        self.confidenceAlpha = confidenceAlpha
        self.minConfidence = minConfidence
    }

    public mutating func reset() {
        previous = nil
    }

    public mutating func smooth(_ skeleton: TCSkeleton?) -> TCSkeleton? {
        guard let skeleton else {
            reset()
            return nil
        }

        let a = clamped01(positionAlpha)
        let ca = clamped01(confidenceAlpha)
        var out = TCSkeleton()

        for (name, joint) in skeleton.joints where joint.confidence >= minConfidence {
            if let prev = previous?.joint(name, minConfidence: 0) {
                let p = TCPoint(
                    x: prev.point.x * (1 - a) + joint.point.x * a,
                    y: prev.point.y * (1 - a) + joint.point.y * a)
                let confidence = prev.confidence * (1 - ca) + joint.confidence * ca
                out.set(name, TCJoint(point: p, confidence: confidence))
            } else {
                out.set(name, joint)
            }
        }

        guard !out.joints.isEmpty else {
            reset()
            return nil
        }

        previous = out
        return out
    }

    private func clamped01(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

/// Vision's `VNHumanBodyPoseObservation.JointName` mapped to stable string keys. Using our own enum
/// keeps the core free of the Vision dependency; the iOS layer translates at the boundary.
public enum TCRiderJoint: String, CaseIterable, Sendable {
    case nose, neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
    case root // pelvis/center
}

/// Pure angle utilities. All angles in DEGREES.
public enum PoseGeometry {
    /// Interior angle at vertex `b` formed by rays b→a and b→c, in [0, 180]. nil if a point is missing
    /// or two points coincide (degenerate).
    public static func angle(at b: TCPoint?, from a: TCPoint?, to c: TCPoint?) -> Double? {
        guard let a, let b, let c else { return nil }
        let v1 = TCPoint(x: a.x - b.x, y: a.y - b.y)
        let v2 = TCPoint(x: c.x - b.x, y: c.y - b.y)
        let m1 = (v1.x * v1.x + v1.y * v1.y).squareRoot()
        let m2 = (v2.x * v2.x + v2.y * v2.y).squareRoot()
        guard m1 > 1e-9, m2 > 1e-9 else { return nil }
        let cosT = max(-1, min(1, (v1.x * v2.x + v1.y * v2.y) / (m1 * m2)))
        return acos(cosT) * 180 / .pi
    }

    /// Inclination of segment a→b relative to vertical (gravity), in [0, 180]. 0 = pointing straight
    /// up the image, 90 = horizontal. Useful for rider torso/leg uprightness.
    public static func inclinationFromVertical(_ a: TCPoint?, _ b: TCPoint?) -> Double? {
        guard let a, let b else { return nil }
        let dx = b.x - a.x
        let dy = b.y - a.y           // y is down
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 1e-9 else { return nil }
        // angle between (dx,dy) and the "up" vector (0,-1)
        let cosT = max(-1, min(1, (-dy) / len))
        return acos(cosT) * 180 / .pi
    }
}

/// Convenience derived rider metrics computed from a `TCSkeleton` of `TCRiderJoint` keys. These are
/// the equitation-relevant angles a coach cares about; extend freely.
public struct RiderAngles: Equatable, Sendable {
    public var leftKnee: Double?      // hip–knee–ankle, leg bend
    public var rightKnee: Double?
    public var leftElbow: Double?     // shoulder–elbow–wrist
    public var rightElbow: Double?
    public var torsoLean: Double?     // hip→shoulder inclination from vertical (forward/back posture)
    public var hipShoulderHeelStacked: Double? // shoulder–hip–ankle straightness (classic position line)

    public init() {}

    public init(_ s: TCSkeleton) {
        func p(_ j: TCRiderJoint) -> TCPoint? { s.point(j.rawValue) }
        leftKnee  = PoseGeometry.angle(at: p(.leftKnee),  from: p(.leftHip),  to: p(.leftAnkle))
        rightKnee = PoseGeometry.angle(at: p(.rightKnee), from: p(.rightHip), to: p(.rightAnkle))
        leftElbow  = PoseGeometry.angle(at: p(.leftElbow),  from: p(.leftShoulder),  to: p(.leftWrist))
        rightElbow = PoseGeometry.angle(at: p(.rightElbow), from: p(.rightShoulder), to: p(.rightWrist))
        // Torso: midpoint hip → midpoint shoulder.
        torsoLean = PoseGeometry.inclinationFromVertical(
            midpoint(p(.leftHip), p(.rightHip)), midpoint(p(.leftShoulder), p(.rightShoulder)))
        // Classic "ear–shoulder–hip–heel" line, sampled as shoulder–hip–ankle: 180 = perfectly stacked.
        hipShoulderHeelStacked = PoseGeometry.angle(
            at: midpoint(p(.leftHip), p(.rightHip)),
            from: midpoint(p(.leftShoulder), p(.rightShoulder)),
            to: midpoint(p(.leftAnkle), p(.rightAnkle)))
    }

    public var measuredCount: Int {
        [leftKnee, rightKnee, leftElbow, rightElbow, torsoLean, hipShoulderHeelStacked]
            .filter { $0 != nil }
            .count
    }

    public var hasAnyMeasurement: Bool {
        measuredCount > 0
    }

    private func midpoint(_ a: TCPoint?, _ b: TCPoint?) -> TCPoint? {
        switch (a, b) {
        case let (a?, b?): return TCPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }
}
