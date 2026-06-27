import SwiftUI
import UIKit
import Observation
import AVFoundation
import QuartzCore
import os
import CoreMedia
import Metal
import TrackerCamCore

/// Orchestrates the pipeline: capture → track → reframe → preview/record (plan §6 data flow).
///
/// Frames flow through an ordered AsyncStream consumed by a single task, which preserves the
/// sequential-tracking contract (plan §6: tracking must not reorder/drop frames). The detector
/// runs on a time cadence; if processing falls behind, the camera's `alwaysDiscardsLateVideoFrames`
/// applies latest-wins backpressure at the source.
@Observable
@MainActor
final class CameraViewModel {
    // Published UI state.
    private(set) var trackingState: TrackingState = .idle
    private(set) var subjectViewRect: CGRect?       // in preview-view coordinates
    private(set) var selectedSeedViewRect: CGRect?  // immediate tap-selected seed in preview coords
    private(set) var debugDetectionViewRect: CGRect?
    private(set) var debugDetectionAccepted = false
    private(set) var guidanceHint: GuidanceEngine.Hint?
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var effectiveConfigSummary: String = ""
    private(set) var permissionDenied = false
    /// Current crop window as a fraction of the source frame, for the mini-map (plan §12).
    private(set) var cropInSourceRect: CGRect?
    private(set) var confidence: Double = 0
    private(set) var trackingScore: Double = 0
    private(set) var fps: Double = 0
    private(set) var visionFailureCount = 0
    private(set) var lastVisionErrorDescription: String?
    private(set) var detectionMs: Double = 0
    private(set) var effectiveDetectionInterval: Double = 0
    /// Seconds remaining in the low-storage countdown, nil when not counting down (plan §14).
    private(set) var storageCountdown: Int?
    private(set) var batteryLow = false  // < 20% (plan §15)
    /// Live skeletons detected this frame (normalized, full-frame). Track/zoom are disabled while we
    /// build the skeleton tracker; this is the primary overlay now.
    private(set) var skeletons: [SkeletonOverlay] = []
    /// Which subjects the skeleton tracker detects (people / cat-dog / both).
    private(set) var subjectMode: SkeletonSubjectMode = .both

    /// The latest reframed texture for the Metal preview (read by MetalPreviewView).
    private(set) var latestPreviewTexture: MTLTexture?
    /// Set by MetalPreviewView to request a single redraw when a new frame is ready (the preview
    /// draws on demand instead of a fixed 60fps, saving GPU/battery when capture is slower).
    var requestPreviewRedraw: (@MainActor () -> Void)?


    let settingsStore: SettingsStore

    private let router: FrameRouter
    private let camera: CameraService
    private let trackingEngine: TrackingEngine
    private let detection: DetectionService
    /// Live skeleton tracker (Vision body pose). Primary subject path while track/zoom are disabled.
    private let skeletonTracker = LiveSkeletonTracker()
    private let recordingStore = RecordingStore()
    private var reframe: ReframePipeline?
    /// Full-frame downscaler that produces the ~720p analysis buffer for Vision (plan §6).
    private var analysisScaler: ReframePipeline?
    private var analysisDims: CGSize = .zero
    private var detectionInFlight = false
    private var detectionTask: Task<Void, Never>?
    private var lastDetectionPixelRect: TCRect?
    private var lastDetectionAccepted = false
    private var trackingScoreEMA: Double = 0
    private var targetTask: Task<Void, Never>?
    private var stopRecordingTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    private var lifecycleGeneration: UInt64 = 0
    private var recording: RecordingService?
#if targetEnvironment(simulator)
    private var simulatorVideoFeeder: SimulatorVideoFeeder?
#endif
    private let thermal = ThermalManager()

    /// Thermal level as text for the debug HUD (plan §12/§15).
    var thermalLevelText: String {
        switch thermal.level {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        }
    }

    private var streamContinuation: AsyncStream<FramePayload>.Continuation?
    private var consumerTask: Task<Void, Never>?
    private var lastDetectAt: Double = -.greatestFiniteMagnitude
    private var lastFrameSeconds: Double?
    private var smoothedFPS: Double = 0
    private var lastUIPublishT: Double = 0
    private var lastHapticState: TrackingState = .idle
    // Live perf debugging: os_signpost (Instruments) + 1 Hz fps log (Console/Xcode).
    private let perfLog = Logger(subsystem: "com.trackercam.app", category: "perf")
    private let signposter = OSSignposter(subsystem: "com.trackercam.app", category: "frame")
    private var lastPerfLogT: Double = 0
    private var trackMsEMA: Double = 0
    private var reframeMsEMA: Double = 0
    private var detectionMsEMA: Double = 0
    // The app needs a faster center pan than the conservative core default so a cantering subject
    // does not outrun the crop between detector/tracker updates.
    private var cropController = CropController(maxCenterSpeed: 4.5)
    private let cropPlanner = CropPlanner()
    private var cropMetadataWriter: CropMetadataStreamWriter?
    private var cropMetadataTempURL: URL?
    private var cropLogActive = false
    private let interruptionPolicy = InterruptionPolicy()
    private var pendingContinuation = false
    private var userRequestedStop = false
    private let storagePolicy = StoragePolicy()
    private let haptics = UINotificationFeedbackGenerator()
    private var lowSpaceSince: Double?
    private var lastStorageCheckT: Double = -.greatestFiniteMagnitude
    private var cachedFreeBytes: Int64 = .max
    private var lastKnownCenter: TCPoint?
    private var lastVelocity: TCPoint = .zero
    private var subjectCenterEMA: TCPoint?   // smoothed subject center for stable crop centering
    private var centeringMeter = CenteringMeter()   // objective tracking-quality metric (motion-based)
    private var lostSince: Double?
    private var recordStartPTS: CMTime = .invalid

    private let processingQueue = DispatchQueue(label: "com.trackercam.processing", qos: .userInitiated)

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.router = FrameRouter(processingQueue: processingQueue)
        self.camera = CameraService(router: router)
        self.trackingEngine = TrackingEngine(settings: settingsStore.settings)
        self.detection = DetectionService()
#if targetEnvironment(simulator)
        self.simulatorVideoFeeder = SimulatorVideoFeeder(router: router)
#endif
    }

    // MARK: - Lifecycle

    func onAppear() async {
        consumerTask?.cancel()
        detectionTask?.cancel()
        targetTask?.cancel()
        streamContinuation?.finish()
        streamContinuation = nil
        router.onFrame = nil

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        guard await CameraService.requestAccess() else { permissionDenied = true; return }
        UIDevice.current.isBatteryMonitoringEnabled = true

        let capabilities = CameraService.discoverCapabilities()
        if !capabilities.supports(settingsStore.settings.frameRate) {
            settingsStore.settings.frameRate = capabilities.bestAvailablePreset
        }

        let outputSize = Self.outputSize(for: settingsStore.settings.aspectRatio)
        reframe = ReframePipeline(outputSize: outputSize)
        recording = RecordingService(outputSize: outputSize)

        // Wire the ordered frame stream. Capture the (Sendable) continuation directly so the
        // off-main-actor capture callback never touches main-actor state (Swift 6).
        // Strict latest-wins (buffer 1): minimize preview latency — never queue stale frames.
        let stream = AsyncStream<FramePayload>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.streamContinuation = continuation
        }
        let continuation = streamContinuation
        router.onFrame = { payload in
            continuation?.yield(payload)
        }

        // Interruption handling (plan §14): finalize-and-continue / stop per policy.
        camera.onInterruption = { [weak self] reason in
            Task { @MainActor in self?.handleInterruption(reason) }
        }
        camera.onInterruptionEnded = { [weak self] in
            Task { @MainActor in self?.handleInterruptionEnded() }
        }
        consumerTask = Task { [weak self] in
            guard let self else { return }
            for await payload in stream {
                guard self.isCurrentGeneration(generation) else { break }
                await self.handle(payload)
            }
        }

#if targetEnvironment(simulator)
        // Deterministic simulator testing: the sim's camera (when present) can't deliver buffers to
        // the data output and is nondeterministic, so ALWAYS drive the pipeline from the fixture clip
        // when one is bundled. This is the reliable way to validate tracking end-to-end in the sim.
        if let fixtureURL = SimulatorVideoFeeder.fixtureURL {
            effectiveConfigSummary = "Fixture video"
            simulatorVideoFeeder?.start(url: fixtureURL)
            return
        }
#endif
        do {
            try await camera.configure(settings: settingsStore.settings)
            if let e = camera.effective {
                effectiveConfigSummary = "\(e.dimensions.width)×\(e.dimensions.height) @\(Int(e.frameRate)) · \(e.isHDR ? "HDR" : "SDR") · \(capabilities.supports4K60 ? "MVP ready" : "limited")"
            }
            camera.startRunning()
        } catch {
            effectiveConfigSummary = "Camera config failed: \(error)"
        }
    }

    func onDisappear() {
        lifecycleGeneration &+= 1
        camera.stopRunning()
#if targetEnvironment(simulator)
        simulatorVideoFeeder?.stop()
#endif
        consumerTask?.cancel()
        detectionTask?.cancel()
        targetTask?.cancel()
        stopRecordingTask?.cancel()
        interruptionTask?.cancel()
        cropMetadataWriter?.close()
        if let tempSidecar = cropMetadataTempURL { try? FileManager.default.removeItem(at: tempSidecar) }
        cropMetadataWriter = nil
        cropMetadataTempURL = nil
        cropLogActive = false
        streamContinuation?.finish()
    }

    // MARK: - User actions

    /// Refocus / tap-to-track (plan §8). `viewPoint` is normalized [0,1] in the preview.
    func refocus(atNormalizedPoint p: CGPoint? = nil) {
        let source = TCRect(x: 0, y: 0,
                            width: Double(camera.effective?.dimensions.width ?? 3840),
                            height: Double(camera.effective?.dimensions.height ?? 2160))
        let seed: TCRect
        if let p {
            // Manual taps should select a precise object, not the strongest contrast in a broad
            // neighborhood. Scale the seed by the visible crop so retaps while zoomed are tighter.
            let sourceShort = min(source.width, source.height)
            let crop = cropInSourceRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            let visibleShort = min(Double(crop.width) * source.width, Double(crop.height) * source.height)
            let side = min(sourceShort * 0.08, max(sourceShort * 0.035, visibleShort * 0.14))
            seed = Self.clampedSeed(
                center: TCPoint(x: p.x * source.width, y: p.y * source.height),
                side: side,
                source: source
            )
            let visibleCrop = Self.cropPixels(fromNormalized: cropInSourceRect, source: source)
            let seedViewRect = Self.rectInCrop(seed, crop: visibleCrop)
            selectedSeedViewRect = seedViewRect
            subjectViewRect = seedViewRect
            trackingState = .searching
            confidence = 0
        } else {
            seed = TCRect(center: source.center,
                          size: TCSize(width: source.width * 0.3, height: source.height * 0.3))
            selectedSeedViewRect = nil
        }
        cropController.reset()   // snap to the new target rather than slewing from the old crop
        subjectCenterEMA = nil
        targetTask?.cancel()
        targetTask = Task { await trackingEngine.seed(pixelRect: seed) }
    }

    /// Release the current target (double-tap "let go") and ease back to a wide centered crop.
    func clearTarget() {
        cropController.reset()
        subjectCenterEMA = nil
        lostSince = nil
        selectedSeedViewRect = nil
        subjectViewRect = nil
        debugDetectionViewRect = nil
        debugDetectionAccepted = false
        lastDetectionPixelRect = nil
        lastDetectionAccepted = false
        trackingState = .idle
        confidence = 0
        targetTask?.cancel()
        targetTask = Task { await trackingEngine.clearTarget() }
    }

    /// Switch which subjects the skeleton tracker looks for.
    func setSubjectMode(_ m: SkeletonSubjectMode) {
        subjectMode = m
        skeletons = []
        Task { await skeletonTracker.setMode(m) }
    }

    func toggleRecording() {
        if isRecording {
            userRequestedStop = true
            pendingContinuation = false
            stopRecordingTask?.cancel()
            stopRecordingTask = Task { await stopRecording() }
        } else {
            userRequestedStop = false
            startRecording()
        }
    }

    // MARK: - Interruptions (plan §14)

    private func handleInterruption(_ reason: CaptureInterruptionReason) {
        let action = interruptionPolicy.action(reason: reason, isRecording: isRecording,
                                               cameraAccessRevoked: permissionDenied)
        switch action {
        case .keepRecording:
            break  // transient (e.g. audio in use) — writer stays active
        case .finalizeAndContinue:
            guard isRecording else { return }
            pendingContinuation = true   // resume into a new segment when the interruption ends
            interruptionTask?.cancel()
            interruptionTask = Task { await stopRecording(continuation: true) }
        case .stopAndFinalize:
            guard isRecording else { return }
            pendingContinuation = false
            stopRecordingTask?.cancel()
            stopRecordingTask = Task { await stopRecording() }
        }
    }

    private func handleInterruptionEnded() {
        guard pendingContinuation, !userRequestedStop else { return }
        pendingContinuation = false
        startRecording()  // continuation segment under the same logical session
    }

    private func startRecording() {
        guard let recording else { return }
        // Pre-record storage check (plan §14).
        if storagePolicy.isCritical(freeBytes: freeBytes(), bitrateBytesPerSecond: currentBitrate()) {
            effectiveConfigSummary = "Not enough storage to record"
            return
        }
        let fps = Int(camera.effective?.frameRate ?? 30)
        do {
            try recording.start(frameRate: fps)
            isRecording = true
            recordStartPTS = .invalid
            lowSpaceSince = nil
            storageCountdown = nil
            camera.setRotationLocked(true)   // lock orientation for the clip (plan §9)
            cropLogActive = settingsStore.settings.exportCropMetadata   // sidecar opt-in (§14)
            cropMetadataWriter?.close()
            cropMetadataWriter = nil
            cropMetadataTempURL = nil
            if cropLogActive {
                let sidecarURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("TrackerCam_\(Int(Date().timeIntervalSince1970))_crop.ndjson")
                cropMetadataTempURL = sidecarURL
                cropMetadataWriter = try? CropMetadataStreamWriter(url: sidecarURL)
            }
        } catch {
            effectiveConfigSummary = "Recorder failed: \(error)"
        }
    }

    /// Live low-space monitor (plan §14): on a critical threshold, run a 5s countdown then stop.
    private func monitorStorage(now t: Double) async {
        if t - lastStorageCheckT >= 1.0 {        // throttle the filesystem query
            lastStorageCheckT = t
            cachedFreeBytes = freeBytes()
        }
        guard storagePolicy.isCritical(freeBytes: cachedFreeBytes, bitrateBytesPerSecond: currentBitrate()) else {
            if lowSpaceSince != nil { lowSpaceSince = nil; storageCountdown = nil }
            return
        }
        if lowSpaceSince == nil {
            lowSpaceSince = t
            haptics.notificationOccurred(.warning)
        }
        let remaining = 5.0 - (t - (lowSpaceSince ?? t))
        storageCountdown = max(0, Int(ceil(remaining)))
        if remaining <= 0 {
            haptics.notificationOccurred(.error)
            await stopRecording()
            storageCountdown = nil
            effectiveConfigSummary = "Stopped — storage full"
        }
    }

    private func freeBytes() -> Int64 {
        (try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? .max
    }

    private func currentBitrate() -> Double {
        let out = Self.outputSize(for: settingsStore.settings.aspectRatio)
        let fps = camera.effective?.frameRate ?? 30
        return StoragePolicy.estimatedBitrateBytesPerSecond(width: Int(out.width), height: Int(out.height), fps: fps)
    }

    private static func recordingHealthSummary(droppedFrames: Int, appendFailures: Int) -> String {
        if droppedFrames == 0 && appendFailures == 0 { return "" }
        var parts: [String] = []
        if droppedFrames > 0 { parts.append("\(droppedFrames) dropped") }
        if appendFailures > 0 { parts.append("\(appendFailures) write failed") }
        return " (" + parts.joined(separator: ", ") + ")"
    }

    private func stopRecording(continuation: Bool = false) async {
        guard let recording else { return }
        camera.setRotationLocked(false)   // allow rotation again after the clip
        let finish = await recording.finish()
        isRecording = false
        elapsed = 0
        guard let url = finish.url else {
            cropMetadataWriter?.close()
            if let tempSidecar = cropMetadataTempURL { try? FileManager.default.removeItem(at: tempSidecar) }
            cropMetadataWriter = nil
            cropMetadataTempURL = nil
            cropLogActive = false
            effectiveConfigSummary = finish.writerErrorDescription.map { "Save failed: \($0)" } ?? "Save failed"
            return
        }
        _ = continuation  // segment finalized; handleInterruptionEnded() will start the next one

        // Move temp file → app library / Photos per settings.saveDestination (plan §14).
        let s = settingsStore.settings
        let res = Self.outputSize(for: s.aspectRatio)
        let result = await recordingStore.finalize(
            tempURL: url, destination: s.saveDestination,
            mode: s.recordingMode == .trackedOnly ? "tracked" : "full",
            resolution: "\(Int(res.width))x\(Int(res.height))")
        let recordingHealth = Self.recordingHealthSummary(droppedFrames: finish.droppedFrames, appendFailures: finish.appendFailures)
        switch (result.appURL != nil, result.savedToPhotos) {
        case (true, true): effectiveConfigSummary = "Saved to app + Photos\(recordingHealth)"
        case (true, false): effectiveConfigSummary = "Saved to app\(recordingHealth)"
        case (false, true): effectiveConfigSummary = "Saved to Photos\(recordingHealth)"
        case (false, false): effectiveConfigSummary = finish.writerErrorDescription.map { "Save failed: \($0)" } ?? "Save failed"
        }

        cropMetadataWriter?.close()
        if cropLogActive, let tempSidecar = cropMetadataTempURL {
            if let appURL = result.appURL {
                let sidecar = appURL.deletingPathExtension().appendingPathExtension("ndjson")
                try? FileManager.default.removeItem(at: sidecar)
                try? FileManager.default.moveItem(at: tempSidecar, to: sidecar)
            } else {
                try? FileManager.default.removeItem(at: tempSidecar)
            }
        }
        cropMetadataWriter = nil
        cropMetadataTempURL = nil
        cropLogActive = false
    }

    // MARK: - Per-frame processing (runs in the consumer task)

    // Skeleton-tracking mode: auto-reframe (ZOOM) and subject TRACKING are intentionally disabled
    // while we build a robust live skeleton tracker first. The preview shows the FULL frame with the
    // detected skeleton(s) overlaid. The previous track+zoom pipeline is preserved verbatim below
    // under `#if false` (`handleLegacyTrackZoom`) so it can be re-enabled.
    private func handle(_ payload: FramePayload) async {
        let ctx = payload.context
        let t = ctx.presentationTime.secondsOrZero
        let sourceSize = TCSize(width: Double(ctx.sourceDimensions.width),
                                height: Double(ctx.sourceDimensions.height))
        let source = TCRect(x: 0, y: 0, width: sourceSize.width, height: sourceSize.height)

        // Downscale to a ~720p analysis buffer for pose (running pose on the full 4K frame is too slow).
        let srcDims = ctx.sourceDimensions
        if analysisScaler == nil || analysisDims != srcDims {
            analysisDims = srcDims
            analysisScaler = ReframePipeline(outputSize: Self.analysisSize(for: srcDims), poolSize: 6)
        }
        var poseBuffer = payload.pixelBuffer
        var poseDims = sourceSize
        if let a = await analysisScaler?.render(payload: payload, cropPixelRect: source, sourceSize: sourceSize) {
            poseBuffer = a.pixelBuffer
            let asz = Self.analysisSize(for: srcDims)
            poseDims = TCSize(width: Double(asz.width), height: Double(asz.height))
        }
        let posePayload = FramePayload(pixelBuffer: poseBuffer, context: ctx)

        // Pose inference (off the main actor, on the owned downscaled buffer).
        let trackSP = signposter.beginInterval("track")
        let trackT0 = CACurrentMediaTime()
        let found = await skeletonTracker.skeletons(in: posePayload, imageSize: poseDims)
        trackMsEMA = trackMsEMA * 0.9 + (CACurrentMediaTime() - trackT0) * 1000 * 0.1
        signposter.endInterval("track", trackSP)

        // Full-frame reframe (NO zoom) → preview + record.
        let crop = source
        let reframeSP = signposter.beginInterval("reframe")
        let reframeT0 = CACurrentMediaTime()
        let renderedOpt = await reframe?.render(payload: payload, cropPixelRect: crop, sourceSize: sourceSize)
        reframeMsEMA = reframeMsEMA * 0.9 + (CACurrentMediaTime() - reframeT0) * 1000 * 0.1
        signposter.endInterval("reframe", reframeSP)
        guard let rendered = renderedOpt else { return }

        // FPS + 1 Hz perf log.
        let dt = lastFrameSeconds.map { max(1.0 / 240, t - $0) } ?? 1.0 / 60
        lastFrameSeconds = t
        smoothedFPS = smoothedFPS == 0 ? 1.0 / dt : smoothedFPS * 0.9 + (1.0 / dt) * 0.1
        if t - lastPerfLogT >= 1.0 {
            lastPerfLogT = t
            perfLog.notice("fps=\(Int(self.smoothedFPS), privacy: .public) trackMs=\(Int(self.trackMsEMA), privacy: .public) reframeMs=\(Int(self.reframeMsEMA), privacy: .public) skeletons=\(found.count, privacy: .public) thermal=\(self.thermalLevelText, privacy: .public) src=\(Int(sourceSize.width))x\(Int(sourceSize.height))")
        }

        // Record the full frame.
        if isRecording, !thermal.mustStopRecording {
            if recordStartPTS == .invalid { recordStartPTS = ctx.presentationTime }
            recording?.append(pixelBuffer: rendered.pixelBuffer, presentationTime: ctx.presentationTime)
            await monitorStorage(now: t)
        } else if isRecording, thermal.mustStopRecording {
            await stopRecording()
        }

        // Publish preview every frame (drives the MTKView without SwiftUI re-render).
        latestPreviewTexture = rendered.texture
        requestPreviewRedraw?()

        // Publish skeletons + HUD state (~20 Hz).
        if t - lastUIPublishT >= 1.0 / 20 {
            lastUIPublishT = t
            skeletons = found
            subjectViewRect = nil
            selectedSeedViewRect = nil
            debugDetectionViewRect = nil
            cropInSourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)   // full frame
            trackingState = found.isEmpty ? .searching : .locked
            confidence = found.first.map {
                Double($0.joints.map(\.confidence).reduce(0, +)) / Double(max(1, $0.joints.count))
            } ?? 0
            fps = smoothedFPS
            let level = UIDevice.current.batteryLevel
            batteryLow = level >= 0 && level < 0.2
            if isRecording, recordStartPTS.isValid {
                elapsed = ctx.presentationTime.seconds - recordStartPTS.seconds
            }
        }
    }

#if false
    // ===== Legacy track + zoom pipeline (DISABLED — kept verbatim for re-enable) =====
    private func handleLegacyTrackZoom(_ payload: FramePayload) async {
        let s = settingsStore.settings
        let ctx = payload.context
        let t = ctx.presentationTime.secondsOrZero

        // Detector cadence (scaled by thermal pressure, plan §15).
        let interval = s.redetectionInterval * thermal.redetectionIntervalMultiplier
        effectiveDetectionInterval = interval
        let redetect = (t - lastDetectAt) >= interval
        if redetect { lastDetectAt = t }

        // Crop / source geometry (plan §10).

        let sourceSize = TCSize(width: Double(ctx.sourceDimensions.width),
                                height: Double(ctx.sourceDimensions.height))
        let source = TCRect(x: 0, y: 0, width: sourceSize.width, height: sourceSize.height)
        let aspect = s.aspectRatio.ratio == 0 ? sourceSize.aspectRatio : s.aspectRatio.ratio

        // Analysis branch (plan §6): run Vision tracking + detection on a ~720p downscale instead of
        // the full 4K frame. Only while a target is being tracked — idle frames need no analysis.
        // Coordinates are normalized, so reduced resolution is transparent to the crop math.
        var visionBuffer = payload.pixelBuffer
        let active = trackingState != .idle
        let autoAcquire = s.acquisitionMode != .tap && detection.canAutoAcquire
        if active || autoAcquire {
            let srcDims = ctx.sourceDimensions
            if analysisScaler == nil || analysisDims != srcDims {
                analysisDims = srcDims
                analysisScaler = ReframePipeline(outputSize: Self.analysisSize(for: srcDims), poolSize: 6)
            }
            if let a = await analysisScaler?.render(payload: payload,
                                                    cropPixelRect: source, sourceSize: sourceSize) {
                visionBuffer = a.pixelBuffer
            }
        }
        let visionPayload = FramePayload(pixelBuffer: visionBuffer, context: ctx)

        // Detector cadence: run decoupled on the owned downscaled buffer so the inference spike never
        // blocks per-frame tracking (latest-wins; at most one in flight, plan §6 backpressure).
        if redetect, (active || autoAcquire), detection.canAutoAcquire, !detectionInFlight {
            detectionInFlight = true
            let detector = detection
            let dims = sourceSize
            let thr = s.confidenceThreshold
            let generation = lifecycleGeneration
            let acquisitionMode = s.acquisitionMode
            let shouldBootstrapDetection = trackingState == .idle || trackingState == .lost || trackingScoreEMA < 25
            detectionTask = Task { [weak self, detector, visionPayload] in
                let detectT0 = CACurrentMediaTime()
                let det = try? detector.detectCompoundTarget(in: visionPayload.pixelBuffer,
                                                             sourceSize: dims, confidenceThreshold: thr)
                let detectMs = (CACurrentMediaTime() - detectT0) * 1000
                guard let self else { return }
                defer { Task { @MainActor in self.clearDetectionInFlight() } }
                guard self.isCurrentGeneration(generation) else { return }
                self.recordDetectionLatency(detectMs)
                if let det {
                    let accepted: Bool
                    if acquisitionMode == .tap {
                        accepted = await self.trackingEngine.applyDetection(pixelRect: det.pixelRect, confidence: det.confidence)
                    } else if shouldBootstrapDetection {
                        await self.trackingEngine.seed(pixelRect: det.pixelRect)
                        accepted = await self.trackingEngine.applyDetection(pixelRect: det.pixelRect, confidence: det.confidence)
                    } else if self.trackingScoreEMA >= 70, det.confidence < thr {
                        accepted = false
                    } else {
                        accepted = await self.trackingEngine.applyDetection(pixelRect: det.pixelRect, confidence: det.confidence)
                    }
                    self.lastDetectionPixelRect = det.pixelRect
                    self.lastDetectionAccepted = accepted
                } else {
                    self.lastDetectionPixelRect = nil
                    self.lastDetectionAccepted = false
                }
            }
        }

        // Tracking (sequential; the actor + ordered stream keep frames in order).
        let trackSP = signposter.beginInterval("track")
        let trackT0 = CACurrentMediaTime()
        let result = await trackingEngine.track(visionPayload: visionPayload, fast: thermal.useFastTracking)
        trackMsEMA = trackMsEMA * 0.9 + (CACurrentMediaTime() - trackT0) * 1000 * 0.1
        signposter.endInterval("track", trackSP)

        // Track last-known motion (used to predict during loss) and the lost-onset time.
        if let center = result.smoothedCenter {
            lastKnownCenter = center
            lastVelocity = result.velocity
        }
        if result.state == .lost {
            if lostSince == nil { lostSince = t }
        } else {
            lostSince = nil
        }
        let secondsSinceLost = lostSince.map { t - $0 } ?? 0
        trackingScoreEMA = Self.trackingScore(
            result: result,
            lastDetection: lastDetectionPixelRect,
            detectionAccepted: lastDetectionAccepted,
            source: source,
            threshold: s.confidenceThreshold,
            previous: trackingScoreEMA
        )

        // Motion centroid of the moving subject (computed once/frame on the source luma). In normal
        // camera use it only scores centering; in the simulator fixture it is also the strongest
        // static-camera signal for the horse/rider.
        CVPixelBufferLockBaseAddress(payload.pixelBuffer, .readOnly)
        if let lp = LumaPlane.fromLockedPixelBuffer(payload.pixelBuffer) {
            centeringMeter.updateCentroid(luma: lp)
        }
        CVPixelBufferUnlockBaseAddress(payload.pixelBuffer, .readOnly)
        // Trust the improved TrackingEngine result (CorrelationTracker + detection fusion + Kalman velocity).
        // The engine now provides reliable smoothedCenter and velocity for crop following.
        var trackCenter: TCPoint?
        var trackSize: TCSize?

        if let subject = result.subjectPixelRect {
            // Responsive EMA on the raw tracker center (Kalman alone lags on direction changes).
            let raw = subject.center
            let prevEMA = subjectCenterEMA
            let smoothed = prevEMA.map {
                TCPoint(x: $0.x + (raw.x - $0.x) * 0.45, y: $0.y + (raw.y - $0.y) * 0.45)
            } ?? raw
            subjectCenterEMA = smoothed
            // Frame-delta lead (~4 frames) plus a short Kalman velocity boost for pipeline latency.
            let frameVel = prevEMA.map {
                TCPoint(x: smoothed.x - $0.x, y: smoothed.y - $0.y)
            } ?? .zero
            let lead = TCPoint(
                x: frameVel.x * 4 + result.velocity.x * 0.12,
                y: frameVel.y * 4 + result.velocity.y * 0.12
            )
            var center = TCPoint(x: smoothed.x + lead.x, y: smoothed.y + lead.y)
            // Nudge toward the latest accepted detection so periodic corrections pull the crop in.
            if lastDetectionAccepted, let det = lastDetectionPixelRect {
                center = TCPoint(x: center.x * 0.70 + det.center.x * 0.30,
                                 y: center.y * 0.70 + det.center.y * 0.30)
            }
            trackCenter = center

            let padded = subject.expanded(byFraction: s.subjectPadding)
            let size = s.dynamicZoomEnabled
                ? CropMath.requiredCropSize(forPaddedSubject: padded,
                                            targetSubjectHeightFraction: s.targetSubjectHeight,
                                            outputAspect: aspect)
                : Self.outputSizeTC(for: s.aspectRatio)
            trackSize = size
        }

        // Simulator fixture fallback to motion metric only if tracker gave nothing.
        #if targetEnvironment(simulator)
        if trackCenter == nil, let motionRect = centeringMeter.motionRectPixels(source: sourceSize) {
            let subjectMotion = Self.simulatorSubjectRect(fromMotionRect: motionRect, source: sourceSize)
            trackCenter = subjectMotion.center
            trackSize = CropMath.requiredCropSize(
                forPaddedSubject: subjectMotion.expanded(byFraction: s.subjectPadding),
                targetSubjectHeightFraction: s.targetSubjectHeight,
                outputAspect: aspect
            )
        }
        #endif

        // Plan the desired crop per tracking state (incl. lost ladder), then rate-limit it (plan §10).
        let planned = cropPlanner.plan(
            state: result.state, secondsSinceLost: secondsSinceLost,
            lastCenter: lastKnownCenter ?? source.center, velocity: lastVelocity,
            trackingDesiredCenter: trackCenter, trackingDesiredSize: trackSize,
            defaultSize: Self.outputSizeTC(for: s.aspectRatio), source: source)

        let dt = lastFrameSeconds.map { max(1.0 / 240, t - $0) } ?? 1.0 / 60
        lastFrameSeconds = t
        smoothedFPS = smoothedFPS == 0 ? 1.0 / dt : smoothedFPS * 0.9 + (1.0 / dt) * 0.1
        cropController.minCropFraction = s.minCropFraction
        let crop = cropController.update(dt: dt, desiredCenter: planned.center,
                                         desiredSize: planned.size, source: source)

        // Objective centering metric, sampled EVERY frame (motion centroid vs the rate-limited crop)
        // so the running average converges. `avg` is the headline number to compare runs.
        if let centerScore = self.centeringMeter.score(crop: crop, source: sourceSize) {
            perfLog.notice("center score=\(String(format: "%.2f", centerScore), privacy: .public) avg=\(String(format: "%.3f", self.centeringMeter.scoreEMA), privacy: .public) n=\(self.centeringMeter.samples, privacy: .public)")
        }

        // GPU reframe → preview + record (runs off the main thread; awaits GPU completion).
        let reframeSP = signposter.beginInterval("reframe")
        let reframeT0 = CACurrentMediaTime()
        let renderedOpt = await reframe?.render(payload: payload, cropPixelRect: crop, sourceSize: sourceSize)
        reframeMsEMA = reframeMsEMA * 0.9 + (CACurrentMediaTime() - reframeT0) * 1000 * 0.1
        signposter.endInterval("reframe", reframeSP)
        guard let rendered = renderedOpt else { return }

        // 1 Hz perf log for live debugging (filter Console/Xcode on subsystem com.trackercam.app).
        if t - lastPerfLogT >= 1.0 {
            lastPerfLogT = t
            perfLog.notice("fps=\(Int(self.smoothedFPS), privacy: .public) trackMs=\(Int(self.trackMsEMA), privacy: .public) reframeMs=\(Int(self.reframeMsEMA), privacy: .public) thermal=\(self.thermalLevelText, privacy: .public) state=\(result.state.rawValue, privacy: .public) src=\(Int(sourceSize.width))x\(Int(sourceSize.height))")
        }


        if isRecording, !thermal.mustStopRecording {
            if recordStartPTS == .invalid { recordStartPTS = ctx.presentationTime }
            recording?.append(pixelBuffer: rendered.pixelBuffer, presentationTime: ctx.presentationTime)
            if cropLogActive {
                let pts = ctx.presentationTime
                cropMetadataWriter?.append(CropFrameRecord(
                    sequence: Int(ctx.sequenceNumber), ptsValue: pts.value, ptsTimescale: pts.timescale,
                    crop: crop, subject: result.subjectPixelRect, confidence: result.confidence,
                    state: result.state.rawValue, predicted: false))
            }
            await monitorStorage(now: t)
        } else if isRecording, thermal.mustStopRecording {
            await stopRecording()   // critical thermal → stop & finalize (plan §15 / D19)
        }

        // Guidance.
        var hint: GuidanceEngine.Hint?
        if s.guidanceEnabled, let center = result.smoothedCenter {
            let engine = GuidanceEngine(deadZoneFraction: s.guidanceDeadZone, lookaheadSeconds: s.guidanceLookahead)
            hint = engine.hint(subjectCenter: center, predictedVelocity: result.velocity, source: source, crop: crop)
        }

        // --- Publish (already on the main actor) ---
        // Preview texture + redraw every frame (kept at capture rate): not read in any SwiftUI body,
        // so it drives the MTKView without triggering SwiftUI re-renders. Draw this frame on demand.
        latestPreviewTexture = rendered.texture
        requestPreviewRedraw?()

        // Haptics fire promptly on every real transition (cheap), independent of the UI throttle.
        if s.guidanceHaptics, lastHapticState != result.state {
            if result.state == .locked { haptics.notificationOccurred(.success) }
            else if result.state == .lost { haptics.notificationOccurred(.warning) }
        }
        lastHapticState = result.state

        // Throttle the SwiftUI overlay/state to ~15 Hz — re-rendering overlays at 60 Hz is wasteful.
        if t - lastUIPublishT >= 1.0 / 15 {
            lastUIPublishT = t
            trackingState = result.state
            // Prefer the engine's subject rect for overlays. Simulator motion is secondary.
            let trackedRect = result.subjectPixelRect.map { Self.rectInCrop($0, crop: crop) }
            if let trackedRect {
                subjectViewRect = trackedRect
            } else if result.state == .searching, let selectedSeedViewRect {
                subjectViewRect = selectedSeedViewRect
            } else if result.state == .idle {
                subjectViewRect = nil
            }
            debugDetectionViewRect = lastDetectionPixelRect.map { Self.rectInCrop($0, crop: crop) }
            debugDetectionAccepted = lastDetectionAccepted
            if result.state != .searching { selectedSeedViewRect = nil }
            guidanceHint = hint
            cropInSourceRect = CGRect(x: crop.minX / source.width, y: crop.minY / source.height,
                                      width: crop.width / source.width, height: crop.height / source.height)
            if let sp = result.subjectPixelRect {
                perfLog.notice("subj scx=\(String(format: "%.2f", sp.center.x / source.width), privacy: .public) scy=\(String(format: "%.2f", sp.center.y / source.height), privacy: .public) cropcx=\(String(format: "%.2f", (crop.minX + crop.width / 2) / source.width), privacy: .public) cropcy=\(String(format: "%.2f", (crop.minY + crop.height / 2) / source.height), privacy: .public) st=\(result.state.rawValue, privacy: .public)")
            }
            confidence = result.confidence
            trackingScore = trackingScoreEMA
            fps = smoothedFPS
            visionFailureCount = result.visionFailureCount
            lastVisionErrorDescription = result.lastVisionErrorDescription
            detectionMs = detectionMsEMA
            let level = UIDevice.current.batteryLevel
            batteryLow = level >= 0 && level < 0.2
            if isRecording, recordStartPTS.isValid {
                elapsed = ctx.presentationTime.seconds - recordStartPTS.seconds
            }
        }
    }
#endif

    // MARK: - Helpers

    /// Clears the decoupled-detection in-flight flag (called back from the detection task).
    private func clearDetectionInFlight() { detectionInFlight = false }

    private func recordDetectionLatency(_ ms: Double) {
        detectionMsEMA = detectionMsEMA == 0 ? ms : detectionMsEMA * 0.9 + ms * 0.1
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        lifecycleGeneration == generation && !Task.isCancelled
    }

    private static func clampedSeed(center: TCPoint, side: Double, source: TCRect) -> TCRect {
        let clampedSide = min(side, source.width, source.height)
        let half = clampedSide / 2
        let x = min(max(center.x - half, source.minX), source.maxX - clampedSide)
        let y = min(max(center.y - half, source.minY), source.maxY - clampedSide)
        return TCRect(x: x, y: y, width: clampedSide, height: clampedSide)
    }

    private static func cropPixels(fromNormalized crop: CGRect?, source: TCRect) -> TCRect {
        guard let crop else { return source }
        return TCRect(x: crop.minX * source.width,
                      y: crop.minY * source.height,
                      width: crop.width * source.width,
                      height: crop.height * source.height)
    }

    /// Simulator-only static fixture targeting: frame difference can include jump rails and arena
    /// shimmer, so clamp its raw extent to a plausible horse+rider box before using it for zoom/UI.
    private static func simulatorSubjectRect(fromMotionRect rect: TCRect, source: TCSize) -> TCRect {
        let minW = source.width * 0.08
        let maxW = source.width * 0.24
        let minH = source.height * 0.12
        let maxH = source.height * 0.24
        let w = min(max(rect.width, minW), maxW)
        let h = min(max(rect.height, minH), maxH)
        let x = min(max(rect.center.x - w / 2, 0), max(0, source.width - w))
        let y = min(max(rect.center.y - h / 2, 0), max(0, source.height - h))
        return TCRect(x: x, y: y, width: w, height: h)
    }

    /// 0...100 target-quality estimate for debug and future self-correction. A good score means
    /// Vision is confident, the box size is plausible, and detector corrections agree with tracking.
    private static func trackingScore(result: TrackingEngine.TrackingResult,
                                      lastDetection: TCRect?,
                                      detectionAccepted: Bool,
                                      source: TCRect,
                                      threshold: Double,
                                      previous: Double) -> Double {
        guard let subject = result.subjectPixelRect, subject.isFiniteAndPositive else {
            return previous * 0.80
        }

        let stateScore: Double
        switch result.state {
        case .locked: stateScore = 1.0
        case .tracking: stateScore = 0.85
        case .searching: stateScore = 0.35
        case .lost: stateScore = 0.05
        case .idle: stateScore = 0.0
        }

        let confidenceScore = min(1.0, result.confidence / max(0.05, threshold))
        let areaFraction = subject.area / max(1, source.area)
        let sizeScore: Double
        if areaFraction < 0.002 || areaFraction > 0.30 {
            sizeScore = 0.05
        } else if areaFraction < 0.006 || areaFraction > 0.18 {
            sizeScore = 0.45
        } else {
            sizeScore = 1.0
        }

        let agreementScore: Double
        if let lastDetection {
            let overlap = subject.iou(lastDetection)
            let dx = subject.center.x - lastDetection.center.x
            let dy = subject.center.y - lastDetection.center.y
            let distance = hypot(dx, dy)
            let distanceScore = 1.0 - min(1.0, distance / max(hypot(subject.width, subject.height), 1))
            agreementScore = detectionAccepted ? max(overlap, distanceScore) : min(0.25, max(overlap, distanceScore) * 0.5)
        } else {
            agreementScore = result.state == .locked || result.state == .tracking ? 0.55 : 0.20
        }

        let raw = 100.0 * (0.35 * stateScore + 0.25 * confidenceScore + 0.20 * sizeScore + 0.20 * agreementScore)
        let alpha = raw >= previous ? 0.28 : 0.45
        return min(100, max(0, previous + (raw - previous) * alpha))
    }

    /// Analysis-buffer size: source aspect preserved, scaled so the long side is ~1280px. Keeping the
    /// source aspect avoids anisotropic distortion of the tracked content.
    private static func analysisSize(for source: CGSize) -> CGSize {
        let longSide: CGFloat = 1280
        guard source.width > 0, source.height > 0 else { return CGSize(width: longSide, height: 720) }
        if source.width >= source.height {
            return CGSize(width: longSide, height: max(2, (longSide * source.height / source.width).rounded()))
        }
        return CGSize(width: max(2, (longSide * source.width / source.height).rounded()), height: longSide)
    }

    /// Map a source-pixel rect into the crop's normalized [0,1] space (preview coordinates).
    private static func rectInCrop(_ rect: TCRect, crop: TCRect) -> CGRect {
        guard crop.width > 0, crop.height > 0 else { return .zero }
        return CGRect(x: (rect.minX - crop.minX) / crop.width,
                      y: (rect.minY - crop.minY) / crop.height,
                      width: rect.width / crop.width,
                      height: rect.height / crop.height)
    }

    private static func outputSize(for aspect: AspectRatioMode) -> CGSize {
        switch aspect {
        case .landscape16x9: return CGSize(width: 1920, height: 1080)
        case .portrait9x16: return CGSize(width: 1080, height: 1920)
        case .square1x1: return CGSize(width: 1080, height: 1080)
        case .fullFrame: return CGSize(width: 3840, height: 2160)
        }
    }

    private static func outputSizeTC(for aspect: AspectRatioMode) -> TCSize {
        let s = outputSize(for: aspect); return TCSize(width: s.width, height: s.height)
    }
}
