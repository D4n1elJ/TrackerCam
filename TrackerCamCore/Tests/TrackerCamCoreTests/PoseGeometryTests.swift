@testable import TrackerCamCore

func runPoseGeometryTests() {
    expectClose(
        PoseGeometry.angle(
            at: TCPoint(x: 0, y: 0),
            from: TCPoint(x: 0, y: -1),
            to: TCPoint(x: 1, y: 0)) ?? -1,
        90,
        "rightAngle")

    expectClose(
        PoseGeometry.angle(
            at: TCPoint(x: 0, y: 0),
            from: TCPoint(x: -1, y: 0),
            to: TCPoint(x: 1, y: 0)) ?? -1,
        180,
        "straightAngle")

    expect(PoseGeometry.angle(at: nil, from: TCPoint(x: 0, y: 0), to: TCPoint(x: 1, y: 0)) == nil,
           "missing point produces nil angle")

    var rider = TCSkeleton()
    set(&rider, .leftHip, 0, 0)
    set(&rider, .leftKnee, 0, 1)
    set(&rider, .leftAnkle, 1, 1)
    set(&rider, .rightHip, 2, 0)
    set(&rider, .rightKnee, 2, 1)
    set(&rider, .rightAnkle, 3, 1)
    set(&rider, .leftShoulder, 0, -2)
    set(&rider, .rightShoulder, 2, -2)
    set(&rider, .leftElbow, -1, -2)
    set(&rider, .leftWrist, -1, -1)
    set(&rider, .rightElbow, 3, -2)
    set(&rider, .rightWrist, 3, -1)

    let angles = RiderAngles(rider)
    expectClose(angles.leftKnee ?? -1, 90, "leftKnee")
    expectClose(angles.rightKnee ?? -1, 90, "rightKnee")
    expectClose(angles.leftElbow ?? -1, 90, "leftElbow")
    expectClose(angles.rightElbow ?? -1, 90, "rightElbow")
    expectClose(angles.torsoLean ?? -1, 0, "torsoLean")
    expectClose(angles.hipShoulderHeelStacked ?? -1, 135, "positionLine")
    expectEqual(angles.measuredCount, 6, "measuredCount")
    expect(angles.hasAnyMeasurement, "hasAnyMeasurement")
    expectClose(
        rider.completeness(requiredJoints: TCRiderJoint.allCases.map(\.rawValue)),
        Double(rider.joints.count) / Double(TCRiderJoint.allCases.count),
        "riderCompleteness")

    var noisy = rider
    noisy.set(TCRiderJoint.leftKnee.rawValue,
              TCJoint(point: TCPoint(x: 0, y: 1), confidence: 0.05))
    expect(RiderAngles(noisy).leftKnee == nil, "low-confidence rider joint is ignored")
    expectClose(
        noisy.completeness(requiredJoints: [TCRiderJoint.leftHip.rawValue, TCRiderJoint.leftKnee.rawValue]),
        0.5,
        "lowConfidenceCompleteness")

    var smoother = TCSkeletonSmoother(positionAlpha: 0.5, confidenceAlpha: 0.5, minConfidence: 0.2)
    var first = TCSkeleton()
    first.set("knee", TCJoint(point: TCPoint(x: 0, y: 0), confidence: 0.8))
    let smoothedFirst = smoother.smooth(first)
    expectClose(smoothedFirst?.point("knee")?.x ?? -1, 0, "smoother first x")

    var second = TCSkeleton()
    second.set("knee", TCJoint(point: TCPoint(x: 10, y: 20), confidence: 0.6))
    second.set("ankle", TCJoint(point: TCPoint(x: 99, y: 99), confidence: 0.1))
    let smoothedSecond = smoother.smooth(second)
    expectClose(smoothedSecond?.point("knee")?.x ?? -1, 5, "smoother blended x")
    expectClose(smoothedSecond?.point("knee")?.y ?? -1, 10, "smoother blended y")
    expect(smoothedSecond?.point("ankle", minConfidence: 0) == nil, "smoother drops weak joints")

    expect(smoother.smooth(nil) == nil, "nil skeleton resets smoother")
    var third = TCSkeleton()
    third.set("knee", TCJoint(point: TCPoint(x: 4, y: 8), confidence: 0.7))
    let smoothedThird = smoother.smooth(third)
    expectClose(smoothedThird?.point("knee")?.x ?? -1, 4, "smoother reset x")
}

private func set(_ skeleton: inout TCSkeleton,
                 _ joint: TCRiderJoint,
                 _ x: Double,
                 _ y: Double,
                 confidence: Double = 1) {
    skeleton.set(joint.rawValue, TCJoint(point: TCPoint(x: x, y: y), confidence: confidence))
}
