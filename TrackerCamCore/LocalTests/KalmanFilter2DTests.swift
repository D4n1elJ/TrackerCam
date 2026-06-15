// Constant-velocity Kalman filter on (x, y, vx, vy). See plan §10 Motion Smoothing.
func runKalmanTests() {
    // First update initializes the estimate to the measurement.
    var initKF = KalmanFilter2D(processNoise: 1.0, measurementNoise: 1.0)
    expect(!initKF.isInitialized, "starts uninitialized")
    initKF.update(measurement: TCPoint(x: 7, y: 9))
    expect(initKF.isInitialized, "initialized after first update")
    expectClose(initKF.position.x, 7, tol: 1e-3, "init x")
    expectClose(initKF.position.y, 9, tol: 1e-3, "init y")

    // Predict before initialization is a no-op (no measurement yet).
    var emptyKF = KalmanFilter2D(processNoise: 1.0, measurementNoise: 1.0)
    emptyKF.predict(dt: 1.0)
    expect(!emptyKF.isInitialized, "predict before init stays uninitialized")

    // Feed perfect constant-velocity measurements; estimate must converge to truth.
    // Distinct vx/vy to catch axis swaps.
    var kf = KalmanFilter2D(processNoise: 1.0, measurementNoise: 1.0)
    let vx = 10.0, vy = -4.0, dt = 1.0
    let x0 = 100.0, y0 = 50.0
    let steps = 60
    for k in 0...steps {
        let t = Double(k)
        kf.predict(dt: dt)
        kf.update(measurement: TCPoint(x: x0 + vx * t, y: y0 + vy * t))
    }
    expectClose(kf.velocity.x, vx, tol: 0.5, "converged vx")
    expectClose(kf.velocity.y, vy, tol: 0.5, "converged vy")
    let lastT = Double(steps)
    expectClose(kf.position.x, x0 + vx * lastT, tol: 1.0, "converged px")
    expectClose(kf.position.y, y0 + vy * lastT, tol: 1.0, "converged py")

    // A pure predict step advances position by the current velocity estimate.
    let beforeX = kf.position.x
    let beforeY = kf.position.y
    let vX = kf.velocity.x
    let vY = kf.velocity.y
    kf.predict(dt: 2.0)
    expectClose(kf.position.x, beforeX + vX * 2.0, tol: 1e-9, "predict advances x")
    expectClose(kf.position.y, beforeY + vY * 2.0, tol: 1e-9, "predict advances y")
}
