@testable import TrackerCamCore

// Robustness for on-device edge cases (degenerate dt, zero sizes, oversize crops).
func runEdgeCaseTests() {
    let source = TCRect(x: 0, y: 0, width: 3840, height: 2160)

    // dt == 0 (two frames sharing a PTS): crop stays stable, no NaN/blowup.
    var cc = CropController()
    _ = cc.update(dt: 1.0 / 60, desiredCenter: TCPoint(x: 1920, y: 1080),
                  desiredSize: TCSize(width: 1920, height: 1080), source: source)
    let r = cc.update(dt: 0, desiredCenter: TCPoint(x: 3000, y: 1500),
                      desiredSize: TCSize(width: 800, height: 450), source: source)
    expect(r.isFiniteAndPositive, "dt=0 yields a finite, positive crop")
    expectClose(r.midX, 1920, tol: 1e-6, "dt=0 holds center")
    expectClose(r.height, 1080, tol: 1e-6, "dt=0 holds size")

    // VisionGeometry guards a zero-size image (no divide-by-zero).
    let n = VisionGeometry.normalizedRect(fromPixel: TCRect(x: 0, y: 0, width: 10, height: 10),
                                          imageSize: .zero)
    expectEqual(n, TCRect.zero, "zero image → zero normalized rect")

    // clampedCrop with a crop far larger than the source scales down to fit, stays inside.
    let big = CropMath.clampedCrop(center: TCPoint(x: 0, y: 0),
                                   size: TCSize(width: 9000, height: 5000), source: source)
    expect(big.minX >= -1e-6 && big.minY >= -1e-6, "clamped origin inside source")
    expect(big.maxX <= source.width + 1e-6 && big.maxY <= source.height + 1e-6, "clamped fits source")

    // Guidance inside the dead zone → no hint (plan §11: |hint| < deadZone). 0.05 < 0.1.
    let g = GuidanceEngine(deadZoneFraction: 0.1, lookaheadSeconds: 0)
    let inside = g.hint(subjectCenter: TCPoint(x: source.midX + 0.05 * source.width, y: source.midY),
                        predictedVelocity: .zero, source: source, crop: source)
    expectEqual(inside.severity, GuidanceEngine.Severity.none, "inside dead zone → no hint")
}
