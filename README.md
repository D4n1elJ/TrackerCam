# TrackerCam

iOS app that detects, tracks, and auto-reframes video of a fast-moving subject (initially horses)
entirely on-device. See [PLAN.md](PLAN.md) (v1.0, locked) for the full product & technical spec.

## Repository layout

```
trackercam/
├── PLAN.md                 # Source-of-truth product & technical plan (locked v1.0)
├── project.yml             # XcodeGen spec for the iOS app target
├── TrackerCamCore/         # Framework-free core logic (SwiftPM) — fully unit-tested
│   ├── Sources/TrackerCamCore/
│   │   ├── Geometry.swift             # TCPoint/TCSize/TCRect (no CoreGraphics dep)
│   │   ├── VisionGeometry.swift       # Vision normalized ↔ source-pixel conversion (§10)
│   │   ├── KalmanFilter2D.swift       # Constant-velocity smoother (§10)
│   │   ├── CropMath.swift             # Compound box, zoom, clamp, composition, headroom (§10)
│   │   ├── TrackingStateMachine.swift # idle→searching→locked→tracking→lost (§8)
│   │   └── TrackerSettings.swift      # Settings model + defaults + clamping (§13)
│   ├── LocalTests/         # swiftc-runnable test harness (works without Xcode/XCTest)
│   └── Scripts/verify.sh   # Compile + run the core test suite locally
└── TrackerCam/             # iOS app (UI + AVFoundation + Vision + Metal)
    ├── App/                # Entry point, Info.plist, entitlements
    ├── Services/           # CameraService, FrameRouter, ThermalManager
    ├── Features/
    │   ├── Camera/         # CameraView, CameraViewModel, MetalPreviewView, overlays
    │   ├── Tracking/       # TrackingEngine (Vision), DetectionService (Core ML)
    │   ├── Reframe/        # ReframePipeline + CropShader.metal
    │   ├── Recording/      # RecordingService (AVAssetWriter)
    │   ├── Guidance/       # GuidanceEngine
    │   └── Settings/       # SettingsStore, SettingsView
    └── Resources/          # Assets, (drop YOLO26n_horse.mlpackage here for Phase 3)
```

## Architecture note: why a separate core package

`TrackerCamCore` contains **no** AVFoundation / Vision / Metal / CoreGraphics code. This keeps the
hard, bug-prone math (Kalman, crop geometry, coordinate flips, the state machine) portable and
unit-testable on any platform — it is verified continuously without a device or simulator. The app
bridges the core's `Double`-based geometry to `CGRect` at one boundary
(`TrackerCam/Support/Geometry+CoreGraphics.swift`).

## Build & test

### Core logic (no Xcode required)

```bash
cd TrackerCamCore
./Scripts/verify.sh          # compiles sources + tests with swiftc, runs them
# In a healthy full toolchain you can instead use: swift test
```

### iOS app (requires full Xcode)

```bash
brew install xcodegen        # no sudo
cd trackercam
xcodegen generate            # produces TrackerCam.xcodeproj from project.yml
open TrackerCam.xcodeproj     # build & run on an iPhone 17 Pro (iOS 26)
```

To build from the command line without changing the global `xcode-select` (no sudo):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project TrackerCam.xcodeproj -scheme TrackerCam \
  -destination 'generic/platform=iOS' build
```

## Status

- **Core logic (`TrackerCamCore`):** 11 modules, **167 checks passing** (`Scripts/verify.sh`) —
  VisionGeometry, KalmanFilter2D, CropMath, CropController (asymmetric zoom + hysteresis),
  CropPlanner (lost ladder), TrackingStateMachine, GuidanceEngine, TrackerSettings,
  InterruptionPolicy, StoragePolicy.
- **iOS app:** **builds clean (0 errors) and installs + launches in the iPhone 17 Pro simulator.**
  Implemented: capture pipeline, Vision tracking + Core ML detection hook, Metal reframe
  (preview+record from one pass), rate-limited/smoothed crop, recording + finalization
  (app library / Photos) + recordings browser, guidance arrows, mini-map, confidence ring,
  debug HUD, onboarding, interruption/continuation handling, low-storage countdown, battery
  warning, hardware capture-button control.
- **Requires the physical iPhone 17 Pro (PLAN.md §17 Phase 0) — cannot be validated in the
  simulator:** the live 4K capture→track→reframe→encode pipeline, exposure/metering, format/
  stabilization/SDR validation, physical-button behavior, thermal-under-load.
- **Needs an external asset:** drop `YOLO26n_horse.mlpackage` into `TrackerCam/Resources/Models/`
  to activate horse detection (the detector returns nil until then; tap-to-track works regardless).
- **Deferred (post-v1 per plan):** fine-tuned equestrian model, true 4K "Full only" / dual-encode,
  sidecar metadata, identity continuity, accel/jerk crop limits (field-tuned).

## Device validation gates before trusting any capture mode

Per PLAN.md §5/§9/§17, a capture mode is only "supported" after the exact format + pixel format +
stabilization + color space + output combination passes on-device. The app reads back and displays
the *effective* configuration rather than assuming the requested one.
```
