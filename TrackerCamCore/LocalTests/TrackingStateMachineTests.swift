// Tracking state machine. Plan §8 Tracking State Machine.
// Durations are authoritative (seconds); transitions are time-based so behavior is fps-independent.
func runTrackingStateMachineTests() {
    let cfg = TrackingConfig() // defaults: lockConfirm 0.17, lostTimeout 0.33, threshold 0.5, lockedHold 0.3

    // idle ignores observations until acquisition starts.
    var idle = TrackingStateMachine(config: cfg)
    expectEqual(idle.state, .idle, "starts idle")
    idle.observe(confidence: 0.9, at: 0.0)
    expectEqual(idle.state, .idle, "idle without acquisition")

    // Full happy path: searching → locked → tracking.
    var sm = TrackingStateMachine(config: cfg)
    sm.startAcquisition(at: 0.0)
    expectEqual(sm.state, .searching, "acquisition → searching")
    sm.observe(confidence: 0.9, at: 0.0)
    sm.observe(confidence: 0.9, at: 0.1)
    expectEqual(sm.state, .searching, "not yet locked before lockConfirmation")
    sm.observe(confidence: 0.9, at: 0.2)        // 0.2 ≥ 0.17
    expectEqual(sm.state, .locked, "locked after sustained confidence")
    sm.observe(confidence: 0.9, at: 0.3)
    expectEqual(sm.state, .locked, "still locked during hold")
    sm.observe(confidence: 0.9, at: 0.55)       // 0.55 - 0.2 = 0.35 ≥ 0.3
    expectEqual(sm.state, .tracking, "locked → tracking after hold")

    // tracking → lost after lostTimeout of low confidence; brief dips do not drop.
    sm.observe(confidence: 0.1, at: 0.6)
    sm.observe(confidence: 0.1, at: 0.9)        // 0.3 < 0.33
    expectEqual(sm.state, .tracking, "brief low-confidence dip holds tracking")
    sm.observe(confidence: 0.1, at: 1.0)        // 0.4 ≥ 0.33
    expectEqual(sm.state, .lost, "tracking → lost after timeout")

    // lost recovers to searching on good confidence.
    sm.observe(confidence: 0.9, at: 1.1)
    expectEqual(sm.state, .searching, "lost → searching on recovery")

    // A confidence dip during searching resets the lock timer (lock needs CONTINUOUS confidence).
    var reset = TrackingStateMachine(config: cfg)
    reset.startAcquisition(at: 0.0)
    reset.observe(confidence: 0.9, at: 0.0)
    reset.observe(confidence: 0.2, at: 0.1)     // resets good run
    reset.observe(confidence: 0.9, at: 0.15)    // good run restarts at 0.15
    reset.observe(confidence: 0.9, at: 0.30)    // 0.15 elapsed < 0.17
    expectEqual(reset.state, .searching, "dip reset the lock timer")
    reset.observe(confidence: 0.9, at: 0.33)    // 0.18 ≥ 0.17
    expectEqual(reset.state, .locked, "locks after continuous confidence post-reset")

    // A mid-tracking recovery clears the loss timer so it does not trip later.
    var recover = TrackingStateMachine(config: cfg)
    recover.startAcquisition(at: 0.0)
    recover.observe(confidence: 0.9, at: 0.0)   // good run starts at 0.0
    recover.observe(confidence: 0.9, at: 0.2)   // locked (0.2 ≥ 0.17)
    recover.observe(confidence: 0.9, at: 0.55)  // tracking (0.35 ≥ 0.3)
    recover.observe(confidence: 0.1, at: 0.6)   // bad run starts
    recover.observe(confidence: 0.9, at: 0.7)   // recovers — bad run cleared
    recover.observe(confidence: 0.1, at: 0.9)   // new bad run from 0.9
    recover.observe(confidence: 0.1, at: 1.1)   // 0.2 < 0.33
    expectEqual(recover.state, .tracking, "recovery cleared the earlier loss timer")

    // reset() returns to idle.
    recover.reset()
    expectEqual(recover.state, .idle, "reset → idle")
}
