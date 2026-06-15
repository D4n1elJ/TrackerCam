// Stateful crop smoothing/rate-limiting. Plan §10 (Dynamic Zoom Controller, Motion Smoothing).
func runCropControllerTests() {
    let source = TCRect(x: 0, y: 0, width: 3840, height: 2160)

    // First update snaps to the desired crop (clamped into the source).
    var snap = CropController()
    let r0 = snap.update(dt: 1.0/30, desiredCenter: TCPoint(x: 1920, y: 1080),
                         desiredSize: TCSize(width: 1920, height: 1080), source: source)
    expectRect(r0, TCRect(x: 960, y: 540, width: 1920, height: 1080), tol: 1e-6, "snap")
    expect(snap.isInitialized, "initialized after first update")

    // First update with an off-source center still clamps inside the source.
    var corner = CropController()
    let rc = corner.update(dt: 1.0/30, desiredCenter: TCPoint(x: 0, y: 0),
                           desiredSize: TCSize(width: 1920, height: 1080), source: source)
    expectRect(rc, TCRect(x: 0, y: 0, width: 1920, height: 1080), tol: 1e-6, "corner clamp")

    // Center-speed limit: max move = maxCenterSpeed * sourceWidth * dt = 1.5 * 3840 * 0.1 = 576.
    var pan = CropController()
    _ = pan.update(dt: 0.1, desiredCenter: TCPoint(x: 1920, y: 1080),
                   desiredSize: TCSize(width: 1920, height: 1080), source: source)
    let r1 = pan.update(dt: 0.1, desiredCenter: TCPoint(x: 3000, y: 1080),
                        desiredSize: TCSize(width: 1920, height: 1080), source: source)
    expectClose(r1.midX, 1920 + 576, tol: 1e-6, "center speed-limited")
    expectClose(r1.midY, 1080, tol: 1e-6, "center y unchanged")

    // Zoom OUT is fast: ratio capped at 1 + 0.8*dt. From height 1080, dt 0.1 → ≤ 1080*1.08 = 1166.4.
    var zoomOut = CropController()
    _ = zoomOut.update(dt: 0.1, desiredCenter: TCPoint(x: 1920, y: 1080),
                       desiredSize: TCSize(width: 1920, height: 1080), source: source)
    let ro = zoomOut.update(dt: 0.1, desiredCenter: TCPoint(x: 1920, y: 1080),
                            desiredSize: TCSize(width: 3840, height: 2160), source: source)
    expectClose(ro.height, 1166.4, tol: 1e-4, "zoom out rate")
    expectClose(ro.width, 1166.4 * 16.0 / 9.0, tol: 1e-3, "zoom out keeps aspect")

    // Zoom IN is slow: ratio floored at 1 - 0.25*dt. From height 1080, dt 0.1 → ≥ 1080*0.975 = 1053.
    // (hold 0 here to isolate the rate from the hysteresis hold.)
    var zoomIn = CropController(zoomInHoldSeconds: 0)
    _ = zoomIn.update(dt: 0.1, desiredCenter: TCPoint(x: 1920, y: 1080),
                      desiredSize: TCSize(width: 1920, height: 1080), source: source)
    let ri = zoomIn.update(dt: 0.1, desiredCenter: TCPoint(x: 1920, y: 1080),
                           desiredSize: TCSize(width: 960, height: 540), source: source)
    expectClose(ri.height, 1053, tol: 1e-4, "zoom in rate (slower)")

    // reset() returns to uninitialized so the next update snaps again.
    zoomIn.reset()
    expect(!zoomIn.isInitialized, "reset clears initialization")

    // --- Hysteresis: zoom-in is suppressed until the desired crop has stayed below the band 150ms ---
    var hys = CropController()  // band 0.05, hold 0.15
    _ = hys.update(dt: 0.05, desiredCenter: TCPoint(x: 1920, y: 1080),
                   desiredSize: TCSize(width: 1920, height: 1080), source: source) // init height 1080
    let h1 = hys.update(dt: 0.05, desiredCenter: TCPoint(x: 1920, y: 1080),
                        desiredSize: TCSize(width: 960, height: 540), source: source) // tb=0.05 < 0.15
    expectClose(h1.height, 1080, tol: 1e-6, "zoom-in suppressed before hold (frame 1)")
    let h2 = hys.update(dt: 0.05, desiredCenter: TCPoint(x: 1920, y: 1080),
                        desiredSize: TCSize(width: 960, height: 540), source: source) // tb=0.10
    expectClose(h2.height, 1080, tol: 1e-6, "zoom-in suppressed (frame 2)")
    let h3 = hys.update(dt: 0.05, desiredCenter: TCPoint(x: 1920, y: 1080),
                        desiredSize: TCSize(width: 960, height: 540), source: source) // tb=0.15 → eligible
    expectClose(h3.height, 1080 * (1 - 0.25 * 0.05), tol: 1e-4, "zoom-in begins after hold") // 1066.5

    // A small desired shrink WITHIN the 5% band never triggers zoom-in, regardless of time.
    var band = CropController()
    _ = band.update(dt: 0.05, desiredCenter: TCPoint(x: 1920, y: 1080),
                    desiredSize: TCSize(width: 1920, height: 1080), source: source) // height 1080
    let b1 = band.update(dt: 1.0, desiredCenter: TCPoint(x: 1920, y: 1080),
                         desiredSize: TCSize(width: 1050 * 16.0 / 9.0, height: 1050), source: source) // 1050 > 1026
    expectClose(b1.height, 1080, tol: 1e-6, "within-band shrink never zooms in")
}
