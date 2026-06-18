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
        var visionFailureCount: Int
        var lastVisionErrorDescription: String?
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
    private var visionFailureCount = 0
    private var lastVisionErrorDescription: String?
    private var manualSeedTrustFrames = 0

    // CPU correlation-filter tracker (CorrelationTracker.swift — codex implements the algorithm).
    // Enabled in the simulator, where Vision's ANE-backed tracker can't run; flip the device branch
    // to `true` once it's proven to out-track VNTrackObjectRequest on hardware.
    private var correlationTracker: CorrelationTracker?
    #if targetEnvironment(simulator)
    private let usesCorrelationTracker = true
    #else
    private let usesCorrelationTracker = false
    #endif

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
        sequenceHandler = VNSequenceRequestHandler()
        correlationTracker = nil
        manualSeedTrustFrames = 0
        visionFailureCount = 0
        lastVisionErrorDescription = nil
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
        sequenceHandler = VNSequenceRequestHandler()
        correlationTracker = nil       // re-seed correlation tracker on next frame
        manualSeedTrustFrames = 12     // user taps are intentional; let Vision establish its track.
        stateMachine.reset()
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
        var acceptedMeasurement: TCRect?
        var frameVisionError: String?

        // --- CPU correlation-filter tracker path (CorrelationTracker.swift) ---
        // Runs on the luma plane, so it works in the simulator (no ANE) and avoids Vision's drift.
        // codex implements the algorithm; this wiring drives it behind the same measurement contract.
        // NOTE: the luma plane is the DOWNSCALED analysis buffer — CorrelationTracker maps the
        // source-pixel box ↔ plane pixels via (luma.width / source.width). The sanity gate
        // (acceptsVisionMeasurement) applies regardless of tracker.
        if usesCorrelationTracker, let seed = currentSeed {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            if let luma = LumaPlane.fromLockedPixelBuffer(pixelBuffer) {
                if correlationTracker == nil {
                    correlationTracker = CorrelationTracker(luma: luma, box: seed, source: sourceSize)
                }
                if let box = correlationTracker?.update(luma: luma, source: sourceSize),
                   Self.acceptsVisionMeasurement(box, previous: seed, sourceSize: sourceSize,
                                                 strict: manualSeedTrustFrames > 0) {
                    subjectPixel = box
                    acceptedMeasurement = box
                    confidence = max(confidence, correlationTracker?.confidence ?? 0)
                    currentSeed = box
                    if manualSeedTrustFrames > 0 { manualSeedTrustFrames -= 1 }
                } else {
                    // Lost / low confidence: drop the filter so it re-seeds from the next detection.
                    correlationTracker = nil
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        // --- Frame-to-frame tracking via Vision (used when the correlation tracker is disabled) ---
        let desiredLevel: VNRequestTrackingLevel = fast ? .fast : .accurate
        if !usesCorrelationTracker, let seed = currentSeed {
            if trackingRequest == nil || trackingLevel != desiredLevel {
                let normalizedSeed = VisionGeometry.normalizedRect(fromPixel: seed, imageSize: sourceSize)
                let req = VNTrackObjectRequest(detectedObjectObservation:
                    VNDetectedObjectObservation(boundingBox: normalizedSeed.cg))
                req.trackingLevel = desiredLevel

                trackingRequest = req
                trackingLevel = desiredLevel
            }
            if let req = trackingRequest {
                do {
                    try sequenceHandler.perform([req], on: pixelBuffer)
                    if let obs = req.results?.first as? VNDetectedObjectObservation {
                        let pixel = VisionGeometry.pixelRect(fromNormalized: TCRect(obs.boundingBox), imageSize: sourceSize)
                        let isManualBootstrap = manualSeedTrustFrames > 0
                        if Self.acceptsVisionMeasurement(pixel, previous: seed, sourceSize: sourceSize, strict: isManualBootstrap) {
                            subjectPixel = pixel
                            acceptedMeasurement = pixel
                            confidence = max(confidence, Double(obs.confidence))
                            if isManualBootstrap {
                                confidence = max(confidence, settings.confidenceThreshold + 0.1)
                                manualSeedTrustFrames -= 1
                            }
                            currentSeed = pixel
                            lastVisionErrorDescription = nil
                        } else {
                            if isManualBootstrap {
                                manualSeedTrustFrames = max(0, manualSeedTrustFrames - 1)
                            }
                            trackingRequest = nil
                            sequenceHandler = VNSequenceRequestHandler()
                        }
                    }
                } catch {
                    visionFailureCount += 1
                    frameVisionError = error.localizedDescription
                    lastVisionErrorDescription = frameVisionError
                    trackingRequest = nil
                }
            }
        }

        // Feed the state machine and smoother.
        stateMachine.observe(confidence: confidence, at: lastSeconds)
        if let s = acceptedMeasurement {
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
            sessionGeneration: context.sessionGeneration,
            visionFailureCount: visionFailureCount,
            lastVisionErrorDescription: frameVisionError ?? lastVisionErrorDescription
        )
    }

    /// Apply a detection result (computed off the per-frame path on the downscaled buffer): refresh
    /// the tracker seed and feed its confidence so lock/recovery transitions still progress. The next
    /// `track(...)` re-seeds the Vision tracker from this box. Ignored while idle (no acquisition
    /// requested), matching the tap/refocus-to-acquire model.
    func applyDetection(pixelRect: TCRect, confidence: Double) -> Bool {
        if let seed = currentSeed,
           !Self.acceptsDetectionCorrection(pixelRect, current: seed) {
            return false
        }
        currentSeed = pixelRect
        trackingRequest = nil
        sequenceHandler = VNSequenceRequestHandler()
        correlationTracker = nil
        manualSeedTrustFrames = 0
        if stateMachine.state != .idle {
            stateMachine.observe(confidence: confidence, at: lastSeconds)
        }
        return true
    }

    private static func processNoise(for smoothingStrength: Double) -> Double {
        // Lower smoothing strength → more responsive (higher process noise). Map [0,1] → [50, 1].
        let s = max(0, min(1, smoothingStrength))
        return 50.0 * (1.0 - s) + 1.0
    }

    private static func acceptsVisionMeasurement(_ rect: TCRect,
                                                 previous: TCRect,
                                                 sourceSize: TCSize,
                                                 strict: Bool) -> Bool {
        guard rect.isFiniteAndPositive else { return false }

        let sourceDiagonal = hypot(sourceSize.width, sourceSize.height)
        let previousDiagonal = hypot(previous.width, previous.height)
        let dx = rect.center.x - previous.center.x
        let dy = rect.center.y - previous.center.y
        let centerDistance = hypot(dx, dy)
        let jumpLimit = max(previousDiagonal * (strict ? 4.0 : 2.25),
                            sourceDiagonal * (strict ? 0.12 : 0.10))
        guard centerDistance <= jumpLimit else { return false }

        let widthRatio = rect.width / max(previous.width, 1)
        let heightRatio = rect.height / max(previous.height, 1)
        let lowerBound = strict ? 0.20 : 0.30
        let upperBound = strict ? 5.00 : 3.25
        guard widthRatio >= lowerBound, widthRatio <= upperBound,
              heightRatio >= lowerBound, heightRatio <= upperBound else {
            return false
        }

        return true
    }

    private static func acceptsDetectionCorrection(_ rect: TCRect, current: TCRect) -> Bool {
        guard rect.isFiniteAndPositive else { return false }

        let currentSearch = current.expanded(byFraction: 2.5)
        if rect.iou(currentSearch) > 0 { return true }

        let dx = rect.center.x - current.center.x
        let dy = rect.center.y - current.center.y
        let centerDistance = hypot(dx, dy)
        let currentDiagonal = hypot(current.width, current.height)
        let rectDiagonal = hypot(rect.width, rect.height)
        return centerDistance <= max(currentDiagonal * 1.75, rectDiagonal * 0.55)
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
