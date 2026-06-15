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

### Known performance risks (to validate/fix on device)
- **`ReframePipeline` does `cmd.waitUntilCompleted()` per frame** — simplest-correct, but it stalls
  the CPU on the GPU every frame. On device this caps throughput. *Fix:* use a completion handler +
  triple-buffered pool so preview/record read when the GPU signals, never blocking capture. (Marked
  TODO in code.)
- **GPU work runs on the main actor** (the frame consumer `Task` inherits `@MainActor`). Fine for the
  cheap CPU math, but the Metal dispatch should move off-main on device. *Fix:* dedicated GPU queue.
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
2. ★ **Replay scrubber with the tracking box drawn on saved clips** — uses the sidecar crop data
   (PLAN §14) to overlay where the subject was; great for coaching review (the core use case).
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

## Known bugs

| # | Symptom | Status |
|---|---------|--------|
| 1 | Preview squeezed/skewed (16:9 stretched onto full screen) | **Fixed & confirmed on device** — blit aspect-fits + letterboxes. |
| 2 | Preview rotated 90° | **Fix shipped, awaiting device confirm** — root cause was the capture connection's `videoRotationAngle` never being set; now applied via `AVCaptureDevice.RotationCoordinator` (matches how the phone is physically held) + per-frame buffer dims. Because rotation is handled at capture, recordings inherit the correct orientation too. *Follow-up:* update the angle live on device rotation (currently set once at configure). |

### Signing note
Headless `xcodebuild -allowProvisioningUpdates` (personal team) intermittently fails with
"No Account for Team" right after a project regen; a retry succeeds. `⌘R` from Xcode always works.

---

## How to measure / verify

- Core tests: `cd TrackerCamCore && ./Scripts/verify.sh` (167 checks).
- Core perf: `cd TrackerCamCore && ./Scripts/perf.sh`.
- Sim build: `xcodebuild ... -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`.
- Device deploy: `./deploy.sh` (build + install + launch over cable/Wi-Fi).
- On-device profiling (Phase 0): Xcode Instruments — Time Profiler, Metal System Trace, Allocations.
