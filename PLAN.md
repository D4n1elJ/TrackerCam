# TrackerCam — Product & Technical Plan

**Version:** 1.0  
**Date:** 14 June 2026  
**Status:** Locked (v1 scope)  
**Primary target:** iPhone 17 Pro · **Compatibility:** iPhone 16 Pro  

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Goals & Non-Goals](#3-goals--non-goals)
4. [Target Users & Use Cases](#4-target-users--use-cases)
5. [Platform Requirements](#5-platform-requirements)
6. [System Architecture](#6-system-architecture)
7. [Technology Stack](#7-technology-stack)
8. [Tracking & Machine Learning Strategy](#8-tracking--machine-learning-strategy)
9. [Camera Capture Pipeline](#9-camera-capture-pipeline)
10. [Reframe, Crop & Stabilization](#10-reframe-crop--stabilization)
11. [Operator Guidance System](#11-operator-guidance-system)
12. [User Experience & Visual Feedback](#12-user-experience--visual-feedback)
13. [Settings Specification](#13-settings-specification)
14. [Recording & Export](#14-recording--export)
15. [Performance & Thermal Budget](#15-performance--thermal-budget)
16. [Project Structure](#16-project-structure)
17. [Implementation Phases](#17-implementation-phases)
18. [Testing Strategy](#18-testing-strategy)
19. [Risks & Mitigations](#19-risks--mitigations)
20. [Future Expansion](#20-future-expansion)
21. [Apple Documentation References](#21-apple-documentation-references)
22. [Open Decisions](#22-open-decisions)

---

## 1. Executive Summary

TrackerCam is an iOS video recording app for equestrian (and future sport) use cases where the camera operator must physically move to follow a fast-moving subject. Unlike Apple's built-in Action Mode or cinematic stabilization — which smooth camera shake but do not track subjects — TrackerCam:

1. **Detects and tracks** a moving subject (initially a horse) using on-device machine learning.
2. **Captures a 4K video frame** on the iPhone 16/17 Pro main camera.
3. **Reframes in real time** into a 1080p tracked output by cropping and smoothing around the subject so it stays centered in preview and recording.
4. **Guides the operator** with directional arrows when physical movement is needed to maintain framing.
5. **Provides clear visual state feedback** so the operator knows when a target is locked, tracking, or lost.

All processing runs **entirely on-device** with no cloud dependency. The initial release targets horse riding; the architecture is designed to support additional sport profiles later.

---

## 2. Problem Statement

When filming horse riding, the subject moves quickly and unpredictably. The operator must run or ride alongside, pan the phone, and still produce watchable footage. Manual framing fails because:

- **Reaction lag:** Human panning trails fast lateral movement.
- **Shake amplification:** Running while filming introduces motion that makes the subject drift off-center.
- **Cognitive load:** The operator cannot simultaneously focus on riding/safety and precise framing.
- **Post-production burden:** Cropping and stabilizing in editing is time-consuming and crops away resolution if the subject was poorly framed in-camera.

TrackerCam solves this by treating the full 4K frame as a **capture buffer** and delivering a **subject-centered output stream** in real time, while optionally guiding the operator to recover when the subject approaches the edge of the usable crop window.

---

## 3. Goals & Non-Goals

### Goals

| ID | Goal |
|----|------|
| G1 | Real-time subject tracking with visual lock/loss feedback |
| G2 | 4K video capture with GPU-accelerated crop/reframe pipeline and 1080p tracked output |
| G3 | Smooth, stabilized preview and recording centered on the subject |
| G4 | Predictive operator guidance (movement arrows) |
| G5 | Configurable settings for tracking, framing, camera, and recording |
| G6 | On-device inference — no network required during recording |
| G7 | iPhone 17 Pro as primary target; iPhone 16 Pro compatibility |
| G8 | Architecture extensible to other sports beyond equestrian |

### Non-Goals (v1)

| ID | Non-Goal | Rationale |
|----|----------|-----------|
| NG1 | Support all iPhone models | Older devices lack 4K 120fps + Neural Engine headroom |
| NG2 | Cloud upload / live streaming | Out of scope for MVP |
| NG3 | Multi-subject tracking | Complexity; v1 tracks one primary subject |
| NG4 | AR effects / filters | Not core to the framing problem |
| NG5 | Android / cross-platform | iOS-first |
| NG6 | Professional color grading / ProRes RAW workflow | Optional later; HEVC sufficient for MVP |
| NG7 | Automatic horse breed / rider identification | Detection + tracking only |

---

## 4. Target Users & Use Cases

### Primary Persona

**The ground-based equestrian filmmaker** — stands beside an arena or field, operates the app one-handed while looking at the preview, and wants useful training-review footage without post-production cropping.

### Core Use Cases

| Use Case | Description | Priority |
|----------|-------------|----------|
| UC1 | **Mounted filming** — rider records at low speed or from a secure mount; app tracks their horse or a companion horse | Post-v1 |
| UC2 | **Ground filming** — person on foot tracks a horse in an arena or field | P0 |
| UC3 | **Training review** — record the horse, rider, and surrounding context for later coaching review | P0 |
| UC4 | **Social clip export** — 9:16 cropped output for vertical sharing | P2 |

### Safety Constraint

TrackerCam is designed for a stationary or walking ground operator. It must not encourage the operator to run, ride, steer, or otherwise navigate while watching the screen. Guidance is a framing/pan aid, not navigation advice.

### Confirmed Product Decisions

- Recording starts and stops only through an explicit user action; acquiring or losing a target never starts or stops recording.
- Tracking defaults to automatic acquisition and can be overridden by tapping the subject or pressing a prominent `Refocus` control.
- Recording may begin before a target is locked.
- MVP scenes assume one intended horse-and-rider target. Identity continuity is preferred over selecting a new detection after an occlusion.
- Framing prioritizes the entire horse-and-rider compound subject plus useful surroundings. Close-up framing is not a v1 goal.
- Landscape 16:9 provides the largest practical field of view and is the launch priority. Portrait is secondary.
- 1080p is the guaranteed tracked output. 60 fps is preferred when sustainable; 30 fps is the fallback.
- The product is consumer-focused and uses understandable presets with optional advanced settings.
- The primary preset is `Training Review`.
- Camera exposure, focus, and white balance remain automatic for MVP.
- The iPhone 17 Pro is mandatory. iPhone 16 Pro support is best-effort after the primary device passes release gates.
- The app targets the current major iOS release rather than maintaining an iOS 18 compatibility baseline.
- App Store distribution is the intended release path.
- Initial business direction is a free download with an optional in-app upgrade; final paid features remain undecided.
- MVP may assume only one relevant horse-and-rider target is present; multi-horse identity protection is not a launch requirement.
- Critical thermal state stops and finalizes recording rather than continuing without tracking.
- Rear dual-camera capture is deferred; v1 uses one physical rear camera.
- Opt-in crash and performance telemetry is allowed, but footage and frame images remain on-device unless separately and explicitly shared.
- Launch success is measured primarily by tracking retention.
- Representative indoor and outdoor equestrian footage and physical iPhone 17 Pro hardware are available for development.
- The primary landscape grip is right-handed.

### Future Sport Profiles (post-v1)

| Sport | Subject class | Notes |
|-------|---------------|-------|
| Cycling | Person / bicycle | Faster lateral motion, smaller subject |
| Running | Person | Simpler motion, crowded scenes |
| Skiing | Person | High speed, snow glare challenges |
| Dog agility | Dog | Apple's `RecognizeAnimalsRequest` could assist |

---

## 5. Platform Requirements

### Hardware

| Device | Chip | Neural Engine | Camera (relevant) |
|--------|------|---------------|-------------------|
| **iPhone 17 Pro / Pro Max** (primary) | A19 Pro: 6-core CPU, 6-core GPU with Neural Accelerators | 16-core | 48MP Fusion Main; 4K Dolby Vision 24–120 fps on Main; second-generation sensor-shift OIS; LiDAR |
| **iPhone 16 Pro / Pro Max** (compatible) | A18 Pro | 16-core | 48MP Fusion Main; 4K Dolby Vision up to 120 fps; sensor-shift OIS |

**Recommended lens:** Fusion Main (`builtInWideAngleCamera`) — best default balance of field of view, low-light quality, autofocus, stabilization, and detail. The Ultra Wide is physically wider but requires separate distortion and image-quality validation. Telephoto narrows FOV and amplifies operator tracking error.

### iPhone 17 Pro Capability Profile

The following are confirmed hardware/product capabilities from Apple's published iPhone 17 Pro specifications. Availability through a custom `AVCaptureSession`, and compatibility between features, must still be checked at runtime.

| Capability | Apple specification | TrackerCam relevance |
|------------|---------------------|----------------------|
| Compute | A19 Pro; 6-core CPU; 6-core GPU with Neural Accelerators; 16-core Neural Engine | Concurrent Vision/Core ML, Metal crop/scale, and hardware encoding; actual sustained concurrency requires profiling |
| Main camera | 48MP Fusion Main, 24 mm equivalent, ƒ/1.78, 100% Focus Pixels | Primary lens for low-light performance, autofocus coverage, and usable framing headroom |
| Main stabilization | Second-generation sensor-shift optical image stabilization for video | Complements software crop stabilization; delivered-buffer geometry remains the app's coordinate source |
| Ultra Wide | 48MP Fusion Ultra Wide, 13 mm equivalent, 120° field of view | Potential recovery/maximum-headroom lens; deferred until distortion, quality, and low-light tests pass |
| Telephoto | 48MP Fusion Telephoto, 100 mm equivalent (4x), 3D sensor-shift OIS and autofocus | Not recommended for default tracking because narrow FOV magnifies framing error |
| Video rates | 4K Dolby Vision at 24/25/30/60 fps and 100/120 fps on Fusion Main | Supports standard, smooth, and high-speed capture experiments |
| Slo-mo | 4K Dolby Vision up to 120 fps on Fusion Main; 1080p up to 240 fps | Possible analysis/slow-motion mode; not an MVP sustained-tracking promise |
| Stabilization | Cinematic video stabilization at 4K, 1080p, and 720p; Action mode up to 2.8K/60 | TrackerCam uses AVFoundation stabilization modes where supported; it does not assume access to Apple's Camera-app Action mode pipeline |
| Codecs/formats | HEVC, H.264, ProRes, ProRes RAW; Apple Log 2; ACES support | HEVC SDR is MVP; professional capture formats are deferred |
| ProRes | Up to 4K/120 with external recording | Relevant only to a future external-storage/pro workflow |
| Dual Capture | Up to 4K Dolby Vision at 30 fps | Does not imply two independently configurable rear-camera video data outputs; treat as a separate future experiment |
| Audio | Four studio-quality microphones, Spatial Audio/stereo recording, wind-noise reduction | Deferred for MVP; current app records video-only until an audio capture/writer path is implemented and field-tested |
| Display | 6.3-inch OLED, ProMotion up to 120 Hz, up to 3000 nits peak outdoor brightness | High-refresh, outdoor-visible preview; app should reduce display refresh/brightness expectations under thermal pressure |
| Storage | 256GB, 512GB, or 1TB on Pro; Pro Max also offers 2TB | Recording-time estimates must use actual free capacity, not model capacity |
| I/O | USB-C with USB 3 up to 10 Gb/s and DisplayPort | Future external recording/export and field-monitor workflows |
| Motion sensors | High dynamic range gyro and high-g accelerometer | Optional camera-motion compensation and shake telemetry |
| Thermal environment | Apple operating ambient range 0–35°C (32–95°F) | Outdoor summer use may reach the limit; test in sun and treat thermal degradation as core behavior |

The 48MP photo sensor specification does not imply that AVFoundation supplies a 48MP video buffer. TrackerCam's initial spatial buffer is the delivered 4K video frame. Any higher-than-4K capture assumption must be proven by enumerating accessible `AVCaptureDevice.Format` values on physical hardware.

### iPhone 17 Pro TrackerCam Operating Envelope

| Mode | Intended status | Initial configuration | Required validation |
|------|-----------------|-----------------------|---------------------|
| 4K30 source → 1080p30 tracked | **MVP baseline** | Main camera, HEVC SDR, best supported stabilization, ML at 30 fps | 30-minute recording, p95 latency, thermal, battery, dropped frames |
| 4K60 source → 1080p60 tracked | MVP candidate | Main camera, ML at up to 60 fps, detector every 0.5–1.0 s | 20-minute sustained test and writer throughput |
| 4K100/120 source → 1080p100/120 tracked | Experimental | Main camera, analysis frame skipping, reduced detector cadence | Format access, stabilization compatibility, GPU/encoder throughput, severe thermal behavior |
| 4K source → vertical 1080×1920 tracked | MVP candidate | Main camera, dynamic 9:16 crop | Subject containment and horizontal headroom |
| Ultra Wide tracked capture | Post-MVP candidate | 13 mm lens with lens correction | Distortion-coordinate alignment, detector accuracy, low-light quality |
| ProRes/Log/external storage | Post-v1 | External drive over USB 3 | Filesystem, bandwidth, heat, color management, interruption recovery |

No mode is considered supported merely because the Camera app or product specification advertises the component capability. TrackerCam exposes a mode only after the exact AVFoundation format, frame duration, pixel format, stabilization mode, color space, and output pipeline combination passes the device validation matrix.

### Runtime Capability Discovery

At startup and after a camera change, build a `DeviceCapabilityProfile` from the active hardware:

```swift
struct DeviceCapabilityProfile: Sendable {
    let deviceModelIdentifier: String
    let cameraUniqueID: String
    let supportedCaptureModes: [CaptureMode]
    let stabilizationModesByCaptureMode: [CaptureMode.ID: Set<StabilizationMode>]
    let supportedColorSpacesByCaptureMode: [CaptureMode.ID: Set<CaptureColorSpace>]
    let supportsDepthData: Bool
    let supportsExternalStorageWorkflow: Bool
}
```

Each `CaptureMode` records dimensions, min/max frame rate, pixel subtype, field of view, video zoom limits, color spaces, whether the format is video-binned, and whether the app has passed its own validation for that exact combination. Persist benchmark results by device model, OS build, and app version, but rediscover system capabilities every launch.

The settings UI must be capability-driven:

- Hide or disable unsupported frame-rate, stabilization, HDR, and lens combinations.
- Explain why a requested combination changed after session configuration.
- Distinguish `hardwareSupported`, `appValidated`, and `currentlyAvailable`.
- Revert atomically to the last working configuration when session reconfiguration fails.
- Record the requested and effective configuration in diagnostics and recording metadata.

### Software

| Requirement | Value |
|-------------|-------|
| Minimum iOS | **iOS 26.0** |
| Target iOS | **Latest stable iOS 26.x SDK available at release** |
| Language | Swift 6 |
| UI framework | SwiftUI |
| Xcode | Latest stable supporting iOS 26 SDK |

### Permissions

- **Camera** — required
- **Microphone** — deferred; do not request until audio capture is implemented
- **Photo Library (add only)** — optional, for saving recordings

Background camera recording is explicitly unsupported. If the app leaves the foreground, preserve the current file and follow the interruption policy in §14.

---

## 6. System Architecture

### High-Level Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AVCaptureSession                             │
│  Main wide camera · 4K video format · configurable frame rate      │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                       ┌────────▼────────┐
                       │ 4K source buffer│
                       └───┬─────────┬───┘
                           │         │
              ┌────────────┘         └─────────────┐
      ┌───────▼────────┐                 ┌─────────▼─────────┐
      │ GPU downscale  │                 │ 4K source texture │
      │ 720p ML input  │                 │ held for reframe  │
      └───────┬────────┘                 └─────────┬─────────┘
              │                                    │
    ┌─────────▼──────────────────────┐             │
    │       TrackingEngine          │             │
    │ Detect (Core ML, timed cadence)│             │
    │ Track (Vision, effective fps)  │             │
    │ Smooth + predict               │             │
    └────────┬───────────────────────┘             │
             │ TrackingState                       │
             │ (PTS, bbox, velocity, confidence)   │
       ┌─────┴─────────────┐                       │
       │                   │                       │
┌──────▼─────────┐  ┌──────▼────────┐              │
│ GuidanceEngine │  │ CropController│              │
│ pan/aim hint   │  │ center + scale├──────────────┤
└──────┬─────────┘  └───────────────┘              │
       │                                 ┌─────────▼─────────┐
       │                                 │ ReframePipeline   │
       │                                 │ Metal crop + scale│
       │                                 └─────────┬─────────┘
       │                                           │
    ┌────────▼──────────────────────────────▼─────────┐
    │              SwiftUI Camera View                 │
    │  Cropped preview · overlays · arrows · status    │
    └────────────────────────┬────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │ RecordingService │
                    │ AVAssetWriter    │
                    │ (cropped HEVC)   │
                    └─────────────────┘
```

### Module Responsibilities

| Module | Responsibility |
|--------|----------------|
| `CameraService` | `AVCaptureSession` lifecycle, format selection, orientation, exposure, stabilization mode |
| `FrameRouter` | Retains each 4K sample buffer, schedules GPU downscale for ML, and routes the source buffer to reframe/record consumers |
| `TrackingEngine` | Detection, tracking, smoothing, state machine (idle → searching → locked → tracking → lost) |
| `CropController` | Converts timestamped tracking observations into a bounded, smoothed crop center and dynamic crop size |
| `ReframePipeline` | GPU crop/scale on full-resolution buffers; produces preview and record textures |
| `GuidanceEngine` | Computes camera pan/aim hints from framing error, crop headroom, and predicted velocity |
| `RecordingService` | `AVAssetWriter` pipeline for cropped output; optional full-frame 4K backup |
| `OverlayRenderer` | Bounding box, status chrome, arrows, confidence indicators |
| `SettingsStore` | Persistent user preferences |
| `ThermalManager` | Monitors `ProcessInfo.thermalState`; triggers quality degradation |

### Concurrency Model

- **Capture callback queue:** High-priority serial queue; minimal work — retain and route one source buffer only.
- **Processing queue:** ML inference + Vision tracking.
- **GPU queue:** Metal command buffer submission for crop.
- **Main actor:** All SwiftUI state updates, overlay rendering inputs.

Use Swift 6 `async`/`await` for Vision's new request API. Avoid blocking the capture callback.

**Swift 6 strict-concurrency caveat:** `CMSampleBuffer`, `CVPixelBuffer`, and `MTLTexture` are **not `Sendable`**. They are reference-like Core Foundation/Metal types and cannot be passed across actor or task boundaries under Swift 6 strict concurrency without an explicit transfer strategy. Adopt one of:

- A dedicated `struct FramePayload: @unchecked Sendable` wrapper that carries the buffer plus its `FrameContext`, with a documented single-owner hand-off contract (the sender stops touching the buffer after enqueue).
- `sending` parameters (Swift 6 region-based isolation) on the queue hand-off functions so the compiler proves single ownership without `@unchecked`.

Do not make `CameraService`/`FrameRouter` a global actor — capture-callback latency must not depend on actor-hop scheduling. Prefer plain serial `DispatchQueue`s for the capture and GPU paths and confine `@MainActor` to UI state only.

### Frame Identity and Timing Contract

Every source frame receives a `FrameContext` that remains authoritative across downscale, tracking, crop, preview, metadata, and recording:

```swift
struct FrameContext: Sendable {
    let sequenceNumber: UInt64
    let presentationTime: CMTime
    let sourceDimensions: CGSize
    let rotationAngle: CGFloat
    let isMirrored: Bool
    let effectiveStabilizationMode: AVCaptureVideoStabilizationMode
}
```

All observations and crop decisions carry the source frame's `presentationTime`. Never apply a tracking result to an arbitrary "latest" frame without prediction. When an observation arrives late, predict its state forward by:

```
predictionDelta = renderFramePTS - observationPTS
predictedCenter = observedCenter + velocity × predictionDelta
```

Clamp `predictionDelta` to 0–200 ms. Discard observations older than 250 ms or from a previous session generation. Increment the session generation whenever the camera format, lens, orientation, or capture session is reconfigured.

### Backpressure and Buffer Ownership

- Keep at most three source frames in flight through the GPU path and one pending ML inference per tracker.
- **Detection is skippable; tracking is not.** Use a latest-wins queue only for the *detector*: when detection falls behind, discard stale pending analysis frames rather than increasing latency. The frame-to-frame *tracker* (`VNTrackObjectRequest` on a `VNSequenceRequestHandler`) is stateful and must receive frames sequentially in PTS order — never drop frames from the tracker stream, or its motion model degrades. If the tracker itself cannot keep cadence, reduce the effective tracking frame rate deterministically (e.g. process every Nth frame consistently) rather than dropping irregularly, and re-seed from the next detector pass.
- Never discard a frame already accepted by `AVAssetWriter`; preview may drop frames independently.
- Retain `CMSampleBuffer`/`CVPixelBuffer` only until all scheduled consumers have taken ownership, then release promptly.
- Record counters for capture drops, analysis drops, preview drops, writer backpressure, and stale observation rejection.

---

## 7. Technology Stack

| Layer | Technology | Apple / Third-Party Reference |
|-------|------------|-------------------------------|
| UI | SwiftUI | — |
| Camera | AVFoundation | [AVCam sample](https://developer.apple.com/documentation/AVFoundation/avcam-building-a-camera-app) |
| Object detection | Core ML (YOLO26n or fine-tuned) | [Core ML Models](https://developer.apple.com/machine-learning/models/), [Ultralytics Core ML](https://docs.ultralytics.com/integrations/coreml/) |
| Object tracking | Vision `TrackObjectRequest` | [Tracking in video](https://developer.apple.com/documentation/Vision/tracking-multiple-objects-or-rectangles-in-video) |
| GPU image processing | Metal + Core Image | [Core Image](https://developer.apple.com/documentation/coreimage), optional [MetalPetal](https://github.com/MetalPetal/MetalPetal) |
| Video encoding | AVAssetWriter (HEVC) | AVFoundation |
| Motion (optional) | CoreMotion | Gyro-assisted prediction refinement |
| Persistence | `@AppStorage` / SwiftData | Settings and sport profiles |
| Haptics | `UIImpactFeedbackGenerator` | Lock/lost feedback |

---

## 8. Tracking & Machine Learning Strategy

### Why Not Apple-Only APIs?

| Apple API | Supports horses? | Role in TrackerCam |
|-----------|------------------|-------------------|
| `RecognizeAnimalsRequest` | **No** — cats and dogs only | Not usable for horses |
| `DetectAnimalBodyPoseRequest` | **No** — cats and dogs only | Not usable for horses |
| `GenerateObjectnessBasedSaliencyImageRequest` | Generic saliency | Fallback for "largest moving object" mode |
| `TrackObjectRequest` | **Yes** — any object from seed bbox | **Primary tracker** once target is acquired |
| `TrackRectangleRequest` | **Yes** — any rectangle | Alternative seed from user tap |

**Conclusion:** A custom Core ML detector is required for horse acquisition and re-acquisition. Vision tracking handles frame-to-frame follow.

### Hybrid Detect + Track Pipeline

```
At tracking cadence: Vision TrackObjectRequest → bbox_t
At timed cadence:    Core ML Detect (horse)    → refresh / re-acquire
For every result:    Kalman filter             → smoothed position + velocity
```

The detector cadence is configured in time (`redetectionInterval`, default 0.5 s), then converted to frames using the effective processing frame rate. At 30 fps this is 15 frames.

**API note (verified against the new Swift Vision API, iOS 18+ / carried into iOS 26):** The value-type `TrackObjectRequest` and `TrackRectangleRequest` *do* exist in the new Swift Vision API and return `DetectedObjectObservation`, which carries the tracked bounding box plus position/velocity. Detection uses `CoreMLRequest` in the same value-type API. What the new API does **not** clearly document is the cross-frame state mechanism: tracking is inherently stateful (each frame's result depends on the previous frame), and the established API expressed this through a per-sequence `VNSequenceRequestHandler` fed strictly in PTS order, recreated whenever the session generation increments (camera/lens/orientation/format change). The one Phase 0 spike that must close this: confirm on the shipping iOS 26 SDK whether `TrackObjectRequest` manages sequence state internally (e.g. a reusable request instance carried frame to frame) or still requires an explicit sequence handler. Isolate this entirely behind `TrackingEngine` so the rest of the app is API-agnostic; if the new tracking surface proves immature, fall back to `VNSequenceRequestHandler` + `VNTrackObjectRequest` for tracking while keeping `CoreMLRequest` for detection.

### Detection Model Options

| Model | Latency (iPhone 17 Pro, sustained) | Accuracy for horses | Recommendation |
|-------|-------------------------------------|---------------------|----------------|
| YOLO26n + COCO "horse" class | ~16 ms/frame in live pipeline | Moderate; misses partial/occluded horses | **MVP default** |
| YOLO26s (small) | ~25–35 ms | Better | Optional "high accuracy" setting |
| Fine-tuned YOLO on equestrian footage | Similar to base model | **Best** | **v1.1 priority** — train on user's own clips |

**Export candidate:** Core ML `.mlpackage`, fixed input size, and INT8 quantization calibrated with representative equestrian footage. YOLO26 is **end-to-end / NMS-free** by design — its Core ML export emits final boxes without a separate non-maximum-suppression pass, removing the in-app NMS step that older YOLO exports required. Verify this holds for the exact export configuration on the iOS 26 deployment target; keep a CPU-side NMS fallback only if a non-end-to-end export is substituted.

**Runtime candidate:** Configure `MLModelConfiguration.computeUnits` after profiling. Start with `.all`; compare `.cpuAndNeuralEngine` and other supported configurations for latency, power, and contention with the Metal reframe pipeline.

### Target Acquisition Modes

| Mode | Flow | Default |
|------|------|---------|
| **Tap-to-track** | User taps subject → choose the best compound subject containing or near the tap; if none exists, create a clamped seed box equal to 20% of the shorter frame dimension → start `TrackObjectRequest` | Available |
| **Auto-detect** | Run detector → select the highest-confidence compound horse/rider target nearest center | Available |
| **Auto + manual refocus** | Auto acquisition runs when no identity is locked; tap or `Refocus` clears the current identity and requests a new seed | **Default** |

The `Refocus` button is always reachable from the recording screen with one hand. A single press runs immediate detection and selects the strongest candidate; tapping the preview selects a specific candidate. Refocus does not affect recording state.

### Compound Horse-and-Rider Target

The composition target is a compound envelope rather than a horse-only box:

1. Detect `horse` and `person` classes on each detector pass.
2. Choose one horse using confidence, center proximity, size, and identity continuity.
3. Associate a rider when a person box overlaps the upper horse region or lies within a validated saddle-region distance.
4. Form the union of the horse and rider boxes.
5. Expand the union by environmental padding before sending it to `CropController`.

If no rider is detected, estimate a conservative rider region by extending the horse box upward by up to 60% of horse height, clamped to the source frame. This heuristic is used only for framing and does not claim rider detection.

MVP supports one compound target and assumes no competing horse is relevant. Prefer continuity when possible, but do not add appearance-embedding or multi-horse identity complexity to the MVP. Explicit refocus always replaces the current target.

### Identity Continuity (Post-Prototype)

Maintain a target signature containing the latest compound box, rider association, motion state, last-seen timestamp, and an appearance embedding if it fits the performance budget. Candidate matching after occlusion uses:

```
identityScore =
    0.35 × predictedPositionScore +
    0.25 × sizeAndAspectScore +
    0.20 × motionConsistencyScore +
    0.20 × appearanceScore
```

If no appearance embedding is available, redistribute its weight across position and motion. Reacquire only above a validated identity threshold. Otherwise remain lost and request refocus rather than silently switching horses.

### Selection Heuristics (auto-detect)

When multiple detections exist, score each candidate:

```
score = confidence × centerProximityWeight × sizeWeight
```

Prefer large, central, high-confidence detections. Reject detections below confidence threshold (configurable, default 0.45).

**Two distinct thresholds — do not conflate:** `detectionConfidenceThreshold` (default 0.45) gates whether a *Core ML detector* output is accepted as a candidate during acquisition/re-detection. `trackingConfidenceThreshold` (default 0.50, §13) gates the *Vision tracker's* per-frame confidence in the state machine (lock/lost transitions). They measure different signals from different subsystems and are tuned independently.

### Tracking State Machine

```
                    ┌──────────┐
         app start  │   idle   │
              ─────►│          │
                    └────┬─────┘
                         │ user tap / auto-detect seed
                    ┌────▼─────┐
                    │ searching │  (detector running, no stable track)
                    └────┬─────┘
                         │ track confidence > threshold for M frames
                    ┌────▼─────┐
              ┌────►│  locked   │  (visual confirmation, haptic)
              │     └────┬─────┘
              │          │ M frames elapsed
              │     ┌────▼─────┐
              │     │ tracking  │  (normal operation)
              │     └────┬─────┘
              │          │ confidence < threshold for K frames
              │     ┌────▼─────┐
              └─────│   lost    │  (prompt re-acquire)
                    └──────────┘
```

| Parameter | Default | Setting key |
|-----------|---------|-------------|
| Lock confirmation | 0.17 s | Internal |
| Lost-track timeout | 0.33 s | `lostTrackTimeout` |
| Confidence threshold | 0.5 | `trackingConfidenceThreshold` |

Durations are authoritative. Convert them to frame counts using the effective tracking cadence so behavior remains consistent at 30, 60, and 120 fps capture presets.

### Coordinate Mapping

Vision returns normalized coordinates (origin bottom-left). All internal math uses delivered source-buffer pixel coordinates. Convert via `toImageCoordinates(from:inputImageSize:orientation:)` per [WWDC24 Vision updates](https://developer.apple.com/videos/play/wwdc2024/10163/).

### Re-Acquisition Logic

On each re-detection frame:

1. Run Core ML detector.
2. If a detection overlaps current track (IoU > 0.3) → update seed, continue tracking.
3. If no overlap and track confidence is dropping → transition to `searching`.
4. If lost longer than `lostTrackTimeout` → show "Tap to re-acquire" UI while auto-detection continues when enabled.

For the MVP single-target assumption, reacquire the strongest plausible compound target near the predicted location. A later multi-horse mode may reserve identity for at least 5 seconds and apply the identity threshold. The `Refocus` action immediately clears any reservation.

### Fine-Tuned Model Roadmap

1. Collect 500–2000 labeled frames from equestrian footage (user's own videos, diverse lighting/angles).
2. Fine-tune YOLO26n on horse bounding boxes.
3. Include hard cases: partial occlusion, motion blur, dust, multiple horses.
4. Ship as downloadable model pack or bundled asset; A/B against COCO baseline.

---

## 9. Camera Capture Pipeline

### Session Configuration

```swift
// Pseudocode — illustrative
session.sessionPreset = .inputPriority
device.activeFormat = /* 4K format matching user fps setting */
device.activeVideoMinFrameDuration = /* exact supported duration */
device.activeVideoMaxFrameDuration = /* same duration */
connection.preferredVideoStabilizationMode = bestSupportedMode(
    requested: settings.stabilization,
    connection: connection
)
```

Lock the device for configuration once per atomic change, set format/frame durations/color space/exposure policy, unlock, then verify the effective connection state. If any step fails, roll back the complete configuration rather than leaving a partially applied mode.

### Output Branches

| Branch | Resolution | Purpose |
|--------|------------|---------|
| **Source video** | 4K (typically 3840×2160) | Single `AVCaptureVideoDataOutput` source for crop, preview, and recording |
| **Processing** | GPU-downscaled 1280×720 default; model input may be smaller | ML detection + Vision tracking |
| **Audio** | AAC via `AVCaptureAudioDataOutput` | Synchronized to video |

The MVP architecture uses one 4K video output and derives the processing image with Metal or Core Image. Do not assume that a second `AVCaptureVideoDataOutput` can independently deliver a lower resolution from the same camera format.

**Phase 0 feasibility gate:** On every target device and capture preset, validate the selected format, pixel format, stabilization support, delivered dimensions, frame cadence, and ability to sustain GPU downscale plus buffer fan-out. If a multi-output topology is later considered, it must pass this matrix before replacing the single-source design.

### Frame Rate Presets

| Preset | Capture fps | ML cadence | Use case |
|--------|-------------|------------|----------|
| Standard | 30 | Track at 30 fps, detect every 0.5 s | Default; best thermal |
| Smooth | 60 | Track at up to 60 fps, detect every 0.5 s | Fast motion |
| Slo-mo capture | 120 | Track at 30–60 fps, detect every 0.5–1.0 s | High-speed; thermal warning |

**Note:** 4K @ 120 fps + full ML pipeline is not sustainable. When 120 fps is selected, default to recording at 120 fps but processing at 30–60 fps effective (frame skip), with UI indication.

On iPhone 17 Pro, include 100 fps when exposed by the selected Fusion Main format. Do not round 100 fps to 120 fps in metadata or timing calculations. Use exact `CMTime` frame durations and derive analysis cadence from timestamps rather than modulo frame counts.

### Lens Policy on iPhone 17 Pro

- Default to the physical Fusion Main camera, not an automatic virtual-device lens switch.
- Lock the selected physical lens during recording so the field of view and coordinate transform cannot change unexpectedly.
- Treat the Main camera's optical-quality 2x mode as a crop/processing choice, not additional physical framing headroom.
- Do not expose 4x/8x Telephoto modes until tracking-retention tests demonstrate acceptable loss rates.
- Evaluate Ultra Wide as a user-selected recovery mode, never an automatic mid-recording switch in v1.
- Store effective focal length/field of view and zoom factor with recording diagnostics.

### Stabilization Strategy (two layers)

| Layer | Mechanism | What it fixes |
|-------|-----------|---------------|
| **Hardware / AVFoundation** | Best supported stabilization mode for the active format | Operator walking bounce, hand shake |
| **Software reframe** | Kalman-smoothed crop window | Subject drift within frame |

These are complementary, but stabilization support is format- and frame-rate-dependent. Query support on the active connection and fall back in this order: `.cinematicExtended`, `.cinematic`, `.standard`, `.off`. The UI must display the effective mode rather than only the requested setting.

The ML input and reframe source must be derived from the same delivered, stabilized video buffer. Tracking coordinates therefore describe that delivered buffer, not an assumed raw sensor field of view. A calibration test must verify that bounding boxes, crop rectangles, preview, and encoded output remain aligned for each supported stabilization mode.

### Color Space & Dynamic Range

The default SDR decision (D10) must be enforced explicitly at capture configuration — it is not the automatic behavior. Several 4K formats on the iPhone 17 Pro Fusion Main are HDR (HLG / Dolby Vision) capable and the system may enable HDR automatically:

- Set `device.activeColorSpace` deliberately. For MVP SDR, select `.sRGB` or `.P3_D65`; reserve `.HLG_BT2020` and `.appleLog` for the deferred HDR/Log workflow.
- Set `device.automaticallyAdjustsVideoHDREnabled = false` and `device.isVideoHDREnabled = false` for SDR capture where the active format permits it; otherwise pick an SDR-native format from the format enumeration.
- Record the requested and effective color space in the `CaptureMode` validation record and recording metadata. A format advertising Dolby Vision does not mean the app-validated SDR path is available on that exact format.
- The Metal reframe shader must know the working color space; sampling an HDR (PQ/HLG) buffer as if it were SDR produces incorrect tone/levels. Keep one documented color pipeline shared by preview and recording.
- Confirm the chosen color space survives the full path: capture → Metal crop/scale → `AVAssetWriter`. HDR passthrough is enabled only after this is validated end to end (D10).

### Orientation

Handle device rotation via `AVCaptureDevice.RotationCoordinator` (iOS 17+), reading `videoRotationAngleForHorizonLevelCapture`/`videoRotationAngleForHorizonLevelPreview` and applying the angle to the relevant `AVCaptureConnection.videoRotationAngle`. Prefer the coordinator over manual `UIDevice` orientation bookkeeping so preview and capture rotation stay consistent. All bbox and crop math must account for rotation consistently across processing and source buffers.

Lock output orientation and dimensions when recording starts. Ignore physical orientation changes until recording stops, while keeping controls readable where practical. Orientation may change freely while not recording.

---

## 10. Reframe, Crop & Stabilization

### Concept

The 4K video frame is a **spatial buffer**. The tracked MVP output is a smaller window, normally 1920×1080, whose center and size change dynamically to preserve composition:

```
desiredCropCenter = compositionTarget(trackedSubject, motion)
desiredCropSize = zoomController(trackedSubject.boundingBox)
cropRect = aspectFitRect(center: desiredCropCenter, size: desiredCropSize)
cropRect = clampInsideSource(cropRect)
```

The encoded output dimensions remain fixed. Dynamic zoom changes the source crop size, then scales that crop to the fixed output texture.

### Composition Model

Use the subject bounding box, not only its center. The default composition target places the horse slightly below center and leaves space in the direction of travel:

```
direction = normalizedOrZero(smoothedVelocity)
horizontalLead = direction.x × cropWidth × leadFraction
verticalOffset = cropHeight × verticalCompositionOffset
desiredCropCenter = subjectCenter + (horizontalLead, verticalOffset)
```

| Parameter | Default | Range |
|-----------|---------|-------|
| `targetSubjectHeight` | 35% of output height | 25–55% |
| `compositionLeadFraction` | 8% of crop width | 0–20% |
| `verticalCompositionOffset` | -5% of crop height | -15–10% |
| `subjectPadding` | 20% around compound bbox | 10–35% |

Negative vertical offset moves the crop center upward, placing the subject lower in the final frame. The subject envelope means horse plus rider when associated. For portrait output, calculate subject size from height and reduce horizontal lead to avoid excessive lateral movement.

### Dynamic Zoom Controller

Compute the crop required to contain the padded subject at the target size:

```
requiredCropHeight = paddedSubjectHeight / targetSubjectHeight
requiredCropWidth = requiredCropHeight × outputAspectRatio
```

If the required width does not contain the padded subject, derive size from width instead. Clamp the result between:

- **Maximum zoom-in:** crop dimensions no smaller than the output dimensions by default, preserving one source pixel per output pixel.
- **Maximum zoom-out:** largest crop of the selected aspect ratio that fits inside the delivered source frame.
- **Optional digital upscale:** disabled for MVP. If enabled later, expose the upscale factor and cap it explicitly.

Apply asymmetric zoom rates:

| Transition | Maximum rate | Rationale |
|------------|--------------|-----------|
| Zoom out | 80% crop-size change per second | Recover headroom quickly |
| Zoom in | 25% per second | Avoid conspicuous pumping |

Use a 5% subject-size hysteresis band and require the target size to remain outside the band for 150 ms before zooming in. Zoom out immediately when padded subject bounds would breach the safe frame.

### Motion Smoothing

Use a **Kalman filter** on `(x, y, vx, vy)`:

- **Process noise:** Tuned by `smoothingStrength` setting (low = more responsive, high = more stable).
- **Measurement noise:** Derived from tracking confidence (lower confidence → more smoothing, less reactive).

Fallback: exponential moving average (EMA) if Kalman tuning is deferred to a later phase.

Filter crop center and logarithmic crop scale independently. Apply acceleration and jerk limits after filtering so one noisy observation cannot cause a visible snap:

| Quantity | Initial target |
|----------|----------------|
| Maximum crop-center speed | 1.5 source-frame widths/s |
| Maximum crop-center acceleration | 6 frame widths/s² |
| Maximum scale acceleration | 2.0 log-scale units/s² |

These are tuning baselines, not release constants. Final values come from the field-test corpus and must be identical for preview and recording.

### Prediction / Lead

Offset the composition target by the estimated subject velocity and the measured pipeline delay:

```
effectiveLeadTime = userLeadTime + measuredPipelineDelay
cropCenter = smoothedPosition + effectiveLeadTime × predictedVelocity
```

`userLeadTime` defaults to 0.10 seconds. `measuredPipelineDelay` uses a rolling p50 capture-to-preview estimate and is capped at 100 ms to prevent runaway prediction.

### Crop State Machine

| Tracking state | Crop behavior |
|----------------|---------------|
| `idle` | Hold a centered default crop |
| `searching` | Hold position; ease toward a crop 15% wider than default |
| `locked` | Blend from current crop to target over at least 300 ms |
| `tracking` | Follow timestamp-aligned center and dynamic zoom controller |
| `lost` for < 0.75 s | Continue constant-velocity prediction while rapidly zooming out |
| `lost` for 0.75–2.0 s | Ease crop center toward source center and continue zooming out |
| `lost` for > 2.0 s | Hold a centered maximum zoom-out crop until identity-safe reacquisition or manual refocus |

Reacquisition must not snap. Blend from the current crop to the new target using a critically damped transition of at least 250 ms, unless immediate zoom-out is required to keep the subject visible.

Recording continues throughout all tracking states. Loss never freezes the last close crop indefinitely; it returns to a centered wide view so the operator can continue filming manually.

### GPU Pipeline

1. Receive full-res `CVPixelBuffer` on Metal-accessible queue.
2. Obtain the crop decision matching the frame PTS or predict from the newest valid observation.
3. Convert the crop from canonical top-left source-pixel coordinates into texture coordinates once.
4. Sample the crop into a fixed-size output texture with a high-quality linear filter.
5. Render to `CAMetalLayer` for preview.
6. Pass to `AVAssetWriter` for recording.

**Latency target:** < 8 ms for 4K crop on A19 Pro.

Use one crop decision and one sampling implementation for preview and recording. Overlays are rendered in a separate pass and are included in the file only when `overlayInRecording` is enabled.

### Coordinate System Contract

- Canonical geometry uses source pixels with origin at top-left, x rightward, and y downward.
- Vision-normalized bottom-left coordinates are converted at the Vision boundary only.
- Crop rectangles use floating-point values until shader sampling; do not round each frame.
- Clean aperture and pixel aspect ratio metadata must be honored when present.
- Rotation and mirroring are represented as transforms, not by mutating bounding boxes in multiple modules.
- All rectangles are validated for finite values, positive area, expected aspect ratio, and source containment.

### Aspect Ratio Modes

| Mode | Output dimensions | Notes |
|------|-------------------|-------|
| 16:9 landscape | 1920×1080 | Default tracked output |
| 9:16 portrait | 1080×1920 | Secondary social mode |
| 1:1 square | 1080×1080 | Post-MVP |
| Full frame | No crop; tracking overlay only | "Tracking assist" mode |

A tracked 4K output cannot pan within a 3840×2160 source because the crop has no spatial headroom. Any future "4K tracked" mode must use a source larger than the output or explicitly upscale a smaller crop and label that behavior in the UI and metadata.

### Edge Behavior

When the subject approaches the edge of the 4K buffer (crop window hits boundary):

- Crop clamping stops following — subject drifts toward edge of output.
- Guidance arrows intensify.
- Dynamic zoom immediately widens toward the largest valid aspect-ratio crop.
- If one axis remains constrained after zooming out, preserve the unconstrained axis smoothing rather than freezing both axes.

Define normalized crop headroom per edge:

```
headroom.left = crop.minX / availablePanX
headroom.right = (sourceWidth - crop.maxX) / availablePanX
```

When `availablePanX` or `availablePanY` is zero, report zero headroom for that axis. Guidance becomes amber below 20% remaining headroom and red below 8%.

---

## 11. Framing Guidance System

### Purpose

Distinguish between:

- **Where the horse is going** (subject velocity vector)
- **Where the operator should pan/aim the phone** (framing error)

The guidance does not infer safe physical movement or navigation. It only indicates the camera aiming correction needed to restore framing.

### Algorithm

```
framingError = subjectCenter_inFullFrame - fullFrameCenter
predictedDrift = predictedVelocity × lookaheadSeconds
framingHint = framingError + predictedDrift
```

If `|framingHint| < deadZone` → no arrows displayed.  
Else → render directional chevrons at screen edge pointing in `normalize(framingHint)` direction.

### Visual Design

| Element | Behavior |
|---------|----------|
| **Chevrons** | 3 animated arrows on the edge nearest the hint direction |
| **Intensity** | Arrow opacity/scale proportional to `|framingHint|` and diminishing crop headroom |
| **Color** | White at low error, amber at medium, red at critical (near loss) |
| **Haptic** | Light pulse when entering amber zone; warning when entering red |

### Settings

| Setting | Default | Range |
|---------|---------|-------|
| `guidanceEnabled` | true | bool |
| `guidanceDeadZone` | 8% of frame | 3–20% |
| `guidanceLookahead` | 0.3 s | 0–1.0 s |
| `guidanceHaptics` | true | bool |

---

## 12. User Experience & Visual Feedback

### Screen Layout

```

### One-Handed Recording Controls

- Optimize `Record` and `Refocus` for a right-hand landscape grip: place them near the right edge in the lower/right thumb-reachable region. Mirror or adapt controls for the opposite orientation without making it the primary tuning target.
- Record uses a large circular control with at least a 60×60 pt hit target; Refocus uses at least 52×52 pt.
- A recording press is always manual and does not wait for tracking lock.
- Disable settings that require session reconfiguration while recording; allow overlay visibility, guidance, dynamic-zoom lock, and refocus to change live.
- Show recording state through elapsed time, persistent red treatment, and haptic confirmation.
- Refocus must remain available while recording and must not interrupt the writer.
- Avoid modal dialogs during normal recording. Storage-critical and unrecoverable camera/writer errors are the only blocking alerts.
- Support both landscape-left and landscape-right at the capture level, but optimize physical control placement for the validated primary grip orientation before release.

### Automatic Camera Policy

- Continuous autofocus, auto exposure, and auto white balance are the MVP defaults.
- Tracking does not lock focus or exposure to the subject.
- When supported, bias the metering point toward the compound subject with slow transitions and conservative limits; fall back to center-weighted automatic behavior.
- Prevent abrupt exposure pumping by rate-limiting metering-point changes and avoiding updates during low-confidence tracking.
- Manual ISO, shutter, focus, and white-balance controls are outside the consumer MVP.
┌─────────────────────────────────────────────┐
│  ● REC 00:42          [Tracking: LOCKED]    │  ← status bar
│                                             │
│              ┌──────────────┐               │
│              │  bounding    │               │
│              │  box on horse  │               │
│              └──────────────┘               │
│                                             │
│  ◄◄◄                              ►►►      │  ← guidance arrows (conditional)
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │  mini-map: full sensor + crop rect  │   │  ← optional inset
│  └─────────────────────────────────────┘   │
│                                             │
│         [ ⚙ Settings ]    [ ● Record ]     │
└─────────────────────────────────────────────┘
```

### Tracking Status Indicators

| State | Bounding box | Status label | Haptic |
|-------|-------------|--------------|--------|
| `idle` | None; center crosshair | "Tap horse to track" | — |
| `searching` | Pulsing yellow brackets | "Searching…" | — |
| `locked` | Solid green box | "Locked" | Success |
| `tracking` | Green box + confidence ring | "Tracking" | — |
| `lost` | Red dashed box | "Target lost — pan wide or refocus" | Warning |

### Confidence Ring

Circular progress ring around the bounding box, filled by tracking confidence (0–100%). Depletes as confidence drops — early warning before `lost` state.

### Mini-Map (optional, settings toggle)

Small inset showing the full 4K field of view with a rectangle indicating the current crop window. Helps the operator understand remaining headroom.

### Onboarding (first launch)

1. Grant camera permission.
2. Explain manual recording, automatic tracking, tap/refocus override, and arrows as camera pan guidance.
3. Start with the `Training Review` preset at 1080p/60 when validated and available, otherwise 1080p/30.

---

## 13. Settings Specification

### Settings UI Structure

Settings are grouped behind user-facing presets first. `Training Review` applies landscape 16:9, wide environmental framing, dynamic zoom, motion lead, automatic camera controls, 1080p, and preferred 60 fps. Advanced numeric controls remain available but are not required for normal operation.

```
Settings
├── Tracking
│   ├── Acquisition mode (Auto / Tap / Auto+Refocus)
│   ├── Re-detection interval (seconds)
│   ├── Lost-track timeout (seconds)
│   ├── Confidence threshold
│   ├── Smoothing strength
│   ├── Identity retention
│   └── Refocus behavior
├── Framing
│   ├── Output aspect ratio
│   ├── Crop zoom level
│   ├── Lock dynamic zoom
│   ├── Lead factor
│   └── Show mini-map
├── Camera
│   ├── Output resolution (1080p tracked / 4K full-frame)
│   ├── Frame rate (30 / 60; experimental 100 / 120)
│   ├── Lens (Main; experimental Ultra Wide)
│   └── Stabilization mode
├── Guidance
│   ├── Enable arrows
│   ├── Dead zone size
│   ├── Lookahead time
│   └── Haptic feedback
├── Recording
│   ├── Mode (Tracked only / Full only / Full + Tracked)
│   ├── Include overlay in recording
│   ├── Preserve full 4K source
│   ├── Export crop metadata
│   ├── Save destination (App / Photos / Both)
│   └── Codec (HEVC / ProRes if external)
└── Advanced
    ├── Detection model (Standard / Equestrian)
    ├── Processing resolution
    ├── Show debug HUD (fps, inference ms, thermal)
    └── Reset to defaults
```

### Default Values

| Setting | Default |
|---------|---------|
| Preset | Training Review |
| Acquisition mode | Auto + Refocus |
| Re-detection interval | 0.50 s |
| Lost-track timeout | 0.33 s |
| Confidence threshold | 0.50 |
| Smoothing strength | Medium (0.5) |
| Aspect ratio | 16:9 |
| Crop zoom | 1.0× (max crop from output res) |
| Lead factor | 0.10 s |
| Output resolution | 1080p |
| Frame rate | 60 fps preferred; automatic fallback to 30 fps |
| Lens | Main wide |
| Stabilization | Best supported (prefer Cinematic Extended) |
| Guidance | Enabled |
| Dead zone | 8% |
| Recording mode | Tracked only |
| Overlay in recording | Off |
| Dynamic zoom | On |
| Preserve full 4K source | Off |
| Export crop metadata | Off |
| Save destination | App |

---

## 14. Recording & Export

### Recording Modes

| Mode | Files produced | Storage impact |
|------|----------------|----------------|
| **Tracked only** | Single cropped HEVC `.mov` | Lowest |
| **Full only** | Single full-frame 4K HEVC `.mov`; tracking affects UI only | Medium |
| **Full + Tracked** | Full 4K + cropped HEVC | High |
| **Full + Tracked + sidecar** | Full 4K + cropped + JSON crop metadata per frame | Highest; enables post re-crop |

The MVP ships `Tracked only` and `Full only`. `Full + Tracked` is gated on sustained dual-encode profiling and may move to v1.1. The sidecar variant is v1.1+.

`Preserve full 4K source` maps to `Full + Tracked`. Show the setting only when that exact device/configuration is app-validated; otherwise display it disabled with a performance explanation. `Export crop metadata` is independently toggleable and defaults off.

### Writer Timing and Failure Policy

- Start the asset-writer session at the first accepted video PTS.
- Retimestamp neither video nor audio during normal capture; preserve monotonic capture timestamps.
- Queue early audio until the first video PTS, then drop audio samples that precede the session start.
- If the video writer input is not ready, count and drop that output frame; never block the capture callback.
- Finish recording only after video, audio, and metadata producers have stopped appending.
- Write to a unique temporary URL and atomically move the completed file to its final location.
- Surface writer status and the underlying error in diagnostics; never report success solely because `finishWriting` returned.

### Encoding

| Setting | Value |
|---------|-------|
| Codec | HEVC (H.265) default |
| Color | SDR default; HDR is enabled only after color metadata and tone-mapping behavior are verified through the Metal and `AVAssetWriter` pipeline |
| Audio | AAC-LC, 48 kHz |
| Container | QuickTime `.mov` |

### File Naming

```
TrackerCam_YYYYMMDD_HHMMSS_[mode]_[resolution].mov
```

### Save Destination

- User-selectable destination: app library, Photos, or both. Record to one temporary app-owned file, then perform the configured copies after finalization.
- Prompt for Photo Library permission on first save.
- Check estimated storage before recording and continuously monitor available capacity.
- When remaining capacity crosses the critical threshold, show a blocking five-second countdown, stop accepting new video frames at expiry, finalize the file, and report where it was saved.
- If safe finalization requires stopping sooner than five seconds, file integrity takes priority over completing the countdown.

### Interruption Policy

- Recording is foreground-only.
- For transient interruptions that do not revoke camera access, keep the writer active and continue recording.
- If iOS suspends camera delivery, preserve the current file. Resume into the same file only when timestamps and writer state remain valid.
- Otherwise finalize the current segment and automatically begin a continuation segment after capture resumes, provided the app is foreground and the user has not stopped recording.
- Group continuation segments under one recording session in the app library.
- Calls, app backgrounding, media-services resets, audio-route changes, and writer failures must never discard an already valid segment.

### Physical Controls

- Camera Control and either volume button can start/stop recording when the app is foreground and the camera view is active.
- Capture volume-button and hardware shutter presses with `AVCaptureEventInteraction` (iOS 17.2+) rather than intercepting raw volume key events. The hardware **Camera Control** (iPhone 16 Pro / 17 Pro) is a separate API: feature-detect with `captureSession.supportsControls`, then register controls via `session.addControl(...)` using `AVCaptureControl` subclasses (and `AVCaptureSessionControlsDelegate` for activation callbacks). Treat Camera Control as optional/enhancing — do not gate recording on it. (Launching the app *from* a locked device via Camera Control would additionally require a Lock Screen capture extension; that is out of scope for v1 — in-app start/stop only requires the app foregrounded and the camera view active.)
- Button handling must debounce repeated events and provide visible/haptic confirmation.
- On-screen recording remains the primary control and is independent of tracking lock.
- Apple Watch remote control is post-v1.

### Sidecar Format (optional, Phase 5+)

```json
{
  "schemaVersion": 2,
  "recordingID": "018f...",
  "timebase": 600,
  "sourceResolution": { "width": 3840, "height": 2160 },
  "outputResolution": { "width": 1920, "height": 1080 },
  "orientation": "landscapeRight",
  "mirrored": false,
  "frames": [
    {
      "sequence": 42,
      "pts": { "value": 1260, "timescale": 600 },
      "crop": { "x": 812.5, "y": 456.8, "w": 2133.3, "h": 1200.0 },
      "subject": { "x": 1402.0, "y": 721.0, "w": 628.0, "h": 540.0 },
      "confidence": 0.87,
      "state": "tracking",
      "predicted": true
    },
    ...
  ]
}
```

Use integer `CMTime` components rather than floating-point seconds. For long recordings, stream newline-delimited frame records to a temporary file or encode timed metadata into the movie; do not retain all frame metadata in memory.

---

## 15. Performance & Thermal Budget

### Latency Budget (iPhone 17 Pro, 30 fps target)

| Stage | Budget | Notes |
|-------|--------|-------|
| Frame interval | 33 ms | Throughput deadline, not processing work |
| Downscale to 720p | 2 ms | vImage or Metal |
| Vision track | 5 ms | Every frame |
| Core ML detect | 16 ms | Every 15th frame (amortized ~1 ms) |
| Kalman update | < 1 ms | CPU |
| 4K Metal crop | 8 ms | GPU |
| Overlay render | 2 ms | SwiftUI / Metal |
| Encode submission | 2 ms | Excludes asynchronous hardware encode |
| **Steady-state processing target** | **≤ 20 ms p95** | Track frames; excludes camera exposure and display scanout |
| **Detection-frame processing target** | **≤ 35 ms p95** | May complete asynchronously without blocking capture |
| **Capture-to-preview target** | **≤ 100 ms p95** | Measured end to end |

The frame interval is not added to processing work. CPU, Neural Engine, GPU, encode, and display stages may overlap, so performance claims must report both stage timings and end-to-end latency. Add separate measured budgets for 60 and 120 fps presets after the Phase 0/1 feasibility work.

### Benchmark Protocol

For every published latency or thermal claim, record: device and storage capacity, iOS build, active camera format, stabilization mode, model and input dimensions, model precision, Core ML compute-unit setting, output mode, ambient conditions, initial/final thermal state, test duration, and p50/p95 timings. Treat values in this draft as targets until reproduced on physical devices for at least 10 minutes.

For iPhone 17 Pro, benchmark at minimum:

- 4K30 and 4K60 on Fusion Main with each app-supported stabilization mode.
- 4K100/120 feasibility with ML at 30 fps and 60 fps effective cadence.
- 1080p landscape, portrait, and square tracked outputs.
- 256GB-class storage behavior near low-space thresholds.
- Outdoor sunlight and indoor-arena conditions, including ambient temperature.
- Battery-only and USB-C-powered operation; charging may increase heat and must not be assumed to improve sustained performance.
- Pro versus Pro Max as separate thermal/battery profiles even when camera and chip capabilities match.

### Thermal Degradation Ladder

Monitor `ProcessInfo.thermalState` and apply progressively:

| Thermal state | Action |
|---------------|--------|
| `.nominal` | Full quality |
| `.fair` | Increase detection interval from 0.5 s to 1.0 s |
| `.serious` | Drop processing to 720p; cap output at 1080p/30; disable mini-map |
| `.critical` | Show an immediate thermal-stop warning, stop accepting frames, finalize the recording, and disable capture until the device leaves critical state |

### Memory

- Pool `CVPixelBuffer`s — avoid per-frame allocation.
- Limit in-flight buffers to 3 per branch.
- Model loaded once at app launch; warm up with dummy inference.

### Battery

- Screen-on outdoor use is already demanding.
- The acceptance target is no more than 20 percentage points of battery drain during a 30-minute 1080p tracked recording on iPhone 17 Pro under the standard field-test conditions.
- Show a warning when battery level falls below 20%.
- Prefer reducing ML cadence and preview refresh before reducing recording integrity.

---

## 16. Project Structure

```
TrackerCam/
├── TrackerCam.xcodeproj
├── TrackerCam/
│   ├── App/
│   │   ├── TrackerCamApp.swift
│   │   └── AppDelegate.swift (if needed)
│   ├── Features/
│   │   ├── Camera/
│   │   │   ├── CameraView.swift
│   │   │   ├── CameraViewModel.swift
│   │   │   └── Components/          (RecordButton, StatusBar, MiniMap)
│   │   ├── Tracking/
│   │   │   ├── TrackingEngine.swift
│   │   │   ├── TrackingState.swift
│   │   │   ├── DetectionService.swift
│   │   │   └── KalmanFilter2D.swift
│   │   ├── Reframe/
│   │   │   ├── ReframePipeline.swift
│   │   │   └── Shaders/CropShader.metal
│   │   ├── Guidance/
│   │   │   ├── GuidanceEngine.swift
│   │   │   └── ArrowOverlayView.swift
│   │   ├── Recording/
│   │   │   └── RecordingService.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       └── SettingsStore.swift
│   ├── Services/
│   │   ├── CameraService.swift
│   │   ├── FrameRouter.swift
│   │   └── ThermalManager.swift
│   ├── Models/
│   │   ├── SportProfile.swift
│   │   └── RecordingConfiguration.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Models/
│           ├── YOLO26n_horse.mlpackage
│           └── YOLO26n_equestrian.mlpackage  (future)
├── TrackerCamTests/
│   ├── TrackingEngineTests.swift
│   ├── KalmanFilterTests.swift
│   └── CropMathTests.swift
└── PLAN.md
```

---

## 17. Implementation Phases

### Phase 0 — Project Setup (Week 1)

| Task | Deliverable |
|------|-------------|
| Create Xcode project (iOS 26+, Swift 6, SwiftUI) | Empty app with bundle ID |
| Configure camera/mic entitlements | Permissions plist strings |
| Add folder structure per §16 | Skeleton modules |
| Integrate AVCam sample camera preview | Live camera feed, no ML |
| Run capture feasibility matrix | Verified formats, fps, stabilization, delivered dimensions, GPU downscale, and buffer topology on target devices |

**Milestone:** App launches to a live 4K camera preview and the MVP capture topology is validated on physical hardware.

#### Phase 0 Spike Checklist (hardware-gated; close before Phase 1 commitments)

Each item is a yes/no answer recorded against device model, iOS build, and active format. These resolve the open unknowns the rest of the plan depends on:

1. **Format enumeration** — Print every `AVCaptureDevice.Format` on the Fusion Main camera. Record delivered dimensions, pixel format subtype (`'420v'`/`'420f'`/`'x422'`), supported frame-rate ranges, FOV, max zoom, and color-space support. Confirm a true 4K (3840×2160) format at 30 and 60 fps exists and is selectable via `.inputPriority`.
2. **SDR path** — Confirm an SDR-deliverable configuration: either an SDR-native format or `activeColorSpace = .sRGB`/`.P3_D65` with `automaticallyAdjustsVideoHDREnabled = false`. Record whether the chosen 60 fps format forces HDR (§9 Color Space).
3. **Stabilization matrix** — For each candidate format, query `isVideoStabilizationModeSupported` per mode and record the effective mode after configuration (`.cinematicExtended` → `.cinematic` → `.standard` → `.off`).
4. **Tracking API resolution** — Determine whether `TrackObjectRequest` in the new Swift API tracks across frames via a reusable request/handler or needs `VNSequenceRequestHandler`. Implement a 10-second tracked-bbox smoke test either way (§8 API note).
5. **GPU downscale + fan-out** — Measure cost of one 4K→720p Metal downscale plus retaining the 4K texture for reframe, at 30 and 60 fps, without dropping capture frames. Confirm `< 8 ms` 4K crop target is plausible on A19 Pro.
6. **Buffer ownership under Swift 6** — Verify the `CMSampleBuffer`/`CVPixelBuffer` hand-off across capture/processing/GPU queues compiles and runs under strict concurrency with the chosen transfer wrapper (§6).
7. **Sustained capture** — 5-minute 4K60 run logging capture-drop, analysis-drop, and thermal-state counters; confirm no runaway drops or premature thermal throttle in nominal conditions.

If any of items 1–3 fail on a given preset, that preset is removed from the supported set before any UI exposes it (§5 capability-driven settings).

---

### Phase 1 — Camera & Settings Shell (Weeks 1–2)

| Task | Deliverable |
|------|-------------|
| `CameraService` with format/fps selection | 4K @ 30/60 selectable |
| Settings UI (camera section) | Resolution, fps, lens, stabilization |
| Hardware stabilization enabled | Best supported mode selected and reported |
| Record button (full-frame, no crop) | Basic HEVC recording |

**Milestone:** Record full 4K video with configurable settings.

---

### Phase 2 — Tap-to-Track (Weeks 3–4)

| Task | Deliverable |
|------|-------------|
| Processing branch at 720p | `FrameRouter` |
| Tap gesture → seed bbox | User-initiated tracking |
| Vision `TrackObjectRequest` integration | Frame-to-frame bbox |
| Tracking state machine | idle/searching/locked/tracking/lost |
| Bounding box overlay | Color-coded per state |
| Lock/lost haptics | Tactile feedback |

**Milestone:** Tap a subject; box follows it; state feedback works.

---

### Phase 3 — Horse Auto-Detect (Weeks 5–6)

| Task | Deliverable |
|------|-------------|
| Export YOLO26n to Core ML (COCO horse class) | `.mlpackage` in bundle |
| `DetectionService` with Core ML Vision request (`CoreMLRequest` on the new Swift API, or `VNCoreMLRequest` if tracking forces the established API — see §8) | Bounding boxes + confidence |
| Hybrid detect + track pipeline | Re-detection on timestamp-based cadence |
| Re-acquisition on loss | Auto or tap fallback |
| Settings: confidence, detect interval | Tracking settings section |

**Milestone:** App auto-detects and tracks a horse without tap.

---

### Phase 4 — Reframe Pipeline (Weeks 7–9)

| Task | Deliverable |
|------|-------------|
| `KalmanFilter2D` on subject center | Smoothed position + velocity |
| Metal crop shader | GPU reframing on 4K buffer |
| Cropped live preview | Subject-centered view |
| `RecordingService` with cropped output | Tracked HEVC recording |
| Settings: aspect ratio, zoom, smoothing, lead | Framing settings section |

**Milestone:** Preview and recording show subject-centered, smoothed output.

---

### Phase 5 — Guidance & Polish (Weeks 10–11)

| Task | Deliverable |
|------|-------------|
| `GuidanceEngine` + arrow overlay | Directional operator hints |
| Confidence ring UI | Early warning visualization |
| Mini-map inset (optional) | Full-sensor context |
| `ThermalManager` degradation | Adaptive quality |
| Debug HUD (fps, inference ms) | Advanced settings |
| Onboarding flow | First-launch tutorial |

**Milestone:** Full feature set for field testing.

---

### Phase 6 — Field Test & Model Improvement (Weeks 12–14)

| Task | Deliverable |
|------|-------------|
| Real-world testing at arena / field | Bug list, performance log |
| Collect failure frames for training | Labeled dataset |
| Fine-tune equestrian YOLO model | Improved detector |
| iPhone 16 Pro compatibility pass | Device matrix test |
| TestFlight beta | External testers |

**Milestone:** Beta-ready build with equestrian-tuned model.

---

### Timeline Summary

| Phase | Duration | Cumulative |
|-------|----------|------------|
| 0 — Setup | 1 week | Week 1 |
| 1 — Camera | 1–2 weeks | Week 2 |
| 2 — Tap-to-track | 2 weeks | Week 4 |
| 3 — Auto-detect | 2 weeks | Week 6 |
| 4 — Reframe | 3 weeks | Week 9 |
| 5 — Guidance | 2 weeks | Week 11 |
| 6 — Field test | 3 weeks | Week 14 |

**Estimated MVP:** ~11 weeks. **Beta-quality:** ~14 weeks.

> **Scheduling assumption:** This timeline assumes one experienced iOS engineer working full-time, with the iPhone 17 Pro hardware and representative footage already on hand (§4). It is aggressive for the scope — a custom Metal reframe pipeline, stateful Vision tracking, the thermal ladder, and dual-encode profiling are each multi-day efforts with hardware-dependent unknowns. Treat Phase 4 (Reframe, 3 weeks) and Phase 0's feasibility matrix as the most likely to slip. If staffing is part-time or split, scale the calendar accordingly and keep D22 (schedule) open until Phase 0 results are in.

---

## 18. Testing Strategy

### Unit Tests

| Area | Tests |
|------|-------|
| `KalmanFilter2D` | Predict/update correctness, noise tuning |
| Crop math | Clamping, aspect ratios, dynamic zoom bounds, hysteresis, edge headroom, rotation |
| `CropController` | Rate limits, prediction, lost-state behavior, reacquisition blending, scale smoothing |
| Coordinate conversion | Vision normalized ↔ pixel coords |
| Timestamp alignment | Late observations, stale-result rejection, session-generation invalidation |
| State machine | Transitions, timeout thresholds |
| Settings | Defaults, persistence, validation |

### Integration Tests

| Scenario | Method |
|----------|--------|
| Detect → track → reframe pipeline | Pre-recorded video file fed through pipeline |
| Recording output resolution | Verify written file dimensions |
| Orientation changes | Rotate during preview; verify recording orientation remains locked |
| Stabilization coordinate alignment | Verify bbox and crop alignment in every supported effective mode |
| Interruption recovery | Calls/backgrounding/media-services reset produce a valid file or explicit failure |
| Preview/record parity | Compare crop decision and sampled pixels for the same PTS |
| Writer backpressure | Inject delayed writer readiness and verify bounded dropping without capture blockage |

### Device Testing Matrix

| Device | iOS | Priority |
|--------|-----|----------|
| iPhone 17 Pro | 26 | P0; full 4K30/60 and 100/120 feasibility matrix |
| iPhone 17 Pro Max | 26 | P1; separate thermal and battery profile |
| iPhone 16 Pro | 26 | P2; best-effort compatibility |
| iPhone 16 Pro Max | 26 | P2; best-effort compatibility |

### Field Test Scenarios

| Scenario | Success criteria |
|----------|------------------|
| Walk trot in arena | Track maintained > 90% of 2-min clip |
| Canter across field | Loss recovery within 2 s |
| Single horse/rider | Compound envelope contains the whole horse and rider plus environmental padding |
| Multiple horses (robustness only) | Does not switch from the reserved identity without refocus |
| Low light (indoor arena) | Graceful degradation, no crash |
| 5-min continuous record | Mandatory minimum; no crash, corruption, or thermal stop |
| 30-min continuous record | Engineering endurance target; degradation activates without corrupting output |
| Portrait + landscape | Correct crop orientation |
| Framing quality | Subject center remains within 15% of intended composition center for ≥ 90% of tracked frames |
| Output stability | No visible one-frame crop jumps; p95 crop-center acceleration stays below a field-tested threshold |
| Dynamic zoom | Padded subject remains inside the safe frame for ≥ 98% of confidently tracked frames; no more than one zoom-direction reversal per second |
| Encoding integrity | < 0.1% dropped output frames; audio/video sync error remains < 50 ms |
| Battery endurance | Standard 30-minute iPhone 17 Pro test consumes no more than 20 percentage points |
| Tap selection | Intended subject selected on first tap in ≥ 95% of labeled multi-horse test cases |

### Release Acceptance Gates

- No crash or corrupt output across a 5-minute continuous 1080p/60 tracked recording on iPhone 17 Pro, with automatic 30 fps fallback where required.
- Complete a 30-minute engineering endurance run without corrupt output before App Store submission.
- Capture-to-preview latency meets the p95 target in nominal thermal state.
- Tracking, framing, dropped-frame, and A/V sync criteria above pass on the fixed field-test corpus.
- Primary launch metric: the compound target remains correctly tracked for at least 90% of visible, labeled frames across the launch regression corpus.
- Every settings combination exposed in production is validated as supported; unsupported combinations are disabled before session reconfiguration.
- Ground-operator safety guidance is present in onboarding.

### Telemetry and Privacy

- Crash reports and aggregate performance telemetry are opt-in.
- Telemetry may include device model, OS/app version, effective camera configuration, thermal state, stage timings, dropped-frame counters, tracking-state durations, and anonymized error codes.
- Never upload video, audio, pixel buffers, model inputs, bounding-box snapshots, filenames, or precise location through telemetry.
- Any future footage-sharing workflow requires a separate explicit action, a clear destination, and revocable consent.
- The app remains fully functional with telemetry disabled.

### Performance Profiling

- Xcode Instruments: Time Profiler, Metal System Trace, Allocations.
- In-app debug HUD: capture fps, inference ms, crop ms, thermal state.
- Compare against budgets in §15.

---

## 19. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| COCO horse detector unreliable | High | High | Fine-tuned equestrian model in Phase 6; tap-to-track fallback |
| Tracking loss at speed | High | High | Wider default crop; predictive lead; fast re-detect |
| 4K + ML thermal throttling | High | Medium | Thermal ladder; separate capture/process resolutions |
| Preview/recording crop mismatch | Medium | High | Single crop rect source of truth; same Metal shader |
| Stabilization shifts tracking coordinates | Medium | High | Derive ML and crop from the same delivered buffer; device-format alignment tests |
| Unsafe interpretation of guidance | Medium | High | Describe arrows as camera pan/aim correction; ground-operator safety guidance; never instruct physical movement |
| Dual encoding drops frames or overheats | High | Medium | Ship single-output modes first; gate Full + Tracked on sustained profiling |
| Dynamic zoom pumps on noisy boxes | High | Medium | Separate scale filter, asymmetric rates, hysteresis, bbox outlier rejection |
| Late ML results move the crop backward | Medium | High | PTS-aligned prediction, stale-result deadline, session generation IDs |
| Motion blur at low shutter | Medium | Medium | Prefer 60 fps; expose exposure bias in advanced settings |
| Multi-horse confusion | Medium | Medium | Tap-to-select; prefer largest/nearest to center |
| App Store review (camera app) | Low | Medium | Clear permission strings; no background recording |
| ProRes / external storage complexity | Low | Low | Defer to post-v1; HEVC only for MVP |

---

## 20. Future Expansion

### Sport Profiles (v2)

```swift
enum SportProfile: String, CaseIterable {
    case equestrian
    case cycling
    case running
    case skiing
    case dogAgility
}
```

Each profile bundles: detector model (or class filter), default crop zoom, lead factor, aspect ratio default.

### Features (v2+)

| Feature | Description |
|---------|-------------|
| Multi-subject tracking | Track horse + rider as compound target |
| Apple Watch companion | Haptic-only guidance without looking at phone |
| Live Activity | Recording duration + tracking status on lock screen |
| iPad support | Larger preview for ground filming |
| External lens support | Moment / Sandmarc wide lenses |
| Post-export re-crop | Import full-frame source video + sidecar JSON |

### Monetization Options (decision deferred)

- Paid app
- Free with watermark; IAP to remove
- Free base; sport model packs as IAP

**Current direction:** free download with an optional one-time in-app upgrade. Subscription is not assumed. Decide the upgrade feature boundary before external TestFlight.

---

## 21. Apple Documentation References

### Camera & Video

- [AVCam: Building a camera app](https://developer.apple.com/documentation/AVFoundation/avcam-building-a-camera-app)
- [AVCaptureDevice.Format](https://developer.apple.com/documentation/avfoundation/avcapturedevice/format)
- [AVCaptureConnection.preferredVideoStabilizationMode](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/preferredvideostabilizationmode)
- [AVCaptureVideoStabilizationMode.previewOptimized](https://developer.apple.com/documentation/avfoundation/avcapturevideostabilizationmode/previewoptimized)
- [Enhancing your camera experience with capture controls (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/253/) — `AVCaptureControl`, `supportsControls`, `addControl`
- [AVCaptureEventInteraction](https://developer.apple.com/documentation/avkit/avcaptureeventinteraction) — hardware shutter / volume-button capture events
- [AVCaptureDevice.RotationCoordinator](https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator)

### Vision & ML

- [Vision framework overview](https://developer.apple.com/documentation/vision)
- [TrackObjectRequest](https://developer.apple.com/documentation/vision/trackobjectrequest)
- [Tracking multiple objects in video](https://developer.apple.com/documentation/Vision/tracking-multiple-objects-or-rectangles-in-video)
- [Recognizing objects in live capture](https://developer.apple.com/documentation/Vision/recognizing-objects-in-live-capture)
- [RecognizeAnimalsRequest](https://developer.apple.com/documentation/vision/recognizeanimalsrequest) (cats/dogs only — not for horses)
- [WWDC24 — Vision Swift enhancements](https://developer.apple.com/videos/play/wwdc2024/10163/)
- [WWDC23 — Detect animal poses](https://developer.apple.com/videos/play/wwdc2023/10045/)
- [WWDC24 — Core ML enhancements](https://developer.apple.com/videos/play/wwdc2024/10161/)
- [Apple Machine Learning models](https://developer.apple.com/machine-learning/models/)

### Image Processing

- [Core Image](https://developer.apple.com/documentation/coreimage)
- [Metal](https://developer.apple.com/documentation/metal)

### Hardware Reference

- [iPhone 17 Pro Technical Specifications](https://www.apple.com/iphone-17-pro/specs/)
- [iPhone 16 Pro — 4K 120fps Dolby Vision](https://support.apple.com/en-la/121032)

### Third-Party References

- [Ultralytics Core ML export](https://docs.ultralytics.com/integrations/coreml/)
- [Ultralytics YOLO26 model docs](https://docs.ultralytics.com/models/yolo26/) — `yolo26n` end-to-end NMS-free; Core ML export; ~43% faster on CPU vs prior nano
- [Ultralytics YOLO iOS app (performance benchmarks)](https://github.com/ultralytics/yolo-ios-app/blob/main/docs/performance.md)
- [MetalPetal GPU image framework](https://github.com/MetalPetal/MetalPetal)

---

## 22. Open Decisions

| # | Decision | Options | Recommendation |
|---|----------|---------|----------------|
| D1 | MVP tracked recording resolution | 1080p cropped vs upscaled "4K" | **1080p native crop**; do not market upscaled output as native 4K |
| D2 | Fine-tuned model in v1 or v1.1 | Ship with COCO only vs wait | **Not required for launch**; ship COCO if field gates pass, fine-tune later |
| D3 | MetalPetal vs raw Metal | Library vs custom shader | **Raw Metal** for MVP; evaluate MetalPetal if complexity grows |
| D4 | Sidecar metadata in v1 | Yes / No | **Optional toggle**; ship only if streaming metadata implementation is stable |
| D5 | Portrait mode support in v1 | Yes / No | **Secondary** — landscape ships first; include portrait if it does not delay core quality |
| D6 | App name / bundle ID | TBD | `com.<org>.trackercam` |
| D7 | Minimum iOS | 18 vs 26 | **Resolved: iOS 26** |
| D8 | Monetization | Paid / freemium / free | **Free download + optional one-time IAP direction**; feature boundary TBD |
| D9 | Simultaneous recording | Single output vs Full + Tracked | **Single output for MVP**; enable dual output only after 30-minute device profiling passes |
| D10 | HDR tracked output | SDR only vs HDR passthrough | **SDR default**; enable HDR only after metadata, tone mapping, and export validation |
| D11 | Dynamic digital upscale | Forbid vs allow limited upscale | **Forbid for MVP**; minimum crop equals output dimensions |
| D12 | Default composition | Center subject vs motion-aware lead | **Motion-aware lead** with conservative 8% horizontal offset |
| D13 | Metadata transport | JSON sidecar vs timed movie metadata | **NDJSON sidecar first** for diagnostics; evaluate timed metadata for v1.1 |
| D14 | iPhone 17 Pro Ultra Wide mode | Main only vs optional Ultra Wide | **Main only for MVP**; validate Ultra Wide as a post-MVP recovery mode |
| D15 | 100/120 fps exposure | Production setting vs experimental flag | **Experimental** until sustained capture, stabilization, and thermal gates pass |
| D16 | Motion-sensor fusion | Camera-only tracking vs gyro-assisted crop prediction | **Instrument gyro in v1**, but enable correction only after offline correlation proves benefit |
| D17 | Rear dual-camera recovery | Main only vs Main + Ultra Wide analysis | **Resolved: defer; single rear Main camera for v1** |
| D18 | Wrong-target tradeoff | Stay lost vs risk switching horses | **Resolved for MVP: assume one relevant target** |
| D19 | Critical thermal behavior | Preserve recording without tracking vs stop recording | **Resolved: stop and finalize recording** |
| D20 | Privacy and telemetry | Fully offline/no telemetry vs opt-in diagnostics | **Resolved: opt-in non-media diagnostics** |
| D21 | Launch success metric | Tracking retention vs usable training clips vs adoption | **Resolved: tracking retention** |
| D22 | Schedule | First usable build and App Store target dates | TBD |
| D23 | Primary landscape grip | Record button near left hand vs right hand | **Resolved: right hand** |
| D24 | Test assets | Existing footage/devices vs collection required | **Resolved: iPhone 17 Pro and substantial footage available** |

---

*This document is the source of truth for TrackerCam v1 planning. Update version and date when revising.*
