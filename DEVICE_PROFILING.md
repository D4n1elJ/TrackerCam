# TrackerCam Device Profiling

Use this checklist on physical hardware before treating an MVP build as field-ready. Simulator results do not validate camera, Vision, Metal, thermal, or one-handed operation.

## Target Devices

- Mandatory: iPhone 17 Pro on the latest stable iOS 26.x available at release.
- Nice-to-have: iPhone 16 Pro for compatibility comparison.

## Build

Run a Release archive first:

```sh
make validate-archive
```

Install/run from Xcode on the device with the same scheme, then profile with Instruments.

## Instruments Runs

1. Time Profiler: record at least 5 minutes at 1080p/60 tracked output. Inspect Vision tracking, detection, GPU reframe, and SwiftUI publish cost.
2. Points of Interest: filter `com.trackercam.app` and verify `track` and `reframe` signposts remain stable under movement.
3. Energy Log: record 5 minutes outdoors or bright-screen equivalent. Note battery drop, thermal transitions, and any frame-rate degradation.
4. Metal System Trace: verify the reframe pass has stable command-buffer pacing and no sustained GPU backlog.

## Field Checks

- Start in landscape 16:9 with the largest useful field of view.
- Confirm auto acquisition finds one subject from center framing and tap/refocus reacquires manually.
- Confirm the crop always includes the full subject plus surrounding environment; it must not become a close-up.
- Confirm right-hand one-handed controls are reachable while watching the screen: record, refocus, settings, recordings.
- Confirm low-storage countdown shows, haptics fire, recording stops within 5 seconds, and the saved segment remains playable.
- Confirm 5-minute minimum recording with optional crop sidecar does not grow app memory unexpectedly.

## Pass Criteria

- Sustained 1080p/60 tracked recording for 5 minutes on iPhone 17 Pro without critical thermal stop.
- Debug HUD detection latency and effective cadence remain stable enough for reacquisition.
- Saved replay opens with sidecar overlay and usable review controls.
- No camera permission prompts beyond camera/photo add-only for the video-only MVP.
