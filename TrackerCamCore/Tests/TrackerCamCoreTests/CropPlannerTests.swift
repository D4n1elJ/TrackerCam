@testable import TrackerCamCore

// Per-state desired-crop planning incl. the lost ladder. Plan §10 Crop State Machine.
func runCropPlannerTests() {
    let planner = CropPlanner() // lostPredict 0.75s, easeEnd 2.0s, searchingWiden 0.15
    let source = TCRect(x: 0, y: 0, width: 3840, height: 2160)
    let defaultSize = TCSize(width: 1920, height: 1080)         // 16:9 → max-zoom-out == full source
    let last = TCPoint(x: 1000, y: 500)
    let vel = TCPoint(x: 200, y: 0)
    let trackCenter = TCPoint(x: 1400, y: 700)
    let trackSize = TCSize(width: 1600, height: 900)

    func plan(_ state: TrackingState, _ tSinceLost: Double) -> (center: TCPoint, size: TCSize) {
        planner.plan(state: state, secondsSinceLost: tSinceLost,
                     lastCenter: last, velocity: vel,
                     trackingDesiredCenter: trackCenter, trackingDesiredSize: trackSize,
                     defaultSize: defaultSize, source: source)
    }

    // idle → centered default crop.
    let idle = plan(.idle, 0)
    expectClose(idle.center.x, source.midX, tol: 1e-6, "idle center x")
    expectClose(idle.size.height, 1080, tol: 1e-6, "idle size")

    // searching → hold last position, target 15% wider than default.
    let searching = plan(.searching, 0)
    expectClose(searching.center.x, last.x, tol: 1e-6, "searching holds position")
    expectClose(searching.size.width, 1920 * 1.15, tol: 1e-6, "searching widened w")
    expectClose(searching.size.height, 1080 * 1.15, tol: 1e-6, "searching widened h")

    // tracking → pass through the active composed target.
    let tracking = plan(.tracking, 0)
    expectClose(tracking.center.x, trackCenter.x, tol: 1e-6, "tracking center passthrough")
    expectClose(tracking.size.width, trackSize.width, tol: 1e-6, "tracking size passthrough")

    // locked → same active target (controller eases via its rate limits).
    let locked = plan(.locked, 0)
    expectClose(locked.center.x, trackCenter.x, tol: 1e-6, "locked center passthrough")

    // lost < 0.75s → constant-velocity prediction + max zoom-out (full source for 16:9).
    let lostEarly = plan(.lost, 0.5)
    expectClose(lostEarly.center.x, 1000 + 200 * 0.5, tol: 1e-6, "lost predict x")  // 1100
    expectClose(lostEarly.size.width, 3840, tol: 1e-6, "lost zoom-out w")
    expectClose(lostEarly.size.height, 2160, tol: 1e-6, "lost zoom-out h")

    // lost 0.75–2.0s → ease predicted(@0.75) toward source center. At t=1.375 factor=0.5.
    // predicted@0.75 = 1000 + 200*0.75 = 1150; lerp(1150, 1920, 0.5) = 1535.
    let lostMid = plan(.lost, 1.375)
    expectClose(lostMid.center.x, 1535, tol: 1e-6, "lost ease x")
    expectClose(lostMid.size.width, 3840, tol: 1e-6, "lost ease still wide")

    // lost > 2.0s → hold centered max zoom-out.
    let lostLate = plan(.lost, 3.0)
    expectClose(lostLate.center.x, source.midX, tol: 1e-6, "lost hold center x")
    expectClose(lostLate.center.y, source.midY, tol: 1e-6, "lost hold center y")
    expectClose(lostLate.size.width, 3840, tol: 1e-6, "lost hold wide")
}
