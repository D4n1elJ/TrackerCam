/// Tracking lifecycle states. Plan §8 Tracking State Machine.
public enum TrackingState: String, Equatable, Sendable {
    case idle       // no target requested
    case searching  // detector running, awaiting a stable track
    case locked     // visual confirmation / haptic, brief hold
    case tracking   // normal operation
    case lost       // track confidence collapsed; prompt re-acquire
}

/// Time-based thresholds. Durations are authoritative (seconds) so behavior is identical at
/// 30/60/120 fps capture presets. Defaults from plan §8/§13.
public struct TrackingConfig: Sendable {
    public var lockConfirmation: Double
    public var lostTimeout: Double
    public var confidenceThreshold: Double
    public var lockedHoldDuration: Double

    public init(lockConfirmation: Double = 0.17,
                lostTimeout: Double = 0.33,
                confidenceThreshold: Double = 0.5,
                lockedHoldDuration: Double = 0.3) {
        self.lockConfirmation = lockConfirmation
        self.lostTimeout = lostTimeout
        self.confidenceThreshold = confidenceThreshold
        self.lockedHoldDuration = lockedHoldDuration
    }
}

/// Drives tracking-state transitions from per-frame confidence observations and timestamps.
public struct TrackingStateMachine: Sendable {
    public private(set) var state: TrackingState = .idle
    private let config: TrackingConfig

    private var stateEnteredAt: Double = 0
    /// Start of the current uninterrupted run of confidence ≥ threshold (nil while below).
    private var goodSince: Double?
    /// Start of the current uninterrupted run of confidence < threshold (nil while above).
    private var badSince: Double?

    public init(config: TrackingConfig = TrackingConfig()) {
        self.config = config
    }

    /// Request acquisition of a new target (manual tap / auto seed). Valid from idle or lost.
    public mutating func startAcquisition(at time: Double) {
        guard state == .idle || state == .lost else { return }
        enter(.searching, at: time)
        goodSince = nil
        badSince = nil
    }

    public mutating func reset() {
        enter(.idle, at: stateEnteredAt)
        goodSince = nil
        badSince = nil
    }

    /// Feed one per-frame confidence sample at its timestamp and advance the state machine.
    public mutating func observe(confidence: Double, at time: Double) {
        guard state != .idle else { return }  // must startAcquisition first

        // Maintain the good/bad confidence runs.
        if confidence >= config.confidenceThreshold {
            if goodSince == nil { goodSince = time }
            badSince = nil
        } else {
            if badSince == nil { badSince = time }
            goodSince = nil
        }

        switch state {
        case .idle:
            break
        case .searching:
            if let gs = goodSince, time - gs >= config.lockConfirmation {
                enter(.locked, at: time)
            }
        case .locked:
            if let bs = badSince, time - bs >= config.lostTimeout {
                enter(.lost, at: time)
            } else if goodSince != nil, time - stateEnteredAt >= config.lockedHoldDuration {
                enter(.tracking, at: time)
            }
        case .tracking:
            if let bs = badSince, time - bs >= config.lostTimeout {
                enter(.lost, at: time)
            }
        case .lost:
            if goodSince != nil {
                enter(.searching, at: time)  // begin re-confirmation toward a fresh lock
            }
        }
    }

    private mutating func enter(_ newState: TrackingState, at time: Double) {
        state = newState
        stateEnteredAt = time
    }
}
