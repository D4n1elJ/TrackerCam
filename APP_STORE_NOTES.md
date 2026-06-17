# TrackerCam App Store And Privacy Notes

TrackerCam MVP positioning should be consistent across onboarding, App Store metadata, review notes, and any privacy policy.

## Local-Only Processing

- Camera frames are processed on device for tracking, reframing, and optional sidecar metadata.
- No footage, tracking boxes, frame timing, or device capability data is uploaded by the MVP app.
- Recordings stay in the app library unless the user chooses Photos export.
- Photos access is add-only; the app does not browse or read the user's photo library.

## Permissions

- Camera: required for capture and tracking.
- Photos add-only: optional, used only when saving to Photos.
- Microphone: not requested in the video-only MVP. Do not add microphone copy unless audio capture is implemented and validated.

## Review Notes

- The app targets rear-camera landscape recording for training review.
- Front camera and multi-camera capture are intentionally unsupported in MVP.
- Advanced FPS modes are device-capability gated; iPhone 17 Pro is the mandatory target device.
- The tracking overlay in replay is generated from local sidecar metadata recorded alongside the clip.

## Privacy Nutrition Label Draft

- Data collected: none for MVP, assuming no analytics/crash SDK is added.
- User content: videos are created and stored locally or saved to Photos at user request; not collected by developer.
- Diagnostics: only local debug HUD/logging during development unless a future telemetry system is added.
