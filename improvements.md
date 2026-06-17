# TrackerCam Improvements

Prioritized review based on the local iOS development skills: build/XcodeGen, Swift 6 concurrency, camera/media, Metal, Vision/CoreML, testing, accessibility, privacy, and performance.

## P0 - Build And Repository Health

1. Fix the broken GPU reframe merge.
   - Status: DONE in this pass. `render(...)` now allocates the output pixel buffer, output texture, command buffer, and compute encoder before dispatch.
   - File: `TrackerCam/Features/Reframe/ReframePipeline.swift`
   - Problem: `render(...)` references `enc`, `outTex`, `cmd`, and `outBuffer` before they are created.
   - Impact: the app cannot build until this is repaired.
   - Expected fix: restore creation of the output pixel buffer, Metal output texture, command buffer, and compute encoder before setting textures and dispatching the shader.

2. Regenerate the Xcode project from `project.yml`.
   - Files: `project.yml`, `TrackerCam.xcodeproj/project.pbxproj`
   - Problem: both the XcodeGen spec and generated project are modified after conflict resolution.
   - Impact: manual `.xcodeproj` edits will drift from source-of-truth project configuration.
   - Expected fix: make `project.yml` authoritative, then run `xcodegen generate` and review only meaningful generated diffs.

3. Resolve the retained stash / dirty merge state before shipping more changes.
   - Problem: a conflict-producing stash was kept during the latest pull workflow.
   - Impact: future pulls/merges can accidentally reintroduce stale conflict content.
   - Expected fix: after verifying all intended changes are present, drop the safety stash and commit a clean state.

## P1 - Validation And Tests

4. Convert `TrackerCamCore/LocalTests` into real SwiftPM tests.
   - Status: DEFERRED. The existing `swiftc` harness remains active; `make validate-core` now wraps it and passes 196 checks. Full SwiftPM test-target migration is still open.
   - Files: `TrackerCamCore/LocalTests/*`, `TrackerCamCore/Package.swift`
   - Problem: `swift test` builds the package but reports `no tests found` because tests are not in a SwiftPM test target.
   - Impact: core crop/tracking/storage logic is not part of normal CI validation.
   - Expected fix: move or wire tests into `TrackerCamCore/Tests/TrackerCamCoreTests` and add a package test target.

5. Add repeatable validation commands.
   - Status: DONE in this pass. Added `Makefile` targets for `validate-core`, `validate-sim`, and `validate-archive`.
   - Suggested file: `Makefile`
   - Expected targets:
     - `validate-core`: run package tests.
     - `validate-sim`: build the iOS app for simulator.
     - `validate-archive`: archive for generic iOS to catch stricter Swift 6/concurrency issues.
   - Impact: prevents relying on ad hoc terminal commands before commits.

6. Run archive validation before commits that touch Swift concurrency or AVFoundation.
   - Status: DONE in this pass. `make validate-archive` completed successfully with `** ARCHIVE SUCCEEDED **`.
   - Reason: simulator/debug builds miss some strict concurrency failures.
   - Expected command shape: `xcodebuild -project TrackerCam.xcodeproj -scheme TrackerCam -destination 'generic/platform=iOS' archive`.

## P1 - Camera And Device Capability

7. Clean up duplicate rotation observation.
   - Status: DONE in this pass. There is now one `RotationCoordinator` observer path, routed through `applyRotation`.
   - File: `TrackerCam/Services/CameraService.swift`
   - Problem: a `RotationCoordinator` observer is created, immediately invalidated, then recreated.
   - Impact: unnecessary complexity around a latency-sensitive capture path.
   - Expected fix: keep one observer and apply rotation through `sessionQueue`, respecting `rotationLocked`.

8. Add real device capability reporting for iPhone 17 Pro and iPhone 16 Pro.
   - File: `TrackerCam/Services/CameraService.swift`
   - Problem: settings expose 100/120 fps experimental modes, but support is only inferred from format selection.
   - Impact: unsupported capture modes can be shown to users or silently downgrade.
   - Expected fix: build a capability probe that records available camera formats, effective fps, dimensions, stabilization, color space, HDR status, and whether the device meets the MVP target.
   - Product rule: iPhone 17 Pro is mandatory; iPhone 16 Pro is nice-to-have.

9. Make camera settings reflect actual capabilities.
   - Files: `TrackerCam/Features/Settings/SettingsView.swift`, `TrackerCam/Services/CameraService.swift`
   - Problem: unsupported frame rates/resolutions can be selected without a visible capability warning.
   - Expected fix: disable unsupported choices or mark them unavailable after capability discovery.

10. Keep all session work off the main actor.
    - File: `TrackerCam/Services/CameraService.swift`
    - Current state: mostly correct; `startRunning()`, configuration, and rotation writes use queues.
    - Improvement: audit every AVFoundation callback and mutable session/device property so it stays serialized on `sessionQueue` or `captureQueue`.

## P1 - Frame Pipeline, Metal, And Performance

11. Throttle SwiftUI overlay publishing.
    - File: `TrackerCam/Features/Camera/CameraViewModel.swift`
    - Problem: `trackingState`, `subjectViewRect`, `guidanceHint`, `cropInSourceRect`, `confidence`, `fps`, and `elapsed` are updated every processed frame.
    - Impact: SwiftUI can re-render at camera frame rate, causing hitches and battery drain.
    - Expected fix: keep `latestPreviewTexture` and `requestPreviewRedraw` per frame, but throttle non-preview UI state to roughly 10-15 Hz.

12. Restore and use frame signposts.
   - Status: DONE in this pass. Added signpost intervals around tracking and reframe plus a 1 Hz performance log.
    - File: `TrackerCam/Features/Camera/CameraViewModel.swift`
    - Problem: `Logger`, `OSSignposter`, and EMA fields exist but are not meaningfully used in the frame path.
    - Expected fix: add signposts around Vision tracking, detection, GPU reframe, recording append, and UI publish. Log 1 Hz summaries for fps, tracking ms, reframe ms, dropped frames, and thermal state.

13. Profile on a real device in Release configuration.
    - Reason: simulator/debug results are misleading for camera, Metal, Vision, and ProMotion.
    - Instruments to use:
      - Time Profiler for CPU hotspots.
      - Points of Interest for signposted frame stages.
      - Energy Log for recording battery cost.
      - Metal System Trace for GPU frame pacing.

14. Review Metal texture and buffer ownership.
    - Files: `TrackerCam/Features/Reframe/ReframePipeline.swift`, `TrackerCam/Features/Camera/MetalPreviewView.swift`
    - Problem: non-Sendable GPU resources are wrapped in unchecked sendability.
    - Expected fix: keep single-owner lifetime documented, avoid retaining stale textures longer than one frame, and verify no command buffer captures mutable non-Sendable state unnecessarily.

15. Remove duplicated MTKView setup.
   - Status: DONE in this pass. The preview now has a single push-render setup block.
    - File: `TrackerCam/Features/Camera/MetalPreviewView.swift`
    - Problem: `isPaused` and `enableSetNeedsDisplay` are assigned twice.
    - Impact: harmless, but it makes preview behavior look less intentional.
    - Expected fix: keep one clear push-render configuration block.

## P1 - Swift 6 Concurrency And Data Safety

16. Re-audit all `@unchecked Sendable` types.
    - Files:
      - `TrackerCam/Services/FrameRouter.swift`
      - `TrackerCam/Services/CameraService.swift`
      - `TrackerCam/Features/Reframe/ReframePipeline.swift`
      - `TrackerCam/Features/Tracking/DetectionService.swift`
    - Problem: unchecked sendability is sometimes necessary for `CVPixelBuffer`, AVFoundation, Vision, and Metal, but every use must have a narrow ownership contract.
    - Expected fix: document why each use is safe, reduce scope where possible, and prefer actors/value payloads for mutable shared state.

17. Fix replay callback isolation.
   - Status: DONE in this pass. The player callback captures immutable sidecar frames and hops `@State` mutation to `MainActor`.
    - File: `TrackerCam/Features/Recording/ReplayView.swift`
    - Problem: `AVPlayer.addPeriodicTimeObserver` callback mutates `@State` and reads `frames` from a sendable closure.
    - Expected fix: capture immutable loaded frames or explicitly hop to `MainActor` inside the callback.

18. Avoid unstructured tasks where lifecycle matters.
    - File: `TrackerCam/Features/Camera/CameraViewModel.swift`
    - Problem: several `Task { ... }` calls are fire-and-forget for tracking seed, clear target, stop recording, interruption handling, and detection.
    - Expected fix: keep handles for tasks that can outlive the screen or recording session, cancel them on disappear, and guard against stale session generations.

19. Decide whether `ReframePipeline` is main-actor or background-owned.
   - Status: DONE for the current design. `ReframePipeline` is now queue-backed and `@unchecked Sendable`; call sites pass `FramePayload` into the async render API, which resumes after GPU completion.
    - File: `TrackerCam/Features/Reframe/ReframePipeline.swift`
    - Problem: it is `@MainActor` but also has an unused `gpuQueue`.
    - Expected fix: either keep it main-actor and rely on async command-buffer completion, or move it behind an actor/queue with a strict sendable input contract. Do not leave both models half-present.

## P1 - Tracking And Vision

20. Make auto-acquisition behavior explicit.
    - Files: `TrackerCam/Features/Camera/CameraViewModel.swift`, `TrackerCam/Features/Tracking/TrackingEngine.swift`
    - Product rule: MVP assumes one target and ignores other horses.
    - Expected fix: document when tracking starts automatically versus requiring tap/refocus, and make the UI labels match that behavior.

21. Add fallback behavior for Vision request failures.
    - File: `TrackerCam/Features/Tracking/TrackingEngine.swift`
    - Problem: `try? sequenceHandler.perform(...)` swallows Vision errors.
    - Impact: tracking can silently stop without diagnostics.
    - Expected fix: count Vision failures, surface a debug HUD state, and transition through the existing lost/center-focus behavior.

22. Profile detection cadence and thermal degradation.
    - Files: `TrackerCam/Features/Camera/CameraViewModel.swift`, `TrackerCam/Services/ThermalManager.swift`
    - Expected fix: measure detection interval, track inference time, and adjust cadence based on thermal level and fps target.

## P2 - Recording And Storage

23. Track writer append failures separately from readiness drops.
    - File: `TrackerCam/Features/Recording/RecordingService.swift`
    - Problem: dropped frames are counted when the writer input is not ready, but failed `append(...)` results are ignored.
    - Expected fix: count append failures, expose writer status/error, and show a concise save/recording error when needed.

24. Add audio path validation.
    - Files: `TrackerCam/Services/CameraService.swift`, `TrackerCam/Features/Recording/RecordingService.swift`
    - Problem: the app requests microphone permission and says it records audio, but the visible writer path only appends video frames.
    - Expected fix: either implement audio capture/writer input or remove microphone permission and messaging until audio is actually recorded.

25. Stream crop metadata for long recordings.
    - File: `TrackerCam/Features/Camera/CameraViewModel.swift`
    - Problem: crop metadata is accumulated in memory and written at the end.
    - Impact: long clips can grow memory unnecessarily.
    - Expected fix: write sidecar metadata incrementally or flush in chunks.

26. Make stop-on-storage behavior more visible.
    - File: `TrackerCam/Features/Camera/CameraView.swift`
    - Current state: countdown banner exists.
    - Improvement: add haptic/audio feedback and an explicit final save status after forced stop.

## P2 - Privacy, Permissions, And App Store Readiness

27. Keep add-only Photos permission.
    - File: `TrackerCam/Features/Recording/RecordingStore.swift`
    - Current state: correct use of `PHPhotoLibrary.requestAuthorization(for: .addOnly)`.
    - Improvement: ensure no future gallery/browsing feature upgrades this to `.readWrite` unless the app truly reads the library.

28. Run a final privacy manifest scan before submission.
    - File: `TrackerCam/App/PrivacyInfo.xcprivacy`
    - Current state: declares UserDefaults, file timestamp, and disk space required-reason APIs.
    - Expected scan targets: `UserDefaults`, `@AppStorage`, file timestamps, disk space, system uptime, active keyboards, and third-party SDK manifests.

29. Reconcile microphone permission with actual functionality.
    - File: `TrackerCam/App/Info.plist`
    - Problem: `NSMicrophoneUsageDescription` exists and access is requested, but audio recording needs verification.
    - Expected fix: if audio is included in MVP, implement and validate it. If not, remove the mic request/usage string to reduce permission friction.

30. Prepare App Store metadata around local-only processing.
    - Product positioning: footage and frame analysis stay on device unless the user saves or shares recordings.
    - Expected fix: reflect this consistently in onboarding, privacy policy, App Store privacy nutrition labels, and review notes.

## P2 - Accessibility And UX

31. Add accessibility actions for preview gestures.
    - File: `TrackerCam/Features/Camera/CameraView.swift`
    - Problem: tap-to-refocus and double-tap-to-release are gesture-only.
    - Expected fix: add named accessibility actions for `Refocus tracking` and `Release target`.

32. Hide decorative overlays from VoiceOver.
    - Files:
      - `TrackerCam/Features/Camera/Components/GridOverlayView.swift`
      - `TrackerCam/Features/Camera/Components/OverlayView.swift`
      - `TrackerCam/Features/Camera/Components/MiniMapView.swift`
    - Expected fix: mark purely visual guides as accessibility hidden, while exposing meaningful tracking status in a single concise element.

33. Mark live text as frequently updating.
    - Files: `TrackerCam/Features/Camera/CameraView.swift`, debug HUD components
    - Examples: elapsed timer, storage countdown, fps/debug metrics.
    - Expected fix: add `.accessibilityAddTraits(.updatesFrequently)` where appropriate.

34. Add a Settings shortcut from denied-permission UI.
    - File: `TrackerCam/Features/Camera/CameraView.swift`
    - Problem: permission denied view tells the user to enable access but does not provide a direct button.
    - Expected fix: add an `Open Settings` button using `UIApplication.openSettingsURLString`.

35. Improve one-handed landscape ergonomics with runtime testing.
    - File: `TrackerCam/Features/Camera/CameraView.swift`
    - Current state: controls are biased to right-hand landscape use.
    - Expected fix: validate thumb reach on iPhone 17 Pro physical dimensions, especially record/refocus/settings while filming.

## P2 - Product-Specific Refinements

36. Keep the subject plus surroundings in frame.
    - Files: `TrackerCamCore/Sources/TrackerCamCore/CropPlanner.swift`, `TrackerCamCore/Sources/TrackerCamCore/CropMath.swift`, settings
    - Product rule: never crop into a close-up; always show the whole subject and environment.
    - Expected fix: enforce minimum crop size and subject padding bounds in core logic, not only settings UI.

37. Prefer landscape and largest useful field of view for MVP.
    - Files: settings, camera format selection, crop planner
    - Product rule: landscape is priority; portrait is nice-to-have.
    - Expected fix: make 16:9 landscape the default and treat portrait/square as secondary modes.

38. Keep double-camera / advanced multi-camera out of MVP unless it proves value.
    - Reason: multi-cam increases thermal load, battery drain, complexity, and device-specific failures.
    - Expected path: first ship reliable single rear-camera tracking. Revisit multi-camera only after profiling shows a clear benefit for reacquisition or wide-context capture on iPhone 17 Pro.

39. Make front camera explicitly unsupported for MVP.
    - Product rule: front camera is not needed.
    - Expected fix: keep camera selection back-camera only and avoid UI/settings that imply selfie support.

40. Define training-review workflow.
    - Files: `TrackerCam/Features/Recording/RecordingsView.swift`, `TrackerCam/Features/Recording/ReplayView.swift`, sidecar metadata
    - Product goal: consumer-focused training review.
    - Expected fix: make saved clips easy to replay, scrub, and inspect with tracking overlay; add share/export later.
