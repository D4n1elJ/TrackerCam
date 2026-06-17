# TrackerCam Improvements — Round 2

The first pass (`improvements.md`) cleared the build-health, concurrency, accessibility, and
code-quality backlog — all 40 items are done. This second pass is a different altitude: it targets
**functional completeness, confidence (tests/CI/profiling), architecture, and shipping** — the work
that stands between "the code is clean" and "this is a product people can rely on."

Grounded in the current tree (commit `1d66a8d`). Each item cites the real file/line evidence.

---

## P0 — Functional completeness (the core promise)

These are not polish. Without them the app does not actually deliver its headline feature.

### 1. Ship the detection model — auto-acquisition is currently inert
- File: `TrackerCam/Features/Tracking/DetectionService.swift:26`
- Problem: the code loads `YOLO26n_horse.mlmodelc`, but **no model is bundled** (`nil until the
  .mlpackage is added (Phase 3)`). `isModelLoaded` is always `false`, so every code path gated on
  `detection.isModelLoaded` is dead. The app today is **tap-to-track only** — it cannot find a horse
  on its own, which is the entire "auto" in auto-reframe.
- Why it matters: "Auto acquire" / "Auto/refocus" acquisition modes (now shown in the UI) silently
  do nothing. This is the single largest gap between the codebase and the product pitch.
- Suggested approach: source or fine-tune a small detector (YOLO-class) for horse + rider, convert
  to Core ML (`.mlpackage` → compiled `.mlmodelc`), add it via `project.yml` so XcodeGen bundles it,
  and validate on-device inference time fits the detection cadence budget (plan §15). Until then,
  make the UI honest: hide/disable auto modes when `!isModelLoaded` rather than offering them.

### 2. Close the Phase 0 feasibility gate and the iOS 26 Vision-tracking spike
- Files: `PLAN.md:399` (tracking-API spike), `PLAN.md:548` (Phase 0 gate), `TrackingEngine.swift`
- Problem: PLAN explicitly flags one unresolved unknown — whether the new value-type
  `TrackObjectRequest` manages cross-frame sequence state internally on the shipping iOS 26 SDK, or
  still needs the `VNSequenceRequestHandler` path the code currently uses. The Phase 0 capture-matrix
  validation (format/pixel-format/stabilization/sustained GPU fan-out per device+preset) is also
  not yet recorded as passed.
- Why it matters: the tracking core rests on an assumption that has not been confirmed on real
  hardware. If the assumption is wrong, framing quality degrades in ways no simulator shows.
- Suggested approach: run the spike on the iPhone 17 Pro, record results in `DEVICE_PROFILING.md`,
  and keep the fallback (`VNSequenceRequestHandler` + `VNTrackObjectRequest`) behind `TrackingEngine`
  as it already is.

### 3. Field-validate tracking accuracy on real footage
- Problem: no measurement exists of how well tracking actually holds a moving horse, how often it
  loses lock, and how the lost-recovery ladder (`CropPlanner`) behaves in practice.
- Why it matters: the product is a bet on tracking quality. Clean code that mis-frames is a failed
  product.
- Suggested approach: capture a corpus of real riding clips, run them through, and score lock
  retention / reacquisition latency / framing jitter. Use it to tune `KalmanFilter2D`, `CropController`
  rate limits, and the lost ladder. (A replay harness already exists via the sidecar — extend it to
  log metrics, not just visualize.)

---

## P1 — Confidence: tests, CI, profiling, observability

### 4. Decompose `CameraViewModel` (618-line god object)
- File: `TrackerCam/Features/Camera/CameraViewModel.swift` (618 lines — the largest file by far)
- Problem: it owns capture wiring, the per-frame pipeline, tracking, reframe, recording, storage
  policy, thermal, haptics, UI publishing, interruptions, and lifecycle. That breadth makes it hard
  to test and reason about.
- Suggested approach: extract collaborators behind small protocols — e.g. a `FramePipeline`
  (track→plan→reframe), a `RecordingController` (start/stop/append/storage), and a `UIPublisher`
  (throttled state). The view model becomes a thin coordinator. This is the prerequisite that makes
  #5 possible.

### 5. Add app-layer tests (currently zero)
- Evidence: `find TrackerCam -iname "*test*"` → nothing. Only `TrackerCamCore` has tests.
- Problem: every app-layer behavior — capability gating, detection cadence, recording finish/error
  handling, interruption policy application, settings→controller wiring — is unverified by tests.
- Suggested approach: once #4 lands, inject the collaborators as protocols and unit-test the
  coordinator with fakes (no AVFoundation needed). Prioritize the pieces with real logic: recording
  finish/error reporting (`RecordingService`), detection-in-flight gating, thermal cadence scaling.

### 6. Add CI (there is none)
- Evidence: no `.github/workflows`.
- Problem: `make validate-core/sim/archive` exist but only run when someone remembers. Regressions
  (like the broken reframe merge this session) can land unnoticed.
- Suggested approach: a GitHub Actions workflow on PR running `make validate-core` (fast, on every
  push) and `make validate-sim` (on PR). `validate-archive` nightly or on release tags.

### 7. On-device performance profiling — replace theoretical claims with measurements
- Files: `DEVLOG.md` (perf claims), `DEVICE_PROFILING.md` (the plan), signposts already in place
- Problem: the off-main reframe, 15 Hz throttle, and latency fixes are sound by construction but the
  numbers in `DEVLOG.md` are partly from a prior build. The signpost/Instruments plan exists but
  hasn't been executed against the current tree.
- Suggested approach: run Time Profiler + Metal System Trace + Energy Log on a seeded, recording
  session (plan in `DEVICE_PROFILING.md`), confirm the main thread is idle during capture and the
  `CVPixelBufferPool` recycles, and record real fps/track-ms/reframe-ms/thermal under sustained load.

### 8. Add MetricKit observability (on-device, privacy-safe)
- Problem: no crash/hang/thermal/battery telemetry. For a camera app doing sustained GPU + ML work,
  field issues (thermal throttling, memory growth, hangs) are invisible without it.
- Suggested approach: adopt `MXMetricManager` for crash diagnostics, hang rate, CPU/GPU/thermal, and
  disk writes. It's local-first and aligns with the app's "no cloud" stance (you choose if/how to
  surface or export). Pairs naturally with the privacy posture in `APP_STORE_NOTES.md`.

---

## P2 — Product, UX, and resilience

### 9. Decide and implement audio (currently video-only)
- Files: `PLAN.md:175`, `PLAN.md:236`, `RecordingService.swift` (video-only writer)
- Problem: audio was deliberately deferred and the mic permission removed. For training-review
  footage, coaches often want spoken feedback / ambient sound.
- Suggested approach: decide if MVP needs audio. If yes, add an `AVAssetWriterInput` audio path +
  mic capture and re-introduce `NSMicrophoneUsageDescription`, then field-test sync. If no, leave it
  deferred but make the decision explicit in product docs.

### 10. In-app sharing / export of recordings
- File: `TrackerCam/Features/Recording/` (saves to Photos via `RecordingStore`, no share path)
- Problem: clips can save to the photo library but there's no `ShareLink` / share sheet to send a
  clip (or its tracked version) directly to a coach or messaging app.
- Suggested approach: add a `ShareLink`/`UIActivityViewController` from the recordings library and
  replay view; consider exporting the tracked crop + optional overlay burn-in.

### 11. Recordings library management
- File: `TrackerCam/Features/Recording/RecordingsView.swift`
- Problem: review-focused product, but no trim, delete, rename, favorite, or storage-usage view.
- Suggested approach: add basic clip management and a storage indicator; trimming is high-value for
  coaching review (isolate the relevant 20 seconds).

### 12. Reacquisition robustness and "lost" UX
- Files: `CropPlanner.swift` (lost ladder), `TrackingEngine.swift`
- Problem: the lost-recovery ladder is implemented but untuned against real loss events; the user has
  little feedback on *why* tracking was lost or how to recover beyond tap-to-refocus.
- Suggested approach: surface a clear "searching / lost — tap subject" affordance, and (with #1's
  model) attempt automatic reacquisition near the predicted location before giving up.

### 13. First-run onboarding for tap-to-track
- File: `TrackerCam/Features/Onboarding/OnboardingView.swift` (exists)
- Problem: since auto-detection is currently absent, the core interaction is tap-to-track — but a
  new user won't know that. Verify onboarding teaches the actual interaction model.

### 14. Localization scaffolding
- Evidence: no `.xcstrings` / `Localizable.*` — all UI strings are hardcoded English.
- Suggested approach: migrate user-facing strings to a String Catalog now (cheap while the surface is
  small); even English-only benefits from centralized copy and review-notes consistency.

### 15. Deeper accessibility: Dynamic Type and a full VoiceOver pass
- Files: control views under `Features/Camera`
- Problem: round 1 added labels/actions/`updatesFrequently`, but Dynamic Type scaling, contrast in
  the live HUD over video, and a full rotor/focus-order audit aren't covered.
- Suggested approach: test at the largest Dynamic Type sizes and with Increase Contrast; ensure the
  landscape control cluster reflows.

### 16. Sustained-recording thermal and interruption resilience
- Files: `ThermalManager.swift`, `CameraService.swift` (interruption handling), `RecordingService.swift`
- Problem: short clips are handled; long shoots (the real use case — a full training session) will
  hit thermal throttling, storage pressure, and interruptions (calls, backgrounding). The policies
  exist but aren't validated end-to-end over 20–30 minute recordings.
- Suggested approach: run a long-recording soak test on device; confirm graceful degradation
  (cadence scaling → resolution → stop-and-save) and that finalize-and-continue works across an
  interruption mid-clip.

### 17. App Store submission assets
- File: `APP_STORE_NOTES.md` (privacy/review notes drafted)
- Problem: TestFlight internal testing needs little, but public release needs screenshots, an app
  description, keywords, and a support URL — none exist yet.
- Suggested approach: defer until after device validation, but track it so release isn't blocked on
  asset creation at the last minute.

---

## Summary

| Priority | Theme | Items |
|---|---|---|
| **P0** | Functional completeness | 1 (detection model), 2 (Phase 0 + Vision spike), 3 (field validation) |
| **P1** | Confidence | 4 (decompose VM), 5 (app tests), 6 (CI), 7 (profiling), 8 (MetricKit) |
| **P2** | Product/UX/resilience | 9 (audio), 10 (share), 11 (library mgmt), 12 (reacquire), 13–17 |

The most important realization: **the engineering is in good shape, but the product's headline
capability (auto-detection) is not actually wired to a model, and tracking quality is unproven on
real footage.** P0 items 1–3 are where the next real progress lives.

---

# Implementation Plan

Sequenced by dependency, not just priority. Owner legend:
- **[code]** — implementable now in this repo (Claude/codex), no external input.
- **[device]** — requires the physical iPhone 17 Pro (you run it).
- **[ml]** — requires a trained/converted Core ML model (data + training work).
- **[account]** — requires Apple Developer / App Store Connect access (you).

Each task lists concrete steps, the files it touches, its dependencies, and a **Done when** check.
Phases A–B and D can largely run in parallel; C and the back half of A gate on you/hardware.

---

## Phase A — Make auto-acquisition real (or honest)

The goal: stop shipping a non-functional "auto" mode, and make the model a drop-in once it exists.

### A1. UI honesty when no model is loaded  **[code]** — ~0.5 day
- Files: `SettingsView.swift`, `CameraView.swift` (`statusLabel`), `CameraViewModel.swift`
- Steps:
  1. Expose `detection.isModelLoaded` on the view model.
  2. In Settings, disable/footnote the `auto` and `autoRefocus` acquisition modes when no model is
     loaded; default to `tap`.
  3. In the live status label, never show "Auto acquire" if detection is unavailable.
- Done when: with no bundled model, the UI offers only tap-to-track and never implies auto-detection.
- Note: this is the one P0 item shippable immediately and should land first.

### A2. Model drop-in scaffolding + spec  **[code]** — ~1 day
- Files: `project.yml` (bundle `*.mlmodelc`), `DetectionService.swift`, new
  `TrackerCam/ML/MODEL_SPEC.md`, a model-load test
- Steps:
  1. Document the contract `DetectionService` expects: input pixel format/size, output (boxes +
     class + confidence), label set (horse, rider), and the `YOLO26n_horse` naming.
  2. Wire `project.yml` so a `.mlmodelc`/`.mlpackage` in a known folder is bundled automatically.
  3. Add a test/skipped-test that asserts `isModelLoaded == true` *when the model is present* (guards
     the integration once the model lands).
- Done when: dropping a correctly-named compiled model into the folder makes detection live with no
  code change, and the bundle path is regenerated by `make generate`.

### A3. Produce the detection model  **[ml]** — external, days–weeks
- Steps: source or fine-tune a small horse+rider detector → convert to Core ML `.mlpackage` →
  compile to `.mlmodelc` → validate on-device inference time against the detection cadence budget
  (plan §15) → drop into the A2 folder.
- Dependency: A2. Done when: on-device auto-acquisition seeds tracking within the cadence budget.

---

## Phase B — Confidence infrastructure (parallel with A, codeable now)

### B1. CI pipeline  **[code]** — ~0.5 day
- Files: new `.github/workflows/ci.yml`
- Steps: run `make validate-core` on every push; `make validate-sim` on PR; `make validate-archive`
  nightly or on `v*` tags. macOS runner with Xcode 26.
- Done when: a red `make validate-core` blocks a PR; the badge is green on `main`.

### B2. Decompose `CameraViewModel`  **[code]** — ~2–3 days
- File: `CameraViewModel.swift` (618 lines → coordinator + collaborators)
- Steps: extract `FramePipeline` (track→plan→reframe), `RecordingController`
  (start/stop/append/storage/finish), and a `UIPublisher` (throttled state) behind protocols; the
  view model becomes a thin coordinator wiring them.
- Dependency: coordinate with codex (it owns this file) to avoid churn. Done when: the view model is
  < ~250 lines and each collaborator is independently constructible with fakes.

### B3. App-layer tests  **[code]** — ~2 days
- Files: new `TrackerCamTests/` target (host app unit tests)
- Steps (after B2): unit-test the highest-logic collaborators with fakes — recording finish/error
  reporting, detection-in-flight gating, thermal cadence scaling, capability gating.
- Dependency: B2. Done when: `make` runs an app-test target and covers those behaviors.

### B4. MetricKit observability  **[code]** — ~1 day
- Files: new `TrackerCam/Diagnostics/MetricsService.swift`
- Steps: subscribe `MXMetricManager` for crash diagnostics, hang rate, CPU/GPU/thermal, disk writes;
  persist locally (no network, consistent with the privacy posture).
- Done when: diagnostics payloads are received and inspectable on device; documented in
  `APP_STORE_NOTES.md` privacy section.

---

## Phase C — On-device validation (gates on you + hardware)

### C1. Phase 0 spike + capability matrix  **[device]**
- Run the iOS 26 `TrackObjectRequest` state spike and the format/stabilization/fan-out matrix; record
  results in `DEVICE_PROFILING.md`. Done when: tracking-API behavior is confirmed and the fallback
  decision is recorded.

### C2. Performance profiling run  **[device]**
- Execute the `DEVICE_PROFILING.md` plan (Time Profiler, Metal System Trace, Energy, Allocations) on
  a seeded recording session. Done when: real fps/track-ms/reframe-ms/thermal are logged and the
  `DEVLOG.md` claims are confirmed or corrected.

### C3. Tracking-accuracy corpus + metrics harness  **[code]** + **[device]**
- Files: extend the replay/sidecar harness to log metrics (lock retention, reacquire latency, jitter).
- Steps: capture real riding clips, run the harness, tune `KalmanFilter2D`/`CropController`/lost
  ladder against the numbers. Done when: tracking quality is measured, not assumed.

### C4. Long-recording soak  **[device]**
- Record 20–30 min continuously; verify graceful thermal degradation (cadence → resolution → stop)
  and interruption finalize-and-continue. Done when: a full-session recording completes without data
  loss or runaway heat.

---

## Phase D — Product / UX (codeable; order by value)

| Task | Owner | Effort | Done when |
|---|---|---|---|
| D1. Share/export (`ShareLink` from library + replay) | [code] | ~1 day | A clip (and tracked version) can be shared to Messages/Files. |
| D2. Recordings management (trim/delete/rename/storage) | [code] | ~2 days | Coaches can isolate and remove clips; storage usage is visible. |
| D3. Reacquisition UX ("searching — tap subject") | [code] | ~1 day | Loss state is clear; auto-reacquire attempted once A3 lands. |
| D4. Onboarding teaches tap-to-track | [code] | ~0.5 day | First-run explains the real interaction model. |
| D5. Localization scaffold (String Catalog) | [code] | ~1 day | UI strings live in `.xcstrings`; English complete. |
| D6. Dynamic Type + full VoiceOver/contrast pass | [code]+[device] | ~1 day | Largest Dynamic Type + Increase Contrast usable in landscape. |
| D7. Audio (decision-gated) | [code] | ~2 days | Decision recorded; if yes, A/V-synced writer + mic perm restored. |

---

## Phase E — Shipping

### E1. TestFlight enablement
- **[code]**: add `ITSAppUsesNonExemptEncryption=false` to `Info.plist`; scaffold `testflight.sh` +
  `ExportOptions.plist` (archive → export `app-store-connect` → upload); bump `CURRENT_PROJECT_VERSION`.
- **[account]**: confirm paid Developer Program (team `DZNC8GD6WJ`), create the App Store Connect app
  record for `com.trackercam.app`, generate an API key.
- Done when: `./testflight.sh` uploads a build that appears in TestFlight; internal testers added.

### E2. App Store assets  **[account]+[code]**
- Screenshots, description, keywords, support URL. Defer until after C-phase validation. Done when:
  the App Store Connect listing is submission-ready.

---

## Suggested execution order

1. **Now, in parallel:** A1 (UI honesty), B1 (CI), E1 code half (encryption key + scaffold). All small, all unblock value.
2. **Next:** B2 → B3 (decompose, then test) while you run **C1/C2** on device and start **A3** (model).
3. **Then:** B4, D1–D5 by value; fold in C3 tuning as the corpus grows.
4. **Before public release:** C4 soak, D6 a11y, E2 assets.

**Critical path to a *real* product:** A1 → A2 → A3 → C3. Everything else raises quality and
confidence, but auto-detection + proven tracking is what makes TrackerCam the thing it claims to be.
