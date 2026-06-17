import Vision
import CoreMedia
import CoreVideo
import TrackerCamCore

/// Detection + tracking + smoothing, producing a timestamped `TrackingResult`.
/// Wires Vision (hardware) to the verified core logic: `TrackingStateMachine`, `KalmanFilter2D`,
/// `VisionGeometry`, `CropMath`. Plan §8.
///
/// API-resolution note (plan §8): `TrackObjectRequest` exists in the new Swift Vision API and returns
/// `DetectedObjectObservation` (position + velocity), but its cross-frame state mechanism must be
/// confirmed on the iOS 26 SDK. This engine isolates that boundary; the `track(...)` body is the one
/// place to swap between the new value-type request and `VNSequenceRequestHandler` + `VNTrackObjectRequest`.
actor TrackingEngine {
    struct TrackingResult: Sendable {
        var state: TrackingState
        var subjectPixelRect: TCRect?     // compound (horse+rider) box in source pixels
        var smoothedCenter: TCPoint?
        var velocity: TCPoint
        var confidence: Double
        var presentationTime: CMTime
        var sessionGeneration: UInt64
    }

    private var stateMachine: TrackingStateMachine
    private var kalman: KalmanFilter2D
    private var settings: TrackerSettings
    private var currentSeed: TCRect?
    private var lastObservationPTS: CMTime = .invalid
    private var lastSeconds: Double = 0   // most recent frame PTS in seconds, for seed timing

    // Vision tracking handle (established API; see API-resolution note above).
    private var sequenceHandler = VNSequenceRequestHandler()
    private var trackingRequest: VNTrackObjectRequest?
    private var trackingLevel: VNRequestTrackingLevel = .accurate

    init(settings: TrackerSettings) {
        self.settings = settings
        self.stateMachine = TrackingStateMachine(config: settings.trackingConfig)
        self.kalman = KalmanFilter2D(
            processNoise: Self.processNoise(for: settings.smoothingStrength),
            measurementNoise: 1.0
        )
    }

    func updateSettings(_ newSettings: TrackerSettings) {
        settings = newSettings
        stateMachine = TrackingStateMachine(config: newSettings.trackingConfig)
    }

    /// Release the current target and return to idle (double-tap "let go").
    func clearTarget() {
        currentSeed = nil
        trackingRequest = nil
        stateMachine.reset()
        kalman = KalmanFilter2D(
            processNoise: Self.processNoise(for: settings.smoothingStrength),
            measurementNoise: 1.0
        )
    }

    /// Manual / auto seed (tap-to-track or Refocus). `pixelRect` is in source pixels.
    /// Uses the most recent frame timestamp internally so the state machine clock stays monotonic.
    func seed(pixelRect: TCRect) {
        currentSeed = pixelRect
        trackingRequest = nil          // re-seed Vision tracker on next frame
        stateMachine.startAcquisition(at: lastSeconds)
        kalman = KalmanFilter2D(
            processNoise: Self.processNoise(for: settings.smoothingStrength),
            measurementNoise: 1.0
        )
    }

    /// Frame-to-frame tracking on the (downscaled) analysis buffer. Coordinates are normalized, so a
    /// reduced-resolution buffer tracks identically while costing far less CPU/ANE than the full 4K
    /// frame. `fast` selects Vision's `.fast` tracking level under thermal pressure (plan §15).
    /// Detection runs separately and feeds results via `applyDetection` (plan §6 analysis branch).
    func track(visionPayload: FramePayload, fast: Bool) async -> TrackingResult {
        // FramePayload is @unchecked Sendable, so the non-Sendable buffer crosses into this actor
        // under our single-owner contract.
        let pixelBuffer = visionPayload.pixelBuffer
        let context = visionPayload.context
        let t = context.presentationTime
        lastSeconds = t.secondsOrZero
        // Coordinate math uses the *true* source dimensions (from the context), not the analysis
        // buffer's size, so normalized Vision results map back to full-resolution source pixels.
        let sourceSize = TCSize(width: Double(context.sourceDimensions.width),
                                height: Double(context.sourceDimensions.height))

        var confidence = 0.0
        var subjectPixel: TCRect? = currentSeed

        // Frame-to-frame tracking via Vision (established API).
        let desiredLevel: VNRequestTrackingLevel = fast ? .fast : .accurate
        if let seed = currentSeed {
            if trackingRequest == nil || trackingLevel != desiredLevel {
                let normalizedSeed = VisionGeometry.normalizedRect(fromPixel: seed, imageSize: sourceSize)
                let req = VNTrackObjectRequest(detectedObjectObservation:
                    VNDetectedObjectObservation(boundingBox: normalizedSeed.cg))
                req.trackingLevel = desiredLevel

                trackingRequest = req
                trackingLevel = desiredLevel
            }
            if let req = trackingRequest {
                try? sequenceHandler.perform([req], on: pixelBuffer)
                if let obs = req.results?.first as? VNDetectedObjectObservation {
                    let pixel = VisionGeometry.pixelRect(fromNormalized: TCRect(obs.boundingBox), imageSize: sourceSize)
                    subjectPixel = pixel
                    confidence = max(confidence, Double(obs.confidence))
                    currentSeed = pixel
                }
            }
        }

        // Feed the state machine and smoother.
        stateMachine.observe(confidence: confidence, at: lastSeconds)
        if let s = subjectPixel {
            kalman.predictIfNeeded(to: lastSeconds, last: &lastObservationPTS)
            kalman.update(measurement: s.center)
        }

        return TrackingResult(
            state: stateMachine.state,
            subjectPixelRect: subjectPixel,
            smoothedCenter: kalman.isInitialized ? kalman.position : nil,
            velocity: kalman.velocity,
            confidence: confidence,
            presentationTime: t,
            sessionGeneration: context.sessionGeneration
        )
    }

    /// Apply a detection result (computed off the per-frame path on the downscaled buffer): refresh
    /// the tracker seed and feed its confidence so lock/recovery transitions still progress. The next
    /// `track(...)` re-seeds the Vision tracker from this box. Ignored while idle (no acquisition
    /// requested), matching the tap/refocus-to-acquire model.
    func applyDetection(pixelRect: TCRect, confidence: Double) {
        currentSeed = pixelRect
        trackingRequest = nil
        if stateMachine.state != .idle {
            stateMachine.observe(confidence: confidence, at: lastSeconds)
        }
    }

    private static func processNoise(for smoothingStrength: Double) -> Double {
        // Lower smoothing strength → more responsive (higher process noise). Map [0,1] → [50, 1].
        let s = max(0, min(1, smoothingStrength))
        return 50.0 * (1.0 - s) + 1.0
    }
}

private extension KalmanFilter2D {
    /// Advance the filter to `time` using the elapsed wall-time since the last observation.
    mutating func predictIfNeeded(to time: Double, last: inout CMTime) {
        if last.isValid {
            let dt = time - last.seconds
            if dt > 0 { predict(dt: dt) }
        }
        last = CMTime(seconds: time, preferredTimescale: 600)
    }
}

extension CMTime {
    /// Seconds as Double, 0 when invalid (analysis math tolerates this; recording never retimes).
    var secondsOrZero: Double { isValid ? seconds : 0 }
}
