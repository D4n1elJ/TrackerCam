# TrackerCam — Devlog, Performance & Ideas

Living document. Priorities: **performance** and **ease of use**. See `PLAN.md` for the locked v1 spec
and `README.md` for build/run.

---

## Performance findings

### Per-frame core math — measured
Micro-benchmark (`TrackerCamCore/LocalPerf`, `Scripts/perf.sh`): the full per-frame CPU pipeline
(Kalman predict+update → required crop size → composition → CropPlanner → CropController →
Guidance) costs **~0.15 µs/frame** — **<0.001%** of the 16.67 ms (60 fps) budget. The tracking math
is effectively free; budget is dominated by **Vision tracking, Core ML detection, the Metal reframe,
and HEVC encode** — all device-only (PLAN §15).

### Performance work — done (device-reported "really slow" → optimized)
- **Removed the per-frame `waitUntilCompleted` main-thread GPU stall.** `ReframePipeline.render` is
  now `async`, runs on a dedicated `gpuQueue`, and awaits an `addCompletedHandler` (no CPU spin, no
  main-thread block). This was the dominant cost.
- **Bounded the frame stream** (`AsyncStream` `.bufferingNewest(2)`) so a slow frame can't grow
  latency — latest-wins.
- **Throttled SwiftUI overlay updates to ~15 Hz** while the Metal preview stays 60 Hz (the texture
  isn't read in any SwiftUI body, so it doesn't trigger re-renders). Stops 60 Hz overlay re-layout.
- **Vision tracking → `.fast`** trackingLevel (real-time priority).

### Shipped since
- **Rotation locks during recording** (plan §9) — live KVO rotation updates are suspended between
  record start/stop so a mid-clip device rotation can't flip the output.
- **`deploy.sh` hardened** — retries through device sleep/disconnect; only fails on real
  signing/compile errors.
- **Accessibility labels** on the record / refocus / settings / recordings controls (VoiceOver).
- **Sidecar metadata + replay scrubber** shipped end-to-end (see backlog #2).
- **`PrivacyInfo.xcprivacy`** added — required-reason APIs (UserDefaults CA92.1, file timestamp
  C617.1, disk space E174.1); no tracking, no off-device data collection. Submission-readiness.

### On-device measurements (live via idevicesyslog, 2026-06-15)
Streamed the app's `os_log` perf line from the device (`idevicesyslog | grep fps=`):
```
fps=60  trackMs=0  reframeMs=1  thermal=nominal  src flips 2160x3840 ↔ 3840x2160 on rotate
```
**Conclusion:** the pipeline is NOT compute-bound — tracking ~0 ms, GPU reframe ~1 ms, sustained 60 fps,
nominal thermal. The user's "video delayed" is **display/buffering latency**, not framerate. Latency
sources: CAMetalLayer triple-buffering (default 3 drawables), the un-synced 60 Hz MTKView pull vs the
60 Hz reframe, and async hops (actor + GPU continuation + MainActor).
**Latency fixes applied:** frame buffer `.bufferingNewest(1)`, removed a router queue hop, and
`CAMetalLayer.maximumDrawableCount = 2`. If still laggy, next lever is a synchronous off-main frame
pipeline (drop the per-frame async hops) or rendering straight into the drawable (push, not pull).

### Live debugging setup
- On-screen HUD (Settings → Advanced → Show debug HUD): fps/state/thermal.
- Remote: `idevicesyslog | grep fps=` streams the 1 Hz perf line (fps, trackMs, reframeMs, thermal).
- Instruments (⌘I): `os_signpost` intervals `track` and `reframe` show as labeled lanes.

### On-device performance profiling plan (Phase 0, Instruments)
Run on the iPhone 17 Pro with a target seeded (tap-to-track) and recording:
1. **Time Profiler** — confirm the main thread is idle during capture (GPU now off-main). Watch for
   any >1 ms main-thread frames.
2. **Metal System Trace** — reframe GPU time per frame (budget <8 ms @ §15); confirm no CPU↔GPU
   serialization stalls now that `waitUntilCompleted` is gone.
3. **Allocations** — confirm the `CVPixelBufferPool` recycles (no per-frame buffer growth).
4. **Energy / thermal** — 5-min and 30-min runs; verify the thermal ladder kicks in (§15).
5. Capture fps / dropped-frame counters via the in-app debug HUD; compare to the §15 budgets.

### Performance — still to do (device profiling)
- **720p analysis downscale for Vision** — currently tracking would run on the 4K buffer when a
  target is seeded. Cheap now (no model bundled → detector off, tracker only on tap), but add a GPU
  downscale before shipping detection. (PLAN §6/§9.)
- **Lock rotation while recording** — rotation currently updates live via KVO even mid-record; per
  PLAN §9 it should lock at record start.
- **Detector runs synchronously inside the tracking actor** (`DetectionService` is non-actor by
  design to avoid sending the pixel buffer). Throttled by `redetectionInterval`, but a slow model
  could stall tracking. *Fix:* keep detection cadence conservative; consider a separate inference
  queue once measured on device.
- **`onCameraCaptureEvent` / battery polling** are negligible.

---

## Quality-of-life

### Shipped
- Crop is **rate-limited + hysteresis-smoothed** (no jumps/pumping) — CropController/CropPlanner.
- **Lost-recovery ladder**: predict → ease to center → hold wide (no frozen close crop on loss).
- **Onboarding** defers the camera-permission prompt until after the tutorial.
- **Mini-map**, **confidence ring**, **debug HUD** (fps/state/thermal), **battery warning**,
  **low-storage countdown**, **recordings browser**, **interruption/continuation** handling.
- Effective capture config (incl. SDR vs HDR) is surfaced, not assumed.
- **Rule-of-thirds grid** toggle (Settings → Framing).
- **Haptics** on lock (success) / lost (warning) transitions, gated by the haptics setting.

### Backlog (ease-of-use)
- **Landscape nudge**: the preview letterboxes in portrait (16:9 output) — show a one-time hint to
  rotate to landscape, the launch-priority orientation (PLAN §4/§12).
- **Double-tap to recenter / clear target** (fast manual reset).
- **Pinch to bias zoom** within the dynamic-zoom bounds.
- **Tap-and-hold to lock exposure/focus** (post-MVP per plan, but high QoL).
- **Persist last-used preset** and show the active preset name on the HUD.

---

## Cool feature backlog (prioritized; ★ = worth building for v1/v1.x)

1. ★ **Framing grid + haptics** — cheap, big ease-of-use win. *(building now)*
2. ✅ **Replay scrubber with the tracking box on saved clips** — SHIPPED. Sidecar `.ndjson` written
   during recording (opt-in) + `ReplayView` plays the clip with the box overlaid (`Sidecar` parser,
   AVPlayer periodic observer, aspect-fit placement). Coaching review (core use case) works end-to-end.
   *Polish TODO:* derive the exact video display rect rather than assuming 16:9; stream sidecar for
   long clips instead of in-memory.
3. ★ **"Auto-Highlight" reels** — detect the most active/centered segments and export short clips.
   Pure post-processing on recorded files; no extra capture cost.
4. **Multi-subject quick-switch** — tap to cycle among detected subjects (post-v1 per plan, but the
   detection already returns candidates).
5. **Apple Watch remote** — start/stop + haptic guidance without looking at the phone (PLAN §20).
6. **Live Activity** — recording duration + tracking status on the lock screen (PLAN §20).
7. **Cloud/Share export** — explicit, consent-gated (PLAN privacy constraints).
8. **Sport profiles** — equestrian → cycling/running/skiing/dog-agility (PLAN §20), each a model +
   framing preset.

---

## Rider-anchored tracking (shipped, awaiting device confirm)

The rider is the subject element Vision's built-in APIs actually understand (there is no built-in
horse pose — animal pose supports only cats/dogs), so the pipeline now **tracks the rider and
frames the horse**: `VNDetectHumanBodyPoseRequest` joint boxes (falling back to human rectangles)
produce a tight rider anchor; the tracker seeds/corrects on that anchor, and the crop centers and
sizes on the horse+rider envelope derived from it (`DetectionService.horseAndRiderEnvelope`).
Because body pose is a per-frame detection rather than a frame-difference heuristic, a
rider-anchored detection may auto-bootstrap even handheld (the gyro gate still applies to the
motion/color/saliency heuristics). Saliency/color/motion remain the fallback for riderless scenes.

---

## Known bugs

| # | Symptom | Status |
|---|---------|--------|
| 1 | Preview squeezed/skewed (16:9 stretched onto full screen) | **Fixed & confirmed on device** — blit aspect-fits + letterboxes. |
| 2 | Preview rotated 90° | **Fix shipped, awaiting device confirm** — root cause was the capture connection's `videoRotationAngle` never being set; now applied via `AVCaptureDevice.RotationCoordinator` (matches how the phone is physically held) + per-frame buffer dims. Because rotation is handled at capture, recordings inherit the correct orientation too. *Follow-up:* update the angle live on device rotation (currently set once at configure). |
| 3 | Handheld: crop wanders on its own and ignores tap-to-track | **Fix shipped, awaiting device confirm** — motion-centering (fixture-validated, static camera) unconditionally overrode the tracker with the frame-difference motion centroid; handheld shake/pan makes the whole frame "motion", so the crop chased noise (and auto-acquire's heuristic fallback seeded targets without a tap, so it wandered even idle). Now gyro-gated via `DeviceStillnessMonitor` (CoreMotion): the tracker is primary; the motion centroid only steers when the device has been physically still ≥0.5 s, only while a target is active, and only assists (blend, proximity-gated) when the tracker already has a subject. Model-free (heuristic) auto-acquire seeding is gated the same way — it relies on the same frame-difference signals — so on a moving phone acquisition is tap-initiated until a trained model is bundled. Centering-metric samples are likewise skipped while panning so `avg` stays comparable. |

### Signing note
Headless `xcodebuild -allowProvisioningUpdates` (personal team) intermittently fails with
"No Account for Team" right after a project regen; a retry succeeds. `⌘R` from Xcode always works.

---

## Reference: Apple-dev skills (`.codex/skills/`)
A large Codex-format skill library is in the repo. Codex format → not auto-loaded by Claude Code,
but useful as reference. They validate our architecture (camera-media skill independently prescribes
RotationCoordinator + serial session queue + begin/commit + 5 interruption reasons — all done).
Most relevant: `ios-frameworks-camera-media`, `ios-frameworks-coreml-vision`, `ios-frameworks-metal`,
`apple-dev-swift6-concurrency`, `apple-dev-performance-instruments`, `apple-dev-ios26-api-reference`,
`avkit`, `ios-frameworks-apple-haptics`, `core-motion`, `apple-dev-privacy-manifest`. Build/ship:
`apple-dev-ios-build/simulate/test`, `apple-dev-submission-preflight`. **TODO from coreml-vision skill:**
consider migrating the tracker/detector to the modern async Vision API (`request.perform(on:)`).

## How to measure / verify

- Core tests: `cd TrackerCamCore && ./Scripts/verify.sh` (167 checks).
- Core perf: `cd TrackerCamCore && ./Scripts/perf.sh`.
- Sim build: `xcodebuild ... -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`.
- Device deploy: `./deploy.sh` (build + install + launch over cable/Wi-Fi).
- On-device profiling (Phase 0): Xcode Instruments — Time Profiler, Metal System Trace, Allocations.
