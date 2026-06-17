@testable import TrackerCamCore

// Operator pan/aim guidance. Plan §11 Framing Guidance System.
func runGuidanceEngineTests() {
    let source = TCRect(x: 0, y: 0, width: 4000, height: 2000) // center (2000,1000)
    let engine = GuidanceEngine(deadZoneFraction: 0.1, lookaheadSeconds: 0.5)
    let centeredCrop = TCRect(x: 1500, y: 750, width: 1000, height: 500) // ample headroom (0.5 each)

    // Centered subject, no motion → inside dead zone → no hint.
    let none = engine.hint(subjectCenter: TCPoint(x: 2000, y: 1000), predictedVelocity: .zero,
                           source: source, crop: centeredCrop)
    expectEqual(none.severity, GuidanceEngine.Severity.none, "dead zone → none")

    // Off-center beyond dead zone, ample headroom → normal, pointing right.
    let normal = engine.hint(subjectCenter: TCPoint(x: 3000, y: 1000), predictedVelocity: .zero,
                             source: source, crop: centeredCrop)
    expectEqual(normal.severity, GuidanceEngine.Severity.normal, "ample headroom → normal")
    expectClose(normal.direction.x, 1.0, tol: 1e-9, "points right")
    expectClose(normal.magnitude, 0.25, tol: 1e-9, "magnitude = errorX/width")

    // Centered subject but predicted drift pushes it out of the dead zone.
    let drift = engine.hint(subjectCenter: TCPoint(x: 2000, y: 1000), predictedVelocity: TCPoint(x: 2000, y: 0),
                            source: source, crop: centeredCrop)
    expectEqual(drift.severity, GuidanceEngine.Severity.normal, "drift triggers a hint")
    expectClose(drift.direction.x, 1.0, tol: 1e-9, "drift points right")
    expectClose(drift.magnitude, 0.25, tol: 1e-9, "drift magnitude = vx*lookahead/width")

    // Crop near the right edge → amber (right headroom 0.15).
    let amberCrop = TCRect(x: 2550, y: 750, width: 1000, height: 500) // right = (4000-3550)/3000 = 0.15
    let amber = engine.hint(subjectCenter: TCPoint(x: 3000, y: 1000), predictedVelocity: .zero,
                            source: source, crop: amberCrop)
    expectEqual(amber.severity, GuidanceEngine.Severity.amber, "0.15 headroom → amber")

    // Crop at the right wall → red (right headroom ≈ 0.017).
    let redCrop = TCRect(x: 2950, y: 750, width: 1000, height: 500) // right = (4000-3950)/3000 ≈ 0.017
    let red = engine.hint(subjectCenter: TCPoint(x: 3000, y: 1000), predictedVelocity: .zero,
                          source: source, crop: redCrop)
    expectEqual(red.severity, GuidanceEngine.Severity.red, "near-wall → red")
}
