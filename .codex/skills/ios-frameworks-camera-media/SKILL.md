---
name: ios-frameworks-camera-media
description: Use when implementing or debugging camera capture, AVCaptureSession, PhotosPicker, PHPicker, limited library access, or HDR media handling.
---

# Camera & Media

Review and write camera capture and photo library code for correct session management, responsive UX, and privacy-forward photo access.

## Responsibility

**Owns:** AVCaptureSession setup and lifecycle, AVCapturePhotoOutput, AVCaptureMovieFileOutput, RotationCoordinator, zero-shutter-lag, responsive capture, deferred photo processing, readiness coordinator, session interruption handling, front camera mirroring, PhotosPicker, PHPickerViewController, limited library access, PHPhotoLibrary change observation, Transferable image loading, HDR preservation, saving to camera roll.

**Does NOT own:** AVAudioSession configuration (see audio skill), Core Image filters, Vision framework analysis, ARKit camera feeds, MapKit or Core Location.

## Core Principles

1. **PhotosPicker first, AVCaptureSession only when needed.** PhotosPicker requires zero permissions and covers most photo selection needs. Only reach for AVCaptureSession when you need a custom camera UI.
2. **All session work on a dedicated serial queue.** `startRunning()` blocks for 1-3 seconds. Calling it on main thread freezes the UI.
3. **Use RotationCoordinator, not deprecated videoOrientation.** RotationCoordinator tracks gravity automatically and handles edge cases (face-up, face-down) that manual tracking misses.
4. **Wrap configuration in begin/commit.** `beginConfiguration()`/`commitConfiguration()` makes changes atomic. Without it, the session can enter an invalid state between calls.
5. **Handle all five interruption reasons.** Phone calls, other apps using the camera, Split View, background, and thermal pressure. Unhandled interruptions look like frozen cameras.
6. **Never request library access for photo picking.** PHPicker and PhotosPicker handle privacy out-of-process. Requesting `.readWrite` when you only need picking is a privacy violation that App Store Review flags.
7. **Treat `.limited` as a valid authorization.** iOS 14+ users can grant access to a subset of their library. Treating `.limited` as denied breaks the feature for those users.

## Capture Approach Decision Tree

```
What does this feature need?

├── User picks existing photos/videos?
│   ├── SwiftUI --> PhotosPicker (no permission needed)
│   └── UIKit --> PHPickerViewController (no permission needed)
│
├── Simple photo/video with system camera UI?
│   └── UIImagePickerController (limited customization, no library permission)
│
├── Custom camera UI for photos?
│   └── AVCaptureSession + AVCapturePhotoOutput
│       └── Need instant feel? Enable responsive capture pipeline
│
├── Custom camera UI for video?
│   └── AVCaptureSession + AVCaptureMovieFileOutput
│       └── Audio? Add AVCaptureDeviceInput for microphone
│
├── Save to camera roll?
│   └── PHPhotoLibrary.requestAuthorization(for: .addOnly)
│       └── Minimal permission -- no reading, just writing
│
└── Build a gallery/browser of user's library?
    └── PHPhotoLibrary.requestAuthorization(for: .readWrite)
        └── Handle .limited with presentLimitedLibraryPicker
```

## Photo Permission Decision Tree

```
What level of photo library access?

├── PICKING ONLY (user selects photos for your app)
│   └── No permission needed -- use PhotosPicker or PHPicker
│
├── SAVING ONLY (writing captured/edited photos)
│   └── Request .addOnly
│       └── NSPhotoLibraryAddUsageDescription in Info.plist
│
├── BROWSING (custom gallery, album view)
│   └── Request .readWrite
│       ├── .authorized --> full access
│       ├── .limited --> user-selected subset
│       │   └── Offer presentLimitedLibraryPicker to expand
│       └── .denied --> show settings prompt
│
└── CAMERA ONLY (no library interaction)
    └── AVCaptureDevice.requestAccess(for: .video)
        └── NSCameraUsageDescription in Info.plist
```

## Red Flags

| Anti-Pattern | Problem | Fix Time |
|---|---|---|
| `startRunning()` on main thread | UI freezes 1-3 seconds | 5 min |
| Deprecated `videoOrientation` instead of RotationCoordinator | Broken rotation on face-up/down, more code to maintain | 30 min |
| No session interruption observers | Camera appears frozen on phone call or Split View | 30 min |
| Session config without `beginConfiguration()`/`commitConfiguration()` | Session enters invalid state mid-change | 5 min |
| Requesting `.readWrite` for photo picking | Privacy violation, App Store rejection risk | 5 min |
| Treating `.limited` as `.denied` | Feature broken for users who granted partial access | 10 min |
| Default `Image` Transferable (PNG only) | Fails silently on JPEG/HEIF photos | 15 min |
| `photoQualityPrioritization = .quality` for social features | 2+ second capture delay, users think camera is broken | 2 min |
| Creating new AVCaptureSession per capture | Expensive reinitialization, visible lag | 15 min |
| UIImagePickerController for photo selection | Deprecated, limited, worse privacy model | 10 min |
| Ignoring `preferredItemEncoding` | HDR data silently transcoded to SDR | 2 min |
| Not saving deferred proxy to PhotoKit promptly | App backgrounded before proxy saved, photo lost | 10 min |

## Pre-Ship Checklist

**Camera Capture:**
- [ ] All session work on dedicated serial queue, never main thread
- [ ] `NSCameraUsageDescription` in Info.plist
- [ ] `NSMicrophoneUsageDescription` if recording audio
- [ ] Session preset matches use case (`.photo` for photos, `.high` for video)
- [ ] Configuration changes wrapped in `beginConfiguration()`/`commitConfiguration()`
- [ ] RotationCoordinator set up for preview and capture
- [ ] `photoQualityPrioritization` set appropriately (`.speed` for social, `.balanced` general, `.quality` documents)
- [ ] Session interruption observers registered, UI feedback shown
- [ ] Camera switching updates RotationCoordinator and falls back on failure
- [ ] Denied permission handled with settings prompt or alternative flow
- [ ] Tested with incoming phone call and Split View on iPad

**Photo Library:**
- [ ] Using PhotosPicker/PHPicker for selection (no permission request)
- [ ] Custom Transferable handles JPEG/HEIF, not just PNG
- [ ] `preferredItemEncoding: .current` if HDR preservation matters
- [ ] `.limited` authorization handled (not treated as denied)
- [ ] `presentLimitedLibraryPicker` offered when `.limited`
- [ ] `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` in Info.plist if handling limited UI manually
- [ ] All image loading is async with error handling
- [ ] PHPhotoLibraryChangeObserver registered/unregistered if displaying library content
- [ ] `.addOnly` used when only saving (not reading) photos
- [ ] Info.plist keys present for requested access level

## References

- `references/capture-patterns.md` -- AVCaptureSession setup, RotationCoordinator, responsive capture pipeline, deferred processing, session interruptions, camera switching, video recording
- `references/photo-library-patterns.md` -- PhotosPicker, PHPicker, limited library access, HDR preservation, custom Transferable, change observation, asset fetching
