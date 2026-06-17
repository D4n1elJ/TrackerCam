@testable import TrackerCamCore

// Vision returns normalized coords with origin at BOTTOM-left, y upward.
// Canonical space is source pixels with origin at TOP-left, y downward (plan §10).
func runVisionGeometryTests() {
    let size = TCSize(width: 1000, height: 500)

    // Full frame maps to full pixel rect.
    expectRect(
        VisionGeometry.pixelRect(fromNormalized: TCRect(x: 0, y: 0, width: 1, height: 1), imageSize: size),
        TCRect(x: 0, y: 0, width: 1000, height: 500), "fullFrame")

    // Vision (0,0,0.5,0.5) is the bottom-left quarter → y=0.5*H in top-left space.
    expectRect(
        VisionGeometry.pixelRect(fromNormalized: TCRect(x: 0, y: 0, width: 0.5, height: 0.5), imageSize: size),
        TCRect(x: 0, y: 250, width: 500, height: 250), "bottomLeftQuadrant")

    // Arbitrary rect: x=200,w=300,h=100; top from bottom=0.8 → from top=0.2 → y=100.
    expectRect(
        VisionGeometry.pixelRect(fromNormalized: TCRect(x: 0.2, y: 0.6, width: 0.3, height: 0.2), imageSize: size),
        TCRect(x: 200, y: 100, width: 300, height: 100), "arbitrary")

    // Round trip pixel → normalized → pixel is identity.
    let src = TCSize(width: 3840, height: 2160)
    let original = TCRect(x: 812.5, y: 456.8, width: 2133.3, height: 1200.0)
    let normalized = VisionGeometry.normalizedRect(fromPixel: original, imageSize: src)
    let back = VisionGeometry.pixelRect(fromNormalized: normalized, imageSize: src)
    expectRect(back, original, tol: 1e-4, "roundTrip")
}
