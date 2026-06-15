/// Constant-velocity Kalman filter on (x, y, vx, vy). Plan §10 Motion Smoothing.
///
/// Implemented as two independent 1-D constant-velocity filters (x and y are uncorrelated under
/// the CV model), which keeps the linear algebra to 2×2 and avoids a full 4×4 implementation.
public struct KalmanFilter2D: Sendable {
    private var fx: KalmanCV1D
    private var fy: KalmanCV1D
    public private(set) var isInitialized: Bool = false

    /// - Parameters:
    ///   - processNoise: acceleration spectral density (higher = more responsive, less smooth).
    ///   - measurementNoise: measurement variance (higher = more smoothing, less reactive).
    public init(processNoise: Double, measurementNoise: Double) {
        fx = KalmanCV1D(processNoise: processNoise, measurementNoise: measurementNoise)
        fy = KalmanCV1D(processNoise: processNoise, measurementNoise: measurementNoise)
    }

    public var position: TCPoint { TCPoint(x: fx.position, y: fy.position) }
    public var velocity: TCPoint { TCPoint(x: fx.velocity, y: fy.velocity) }

    /// Advance the state forward by `dt` seconds. No-op until the first measurement.
    public mutating func predict(dt: Double) {
        guard isInitialized else { return }
        fx.predict(dt: dt)
        fy.predict(dt: dt)
    }

    /// Fold in a position measurement, initializing on the first call.
    public mutating func update(measurement: TCPoint) {
        if !isInitialized {
            fx.initialize(position: measurement.x)
            fy.initialize(position: measurement.y)
            isInitialized = true
            return
        }
        fx.update(measurement: measurement.x)
        fy.update(measurement: measurement.y)
    }
}

/// Scalar constant-velocity Kalman filter with state [position, velocity].
struct KalmanCV1D: Sendable {
    private let q: Double  // process (acceleration) noise density
    private let r: Double  // measurement variance

    var position: Double = 0
    var velocity: Double = 0

    // Covariance matrix P (symmetric 2×2): p00 p01 / p10 p11.
    private var p00 = 1e9
    private var p01 = 0.0
    private var p10 = 0.0
    private var p11 = 1e9

    init(processNoise: Double, measurementNoise: Double) {
        q = processNoise
        r = measurementNoise
    }

    mutating func initialize(position: Double) {
        // Seed the estimate at the measurement with small position uncertainty and
        // large velocity uncertainty (velocity is still unknown after one sample).
        self.position = position
        velocity = 0
        p00 = r
        p01 = 0
        p10 = 0
        p11 = 1e6
    }

    /// Predict: x' = F x ; P' = F P Fᵀ + Q, with F = [[1, dt],[0, 1]].
    mutating func predict(dt: Double) {
        position += velocity * dt

        // P' = F P Fᵀ
        let np00 = p00 + dt * (p10 + p01) + dt * dt * p11
        let np01 = p01 + dt * p11
        let np10 = p10 + dt * p11
        let np11 = p11

        // + Q (continuous white-acceleration model, spectral density q).
        let dt2 = dt * dt
        let dt3 = dt2 * dt
        let dt4 = dt2 * dt2
        p00 = np00 + q * dt4 / 4.0
        p01 = np01 + q * dt3 / 2.0
        p10 = np10 + q * dt3 / 2.0
        p11 = np11 + q * dt2
    }

    /// Update with scalar position measurement z. H = [1, 0], R = r.
    mutating func update(measurement z: Double) {
        let y = z - position          // innovation
        let s = p00 + r               // innovation covariance
        let k0 = p00 / s              // Kalman gain
        let k1 = p10 / s

        position += k0 * y
        velocity += k1 * y

        // P = (I - K H) P
        let np00 = (1 - k0) * p00
        let np01 = (1 - k0) * p01
        let np10 = p10 - k1 * p00
        let np11 = p11 - k1 * p01
        p00 = np00
        p01 = np01
        p10 = np10
        p11 = np11
    }
}
