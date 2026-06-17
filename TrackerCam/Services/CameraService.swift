import AVFoundation
import CoreMedia
import TrackerCamCore

/// Owns the `AVCaptureSession` lifecycle: device/format selection, SDR color space, stabilization,
/// frame rate, and orientation (plan §9 Camera Capture Pipeline). Emits `FramePayload`s via the router.
///
/// IMPORTANT (plan §5 / §17 Phase 0): the exact format + pixel format + stabilization + color space
/// combination must be validated on physical hardware before a capture mode is exposed in the UI.
/// This service picks a best-effort 4K SDR configuration and reports the *effective* result.
///
/// `@unchecked Sendable` contract: AVFoundation session/device/connection state is mutable and
/// non-Sendable, so every access is serialized through `sessionQueue` or `captureQueue`; the main
/// actor only calls async wrappers or posts fire-and-forget queue work.
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    enum CameraError: Error {
        case noCamera
        case noSupported4KFormat
        case configurationFailed
    }

    /// Result of applying a configuration — request vs effective (plan §5 capability discovery).
    struct EffectiveConfiguration {
        var dimensions: CMVideoDimensions
        var frameRate: Double
        var stabilizationMode: AVCaptureVideoStabilizationMode
        var colorSpace: AVCaptureColorSpace
        var isHDR: Bool
    }

    /// Runtime capability snapshot for Settings and diagnostics. This is device/format driven rather
    /// than model-name driven, so it works for iPhone 17 Pro, 16 Pro, and future Pro hardware.
    struct CapabilityReport: Sendable {
        var cameraName: String
        var max4KFrameRate: Double
        var supports4K30: Bool
        var supports4K60: Bool
        var supports4K100: Bool
        var supports4K120: Bool

        var bestAvailablePreset: FrameRatePreset {
            if supports4K120 { return .experimental120 }
            if supports4K100 { return .experimental100 }
            if supports4K60 { return .preferred60 }
            return .fps30
        }

        var summary: String {
            guard max4KFrameRate > 0 else { return "No back 4K camera detected" }
            let fps = Int(max4KFrameRate.rounded(.down))
            let readiness = supports4K60 ? "MVP ready" : "below MVP target"
            return "\(cameraName): 4K up to \(fps) fps · \(readiness)"
        }

        func supports(_ preset: FrameRatePreset) -> Bool {
            switch preset {
            case .fps30: return supports4K30
            case .preferred60: return supports4K60
            case .experimental100: return supports4K100
            case .experimental120: return supports4K120
            }
        }
    }

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.trackercam.session")
    private let captureQueue = DispatchQueue(label: "com.trackercam.capture", qos: .userInitiated)

    private let router: FrameRouter
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var connection: AVCaptureConnection?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    private var sequence: UInt64 = 0
    private(set) var sessionGeneration: UInt64 = 0
    private(set) var effective: EffectiveConfiguration?

    /// Capture-interruption callbacks (plan §14). Invoked on the main queue.
    var onInterruption: (@Sendable (CaptureInterruptionReason) -> Void)?
    var onInterruptionEnded: (@Sendable () -> Void)?
    private var notificationObservers: [NSObjectProtocol] = []

    init(router: FrameRouter) {
        self.router = router
        super.init()
        registerInterruptionObservers()
    }

    private func registerInterruptionObservers() {
        let nc = NotificationCenter.default
        notificationObservers.append(nc.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main
        ) { [weak self] note in
            self?.onInterruption?(Self.mapReason(note))
        })
        notificationObservers.append(nc.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main
        ) { [weak self] _ in
            self?.onInterruptionEnded?()
        })
        notificationObservers.append(nc.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] note in
            // A media-services reset surfaces here; treat as needing a fresh segment + session.
            if let err = note.userInfo?[AVCaptureSessionErrorKey] as? AVError,
               err.code == .mediaServicesWereReset {
                self?.onInterruption?(.mediaServicesReset)
            }
        })
    }

    private static func mapReason(_ note: Notification) -> CaptureInterruptionReason {
        guard let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
              let reason = AVCaptureSession.InterruptionReason(rawValue: raw) else { return .videoInUse }
        switch reason {
        case .videoDeviceNotAvailableInBackground: return .backgrounded
        case .audioDeviceInUseByAnotherClient: return .audioInUse
        case .videoDeviceInUseByAnotherClient: return .videoInUse
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return .videoInUse
        case .videoDeviceNotAvailableDueToSystemPressure: return .systemPressure
        case .sensitiveContentMitigationActivated: return .videoInUse
        @unknown default: return .videoInUse
        }
    }

    // MARK: - Authorization

    static func discoverCapabilities() -> CapabilityReport {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return CapabilityReport(cameraName: "Back camera", max4KFrameRate: 0,
                                    supports4K30: false, supports4K60: false,
                                    supports4K100: false, supports4K120: false)
        }
        let max4K = device.formats
            .filter(is4KYUVFormat)
            .flatMap(\.videoSupportedFrameRateRanges)
            .map(\.maxFrameRate)
            .max() ?? 0
        return CapabilityReport(
            cameraName: device.localizedName,
            max4KFrameRate: max4K,
            supports4K30: max4K + 0.01 >= 30,
            supports4K60: max4K + 0.01 >= 60,
            supports4K100: max4K + 0.01 >= 100,
            supports4K120: max4K + 0.01 >= 120)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Configuration

    func configure(settings: TrackerSettings) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureLocked(settings: settings)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func configureLocked(settings: TrackerSettings) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .inputPriority

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCamera
        }
        self.device = device

        // Pick a 4K, SDR-capable format at the requested frame rate (plan §9).
        guard let format = Self.best4KFormat(for: device, frameRate: settings.frameRate) else {
            throw CameraError.noSupported4KFormat
        }

        try device.lockForConfiguration()
        device.activeFormat = format
        let fps = Self.targetFPS(settings.frameRate, format: format)
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration

        // Enforce SDR explicitly — 4K Fusion Main formats may default to HDR (plan §9 Color Space).
        if device.activeFormat.supportedColorSpaces.contains(.sRGB) {
            device.activeColorSpace = .sRGB
        }
        device.automaticallyAdjustsVideoHDREnabled = false
        if device.activeFormat.isVideoHDRSupported {
            device.isVideoHDREnabled = false
        }
        device.unlockForConfiguration()

        // I/O.
        let input = try AVCaptureDeviceInput(device: device)
        session.inputs.forEach(session.removeInput)
        guard session.canAddInput(input) else { throw CameraError.configurationFailed }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        if session.outputs.contains(videoOutput) == false {
            guard session.canAddOutput(videoOutput) else { throw CameraError.configurationFailed }
            session.addOutput(videoOutput)
        }

        guard let conn = videoOutput.connection(with: .video) else { throw CameraError.configurationFailed }
        self.connection = conn

        // Stabilization: prefer Cinematic Extended, fall back (plan §9).
        conn.preferredVideoStabilizationMode = Self.bestStabilization(for: conn, requested: .cinematicExtended)

        // Orientation: rotate delivered buffers to match how the phone is physically held (plan §9).
        // Without this the back camera's native-landscape buffer appears rotated.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        self.rotationCoordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        // Track device rotation live so the viewfinder re-levels as the phone turns (full UI
        // autorotation): the coordinator's horizon-level angle is KVO-observable and updates as the
        // device orientation changes. Apply on the session queue to serialize with the connection
        // and respect recording's rotation lock.
        rotationObservation?.invalidate()
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture,
                                                  options: [.new]) { [weak self] coordinator, _ in
            self?.applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        }

        sessionGeneration &+= 1

        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        effective = EffectiveConfiguration(
            dimensions: dims,
            frameRate: Double(fps),
            stabilizationMode: conn.activeVideoStabilizationMode,
            colorSpace: device.activeColorSpace,
            isHDR: device.isVideoHDREnabled
        )
    }

    private var rotationLocked = false

    /// Lock the capture rotation while recording so a mid-clip device rotation can't flip the
    /// output (plan §9: lock output orientation when recording starts).
    func setRotationLocked(_ locked: Bool) {
        sessionQueue.async { self.rotationLocked = locked }
    }

    private func applyRotation(_ angle: CGFloat) {
        sessionQueue.async {
            guard !self.rotationLocked,
                  let conn = self.connection, conn.isVideoRotationAngleSupported(angle) else { return }
            conn.videoRotationAngle = angle
        }
    }

    func startRunning() {
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stopRunning() {
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    // MARK: - Format selection helpers

    private static func targetFPS(_ preset: FrameRatePreset, format: AVCaptureDevice.Format) -> Int {
        switch preset {
        case .fps30: return 30
        case .preferred60: return format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 } ? 60 : 30
        case .experimental100: return 100
        case .experimental120: return 120
        }
    }

    private static func best4KFormat(for device: AVCaptureDevice, frameRate: FrameRatePreset) -> AVCaptureDevice.Format? {
        let wanted = targetFPSForSelection(frameRate)
        let formats = device.formats.filter { f in
            is4KYUVFormat(f) && f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate + 0.01 >= Double(wanted) }
        }
        // Prefer formats that advertise SDR (sRGB) support and are not binned.
        return formats.sorted { a, b in
            let aSDR = a.supportedColorSpaces.contains(.sRGB)
            let bSDR = b.supportedColorSpaces.contains(.sRGB)
            if aSDR != bSDR { return aSDR && !bSDR }
            return !a.isVideoBinned && b.isVideoBinned
        }.first
    }

    private static func is4KYUVFormat(_ format: AVCaptureDevice.Format) -> Bool {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let is4K = d.width >= 3840 && d.height >= 2160
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let isYUV = subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        return is4K && isYUV
    }

    private static func targetFPSForSelection(_ preset: FrameRatePreset) -> Int {
        switch preset {
        case .fps30: return 30
        case .preferred60: return 60
        case .experimental100: return 100
        case .experimental120: return 120
        }
    }

    private static func bestStabilization(for connection: AVCaptureConnection,
                                          requested: AVCaptureVideoStabilizationMode) -> AVCaptureVideoStabilizationMode {
        let order: [AVCaptureVideoStabilizationMode] = [.cinematicExtended, .cinematic, .standard, .off]
        let start = order.firstIndex(of: requested) ?? 0
        for mode in order[start...] where connection.isVideoStabilizationSupported {
            // isVideoStabilizationSupported is a coarse gate; the effective mode is read back after set.
            return mode
        }
        return .off
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        sequence &+= 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // Use the delivered buffer's actual dimensions (rotation swaps width/height).
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let ctx = FrameContext(
            sequenceNumber: sequence,
            presentationTime: pts,
            sourceDimensions: CGSize(width: w, height: h),
            rotationAngle: connection.videoRotationAngle,
            isMirrored: connection.isVideoMirrored,
            sessionGeneration: sessionGeneration,
            effectiveStabilizationMode: connection.activeVideoStabilizationMode
        )
        // Hand off ownership to the router (single-owner contract, plan §6).
        router.route(FramePayload(pixelBuffer: pixelBuffer, context: ctx))
    }
}
