import SwiftUI
import Observation
import AVFoundation
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
    private(set) var guidanceHint: GuidanceEngine.Hint?
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var effectiveConfigSummary: String = ""
    private(set) var permissionDenied = false
    /// Current crop window as a fraction of the source frame, for the mini-map (plan §12).
    private(set) var cropInSourceRect: CGRect?
    private(set) var confidence: Double = 0
    private(set) var fps: Double = 0

    /// The latest reframed texture for the Metal preview (read by MetalPreviewView).
    private(set) var latestPreviewTexture: MTLTexture?

    let settingsStore: SettingsStore

    private let router: FrameRouter
    private let camera: CameraService
    private let trackingEngine: TrackingEngine
    private let detection: DetectionService
    private let recordingStore = RecordingStore()
    private var reframe: ReframePipeline?
    private var recording: RecordingService?
    private let thermal = ThermalManager()

    private var streamContinuation: AsyncStream<FramePayload>.Continuation?
    private var consumerTask: Task<Void, Never>?
    private var lastDetectAt: Double = -.greatestFiniteMagnitude
    private var lastFrameSeconds: Double?
    private var smoothedFPS: Double = 0
    private var cropController = CropController()
    private let cropPlanner = CropPlanner()
    private var lastKnownCenter: TCPoint?
    private var lastVelocity: TCPoint = .zero
    private var lostSince: Double?
    private var recordStartPTS: CMTime = .invalid

    private let processingQueue = DispatchQueue(label: "com.trackercam.processing", qos: .userInitiated)

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.router = FrameRouter(processingQueue: processingQueue)
        self.camera = CameraService(router: router)
        self.trackingEngine = TrackingEngine(settings: settingsStore.settings)
        self.detection = DetectionService()
    }

    // MARK: - Lifecycle

    func onAppear() async {
        guard await CameraService.requestAccess() else { permissionDenied = true; return }

        let outputSize = Self.outputSize(for: settingsStore.settings.aspectRatio)
        reframe = ReframePipeline(outputSize: outputSize)
        recording = RecordingService(outputSize: outputSize)

        // Wire the ordered frame stream. Capture the (Sendable) continuation directly so the
        // off-main-actor capture callback never touches main-actor state (Swift 6).
        let stream = AsyncStream<FramePayload> { continuation in
            self.streamContinuation = continuation
        }
        let continuation = streamContinuation
        router.onFrame = { payload in
            continuation?.yield(payload)
        }
        consumerTask = Task { [weak self] in
            guard let self else { return }
            for await payload in stream {
                await self.handle(payload)
            }
        }

        do {
            try await camera.configure(settings: settingsStore.settings)
            if let e = camera.effective {
                effectiveConfigSummary = "\(e.dimensions.width)×\(e.dimensions.height) @\(Int(e.frameRate)) · \(e.isHDR ? "HDR" : "SDR")"
            }
            camera.startRunning()
        } catch {
            effectiveConfigSummary = "Camera config failed: \(error)"
        }
    }

    func onDisappear() {
        camera.stopRunning()
        consumerTask?.cancel()
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
            // Clamped seed = 20% of shorter dimension centered at the tap (plan §8 Tap-to-track).
            let side = min(source.width, source.height) * 0.2
            seed = TCRect(center: TCPoint(x: p.x * source.width, y: p.y * source.height),
                          size: TCSize(width: side, height: side))
        } else {
            seed = TCRect(center: source.center,
                          size: TCSize(width: source.width * 0.3, height: source.height * 0.3))
        }
        cropController.reset()   // snap to the new target rather than slewing from the old crop
        Task { await trackingEngine.seed(pixelRect: seed) }
    }

    func toggleRecording() {
        if isRecording { Task { await stopRecording() } }
        else { startRecording() }
    }

    private func startRecording() {
        guard let recording else { return }
        let fps = Int(camera.effective?.frameRate ?? 30)
        do {
            try recording.start(frameRate: fps)
            isRecording = true
            recordStartPTS = .invalid
        } catch {
            effectiveConfigSummary = "Recorder failed: \(error)"
        }
    }

    private func stopRecording() async {
        guard let recording else { return }
        let (url, dropped) = await recording.finish()
        isRecording = false
        elapsed = 0
        guard let url else { effectiveConfigSummary = "Save failed"; return }

        // Move temp file → app library / Photos per settings.saveDestination (plan §14).
        let s = settingsStore.settings
        let res = Self.outputSize(for: s.aspectRatio)
        let result = await recordingStore.finalize(
            tempURL: url, destination: s.saveDestination,
            mode: s.recordingMode == .trackedOnly ? "tracked" : "full",
            resolution: "\(Int(res.width))x\(Int(res.height))")
        switch (result.appURL != nil, result.savedToPhotos) {
        case (true, true): effectiveConfigSummary = "Saved to app + Photos (\(dropped) dropped)"
        case (true, false): effectiveConfigSummary = "Saved to app (\(dropped) dropped)"
        case (false, true): effectiveConfigSummary = "Saved to Photos (\(dropped) dropped)"
        case (false, false): effectiveConfigSummary = "Save failed"
        }
    }

    // MARK: - Per-frame processing (runs in the consumer task)

    private func handle(_ payload: FramePayload) async {
        let s = settingsStore.settings
        let ctx = payload.context
        let t = ctx.presentationTime.secondsOrZero

        // Detector cadence (scaled by thermal pressure, plan §15).
        let interval = s.redetectionInterval * thermal.redetectionIntervalMultiplier
        let redetect = (t - lastDetectAt) >= interval
        if redetect { lastDetectAt = t }

        // Tracking (sequential; the actor + ordered stream keep frames in order).
        let result = await trackingEngine.process(
            payload: payload,
            detector: detection.isModelLoaded ? detection : nil, redetect: redetect)

        // Crop decision (plan §10).
        let sourceSize = TCSize(width: Double(ctx.sourceDimensions.width),
                                height: Double(ctx.sourceDimensions.height))
        let source = TCRect(x: 0, y: 0, width: sourceSize.width, height: sourceSize.height)
        let aspect = s.aspectRatio.ratio == 0 ? sourceSize.aspectRatio : s.aspectRatio.ratio

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

        // Active composed target when we actually have a subject (tracking/locked).
        var trackCenter: TCPoint?
        var trackSize: TCSize?
        if let subject = result.subjectPixelRect, let center = result.smoothedCenter {
            let padded = subject.expanded(byFraction: s.subjectPadding)
            let size = s.dynamicZoomEnabled
                ? CropMath.requiredCropSize(forPaddedSubject: padded,
                                            targetSubjectHeightFraction: s.targetSubjectHeight,
                                            outputAspect: aspect)
                : Self.outputSizeTC(for: s.aspectRatio)
            trackSize = size
            trackCenter = CropMath.compositionCenter(
                subjectCenter: center, velocity: result.velocity, cropSize: size,
                leadFraction: s.compositionLeadFraction, verticalOffsetFraction: s.verticalCompositionOffset)
        }

        // Plan the desired crop per tracking state (incl. lost ladder), then rate-limit it (plan §10).
        let planned = cropPlanner.plan(
            state: result.state, secondsSinceLost: secondsSinceLost,
            lastCenter: lastKnownCenter ?? source.center, velocity: lastVelocity,
            trackingDesiredCenter: trackCenter, trackingDesiredSize: trackSize,
            defaultSize: Self.outputSizeTC(for: s.aspectRatio), source: source)

        let dt = lastFrameSeconds.map { max(1.0 / 240, t - $0) } ?? 1.0 / 60
        lastFrameSeconds = t
        smoothedFPS = smoothedFPS == 0 ? 1.0 / dt : smoothedFPS * 0.9 + (1.0 / dt) * 0.1
        let crop = cropController.update(dt: dt, desiredCenter: planned.center,
                                         desiredSize: planned.size, source: source)

        // GPU reframe → preview + record.
        guard let rendered = reframe?.render(pixelBuffer: payload.pixelBuffer,
                                             cropPixelRect: crop, sourceSize: sourceSize) else { return }

        if isRecording, !thermal.mustStopRecording {
            if recordStartPTS == .invalid { recordStartPTS = ctx.presentationTime }
            recording?.append(pixelBuffer: rendered.pixelBuffer, presentationTime: ctx.presentationTime)
        } else if isRecording, thermal.mustStopRecording {
            await stopRecording()   // critical thermal → stop & finalize (plan §15 / D19)
        }

        // Guidance.
        var hint: GuidanceEngine.Hint?
        if s.guidanceEnabled, let center = result.smoothedCenter {
            let engine = GuidanceEngine(deadZoneFraction: s.guidanceDeadZone, lookaheadSeconds: s.guidanceLookahead)
            hint = engine.hint(subjectCenter: center, predictedVelocity: result.velocity, source: source, crop: crop)
        }

        // Publish to UI on the main actor.
        let subjectInCrop = result.subjectPixelRect.map { Self.rectInCrop($0, crop: crop) }
        let cropFraction = CGRect(x: crop.minX / source.width, y: crop.minY / source.height,
                                  width: crop.width / source.width, height: crop.height / source.height)
        await MainActor.run {
            self.trackingState = result.state
            self.latestPreviewTexture = rendered.texture
            self.subjectViewRect = subjectInCrop
            self.guidanceHint = hint
            self.cropInSourceRect = cropFraction
            if self.isRecording, self.recordStartPTS.isValid {
                self.elapsed = ctx.presentationTime.seconds - self.recordStartPTS.seconds
            }
        }
    }

    // MARK: - Helpers

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
