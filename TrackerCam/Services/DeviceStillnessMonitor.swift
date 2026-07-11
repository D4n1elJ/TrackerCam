import CoreMotion
import QuartzCore

/// Gyro-based "is the camera physically still?" signal (tripod, or deliberately held steady).
///
/// Motion-centering infers the subject position from frame-difference motion, which is only
/// meaningful when the camera itself is not moving — a handheld pan turns the whole frame into
/// "motion" and the centroid into noise. This monitor gates that path so the tracker stays the
/// primary crop signal whenever the operator is moving the phone.
///
/// Pull model: `CMMotionManager` samples device motion in the background; `isStill()` evaluates
/// the latest sample on read (once per frame from the pipeline). Entering stillness requires a
/// sustained quiet window so brief pauses mid-pan don't flip the gate.
@MainActor
final class DeviceStillnessMonitor {
    /// Rotation-rate magnitude below which the device counts as quiet (rad/s). Hand tremor while
    /// deliberately holding still is ~0.02–0.05; an intentional pan is an order of magnitude above.
    private static let quietRotationRate = 0.05
    /// User (gravity-removed) acceleration magnitude below which the device counts as quiet (g).
    private static let quietAcceleration = 0.04
    /// The device must stay quiet this long before motion-centering may steer the crop.
    private static let sustainSeconds = 0.5

    private let manager = CMMotionManager()
    private var quietSince: Double?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        quietSince = nil
    }

    /// True when the camera has been physically still for the sustained window.
    ///
    /// Without sensor data the answer is platform-dependent: the simulator has no gyro but drives
    /// the pipeline from a static-camera fixture clip (still = true keeps that validation path
    /// working); on device, missing data means "unknown", which must read as moving so the
    /// tracker stays primary.
    func isStill() -> Bool {
#if targetEnvironment(simulator)
        return true
#else
        guard let motion = manager.deviceMotion else {
            quietSince = nil
            return false
        }
        let r = motion.rotationRate
        let a = motion.userAcceleration
        let rotation = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        let acceleration = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        guard rotation < Self.quietRotationRate, acceleration < Self.quietAcceleration else {
            quietSince = nil
            return false
        }
        let now = CACurrentMediaTime()
        if quietSince == nil { quietSince = now }
        return now - (quietSince ?? now) >= Self.sustainSeconds
#endif
    }
}
