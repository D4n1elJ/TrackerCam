# Capture Patterns

## AVCaptureSession Setup

All session work must happen on a dedicated serial queue. `startRunning()` is a blocking call that freezes the UI when called on the main thread.

### Architecture

```
AVCaptureSession
    ├── Inputs
    │   ├── AVCaptureDeviceInput (camera)
    │   └── AVCaptureDeviceInput (microphone, for video)
    ├── Outputs
    │   ├── AVCapturePhotoOutput (still photos)
    │   ├── AVCaptureMovieFileOutput (video files)
    │   └── AVCaptureVideoDataOutput (raw frames)
    └── Connections (automatic between compatible input/output)
```

### Session Presets

| Preset | Use Case |
|---|---|
| `.photo` | Photo capture (optimal resolution) |
| `.high` | Video recording (highest device quality) |
| `.hd1920x1080` | Full HD video |
| `.hd4K3840x2160` | 4K video |
| `.inputPriority` | Custom device format configuration |

### Basic Session Setup

```swift
import AVFoundation

class CameraManager: NSObject {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")

    func setupSession() {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(
                      .builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            guard session.canAddOutput(photoOutput) else { return }
            session.addOutput(photoOutput)

            photoOutput.maxPhotoQualityPrioritization = .quality
        }
    }

    func startSession() {
        sessionQueue.async { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func stopSession() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}
```

### SwiftUI Camera Preview

```swift
import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
```

### Camera Permission

```swift
func requestCameraAccess() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
        return true
    case .notDetermined:
        return await AVCaptureDevice.requestAccess(for: .video)
    case .denied, .restricted:
        return false
    @unknown default:
        return false
    }
}
```

Required Info.plist keys:

```xml
<key>NSCameraUsageDescription</key>
<string>Take photos and videos</string>

<!-- Only if recording video with audio -->
<key>NSMicrophoneUsageDescription</key>
<string>Record audio with video</string>
```

## RotationCoordinator (iOS 17+)

Replaces deprecated `videoOrientation`. Tracks device gravity automatically and provides rotation angles for both preview and capture. Handles edge cases (face-up, face-down) that manual orientation tracking misses.

### Setup

```swift
private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
private var rotationObservation: NSKeyValueObservation?

func setupRotationCoordinator(
    device: AVCaptureDevice,
    previewLayer: AVCaptureVideoPreviewLayer
) {
    rotationCoordinator = AVCaptureDevice.RotationCoordinator(
        device: device,
        previewLayer: previewLayer
    )

    // Set initial preview rotation
    previewLayer.connection?.videoRotationAngle =
        rotationCoordinator!.videoRotationAngleForHorizonLevelPreview

    // Observe changes
    rotationObservation = rotationCoordinator?.observe(
        \.videoRotationAngleForHorizonLevelPreview,
        options: [.new]
    ) { [weak previewLayer] coordinator, _ in
        DispatchQueue.main.async {
            previewLayer?.connection?.videoRotationAngle =
                coordinator.videoRotationAngleForHorizonLevelPreview
        }
    }
}
```

### Two Properties, Two Purposes

| Property | Use |
|---|---|
| `videoRotationAngleForHorizonLevelPreview` | Apply to preview layer connection |
| `videoRotationAngleForHorizonLevelCapture` | Apply to output connection when capturing |

### Applying to Capture

```swift
func capturePhoto() {
    let settings = AVCapturePhotoSettings()

    if let connection = photoOutput.connection(with: .video),
       let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture {
        connection.videoRotationAngle = angle
    }

    photoOutput.capturePhoto(with: settings, delegate: self)
}
```

When switching cameras, create a new RotationCoordinator for the new device.

## Responsive Capture Pipeline (iOS 17+)

Four complementary APIs that work together for maximum capture responsiveness.

### Zero Shutter Lag

Uses a ring buffer of recent frames. When the user taps the shutter, the system uses the frame from that exact moment instead of waiting for a new exposure.

```swift
// Enabled by default for iOS 17+ apps
// Check support:
if photoOutput.isZeroShutterLagSupported {
    // Opt out only if causing issues:
    // photoOutput.isZeroShutterLagEnabled = false
}
```

Requirements: iPhone XS (A12) and newer. Does not apply to flash captures, manual exposure, bracketed captures, or constituent photo delivery.

### Responsive Capture (Overlapping Captures)

Allows a new capture to begin while the previous one is still processing. Increases peak memory usage.

```swift
if photoOutput.isZeroShutterLagSupported {
    photoOutput.isZeroShutterLagEnabled = true

    if photoOutput.isResponsiveCaptureSupported {
        photoOutput.isResponsiveCaptureEnabled = true
    }
}
```

### Fast Capture Prioritization

Automatically reduces quality when taking photos in rapid succession to maintain consistent shot-to-shot time. Off by default because it reduces quality.

```swift
if photoOutput.isFastCapturePrioritizationSupported {
    photoOutput.isFastCapturePrioritizationEnabled = true
}
```

### Readiness Coordinator (Button State)

Provides synchronous shutter button state updates without async lag. Prevents users from spamming the shutter button during processing.

```swift
private var readinessCoordinator: AVCapturePhotoOutputReadinessCoordinator!

func setupReadinessCoordinator() {
    readinessCoordinator = AVCapturePhotoOutputReadinessCoordinator(
        photoOutput: photoOutput
    )
    readinessCoordinator.delegate = self
}

func capturePhoto() {
    let settings = AVCapturePhotoSettings()
    settings.photoQualityPrioritization = .balanced

    // Track BEFORE calling capturePhoto
    readinessCoordinator.startTrackingCaptureRequest(using: settings)
    photoOutput.capturePhoto(with: settings, delegate: self)
}
```

Delegate states:

| CaptureReadiness | Meaning | UI Response |
|---|---|---|
| `.ready` | Can capture now | Enable shutter button |
| `.notReadyMomentarily` | Brief delay | Disable to prevent double-tap |
| `.notReadyWaitingForCapture` | Flash firing or sensor reading | Dim button |
| `.notReadyWaitingForProcessing` | Processing previous photo | Show spinner |
| `.sessionNotRunning` | Session stopped | Disable button |

```swift
extension CameraManager: AVCapturePhotoOutputReadinessCoordinatorDelegate {
    func readinessCoordinator(
        _ coordinator: AVCapturePhotoOutputReadinessCoordinator,
        captureReadinessDidChange captureReadiness: AVCapturePhotoOutput.CaptureReadiness
    ) {
        DispatchQueue.main.async {
            switch captureReadiness {
            case .ready:
                self.shutterButton.isEnabled = true
                self.shutterButton.alpha = 1.0
            case .notReadyMomentarily:
                self.shutterButton.isEnabled = false
            case .notReadyWaitingForCapture:
                self.shutterButton.alpha = 0.5
            case .notReadyWaitingForProcessing:
                self.showProcessingIndicator()
            case .sessionNotRunning:
                self.shutterButton.isEnabled = false
            @unknown default:
                break
            }
        }
    }
}
```

### Quality Prioritization

Controls speed vs quality tradeoff per capture, independent of the responsive capture pipeline.

| Value | When to Use |
|---|---|
| `.speed` | Social sharing, rapid capture |
| `.balanced` | General photography |
| `.quality` | Documents, professional use |

```swift
var settings = AVCapturePhotoSettings()
settings.photoQualityPrioritization = .speed
```

## Deferred Photo Processing (iOS 17+)

Capture returns immediately with a proxy image. Full Deep Fusion processing happens in the background, triggered by PhotoKit when the image is viewed or when the device is idle.

```swift
// Enable during session setup
if photoOutput.isAutoDeferredPhotoDeliverySupported {
    photoOutput.isAutoDeferredPhotoDeliveryEnabled = true
}
```

### Delegate Handling

Two callbacks fire for deferred captures:

```swift
// Called for standard photos (non-deferred)
func photoOutput(_ output: AVCapturePhotoOutput,
                 didFinishProcessingPhoto photo: AVCapturePhoto,
                 error: Error?) {
    guard error == nil, let data = photo.fileDataRepresentation() else { return }
    savePhotoToLibrary(data)
}

// Called for deferred proxies -- save to PhotoKit immediately
func photoOutput(_ output: AVCapturePhotoOutput,
                 didFinishCapturingDeferredPhotoProxy proxy: AVCaptureDeferredPhotoProxy,
                 error: Error?) {
    guard error == nil, let proxyData = proxy.fileDataRepresentation() else { return }

    // Save proxy ASAP -- app may be force-quit if backgrounded under memory pressure
    Task {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photoProxy, data: proxyData, options: nil)
        }
    }
}
```

When the photo is later requested from PhotoKit, the system processes the proxy into a full-quality image. To get intermediate quality during processing:

```swift
let options = PHImageRequestOptions()
options.allowSecondaryDegradedImage = true  // iOS 17+

// Callback order:
// 1. Low quality (immediate, isDegraded = true)
// 2. Medium quality (isDegraded = true) -- while processing
// 3. Final quality (isDegraded = false)
```

Limitations: Cannot apply pixel buffer customizations (filters, metadata changes) to deferred photos. Use PhotoKit adjustments after processing for edits. Does not apply to flash captures. Requires iPhone 11 Pro or newer.

## Session Interruption Handling

Five interruption reasons, all of which need UI feedback. The session automatically resumes after the interruption ends -- do not call `startRunning()` again.

```swift
private var interruptionObservers: [NSObjectProtocol] = []

func setupInterruptionHandling() {
    let interrupted = NotificationCenter.default.addObserver(
        forName: .AVCaptureSessionWasInterrupted,
        object: session,
        queue: .main
    ) { [weak self] notification in
        guard let reason = notification.userInfo?[
                  AVCaptureSessionInterruptionReasonKey] as? Int,
              let interruptionReason = AVCaptureSession.InterruptionReason(
                  rawValue: reason) else { return }

        switch interruptionReason {
        case .videoDeviceNotAvailableInBackground:
            self?.showPausedOverlay()

        case .audioDeviceInUseByAnotherClient:
            self?.showBanner("Audio in use by another app")

        case .videoDeviceInUseByAnotherClient:
            self?.showBanner("Camera in use by another app")

        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            self?.showBanner("Camera unavailable in Split View")

        case .videoDeviceNotAvailableDueToSystemPressure:
            self?.handleThermalPressure()

        @unknown default:
            self?.showBanner("Camera interrupted")
        }
    }
    interruptionObservers.append(interrupted)

    let ended = NotificationCenter.default.addObserver(
        forName: .AVCaptureSessionInterruptionEnded,
        object: session,
        queue: .main
    ) { [weak self] _ in
        self?.hideBanner()
        self?.hidePausedOverlay()
    }
    interruptionObservers.append(ended)
}

deinit {
    interruptionObservers.forEach { NotificationCenter.default.removeObserver($0) }
}
```

| Reason | Cause | Typical UI |
|---|---|---|
| `.videoDeviceNotAvailableInBackground` | App backgrounded | Paused overlay |
| `.audioDeviceInUseByAnotherClient` | Phone call, other app | Banner |
| `.videoDeviceInUseByAnotherClient` | Another app using camera | Banner |
| `.videoDeviceNotAvailableWithMultipleForegroundApps` | iPad Split View | Banner with explanation |
| `.videoDeviceNotAvailableDueToSystemPressure` | Device overheating | Reduce quality or show cooling message |

## Front Camera Mirroring

Preview is mirrored (like a mirror -- matches user expectation). Captured photo is NOT mirrored (text reads correctly when shared). This is intentional, matching the system Camera app.

If the product requires mirrored selfie photos:

```swift
func mirrorImage(_ image: UIImage) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }
    return UIImage(cgImage: cgImage, scale: image.scale, orientation: .upMirrored)
}
```

## Camera Switching

```swift
func switchCamera() {
    sessionQueue.async { [self] in
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else {
            return
        }

        let newPosition: AVCaptureDevice.Position =
            currentInput.device.position == .back ? .front : .back

        guard let newDevice = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: newPosition
        ) else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.removeInput(currentInput)

        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                // Update rotation coordinator for new device
                if let previewLayer = previewLayer {
                    setupRotationCoordinator(device: newDevice, previewLayer: previewLayer)
                }
            } else {
                session.addInput(currentInput)  // fallback
            }
        } catch {
            session.addInput(currentInput)  // fallback
        }
    }
}
```

Always switch on the session queue, within `beginConfiguration()`/`commitConfiguration()`. Always restore the old input if the new one fails.

## Video Recording

```swift
let movieOutput = AVCaptureMovieFileOutput()

func setupVideoRecording() {
    sessionQueue.async { [self] in
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        // Add microphone
        if let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
    }
}

func startRecording() {
    guard !movieOutput.isRecording else { return }

    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mov")

    if let connection = movieOutput.connection(with: .video),
       let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture {
        connection.videoRotationAngle = angle
    }

    movieOutput.startRecording(to: outputURL, recordingDelegate: self)
}

func stopRecording() {
    guard movieOutput.isRecording else { return }
    movieOutput.stopRecording()
}
```

### Recording Delegate

```swift
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error {
            print("Recording error: \(error)")
            return
        }
        saveVideoToPhotoLibrary(outputFileURL)
    }
}
```

### Photo Capture Delegate

```swift
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Show shutter animation
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        // Handle photo data
    }
}
```

### Photo Settings

Each capture requires a new `AVCapturePhotoSettings` instance. Settings cannot be reused.

```swift
// HEIF format
let settings = AVCapturePhotoSettings(
    format: [AVVideoCodecKey: AVVideoCodecType.hevc]
)

// Flash
settings.flashMode = .auto  // .off, .on, .auto

// High resolution
settings.maxPhotoDimensions = CMVideoDimensions(width: 4032, height: 3024)

// Embedded thumbnail
settings.embeddedThumbnailPhotoFormat = [
    AVVideoCodecKey: AVVideoCodecType.jpeg,
    AVVideoWidthKey: 160,
    AVVideoHeightKey: 120
]
```

## Device Types

| Type | Description |
|---|---|
| `.builtInWideAngleCamera` | Standard 1x camera |
| `.builtInUltraWideCamera` | Ultra-wide 0.5x |
| `.builtInTelephotoCamera` | Telephoto 2x/3x |
| `.builtInDualCamera` | Wide + telephoto |
| `.builtInTripleCamera` | Wide + ultra-wide + telephoto |
| `.builtInTrueDepthCamera` | Front TrueDepth (Face ID) |

### Discovery Session

```swift
let discovery = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
    mediaType: .video,
    position: .unspecified
)
let cameras = discovery.devices
```

## Device Configuration

```swift
do {
    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }

    if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
    }
    if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
    }
    device.videoZoomFactor = 2.0
} catch {
    // Handle configuration error
}
```
