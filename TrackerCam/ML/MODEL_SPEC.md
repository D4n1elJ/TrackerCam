# Detection Model Spec (improvements2 A2)

`DetectionService` expects a bundled Core ML object-detection model. This document pins the exact
contract so a trained model is a **drop-in** — no code changes needed. Source of truth:
`TrackerCam/Features/Tracking/DetectionService.swift`.

## File & bundling
- **Resource name:** `YOLO26n_horse` — loaded as `Bundle.main.url(forResource: "YOLO26n_horse", withExtension: "mlmodelc")`.
- Ship a compiled **`YOLO26n_horse.mlmodelc`** (Xcode compiles a `.mlpackage`/`.mlmodel` added to the
  target automatically; the compiled name matches the source name).
- Place the model under `TrackerCam/ML/` and ensure `project.yml` includes it as a bundled resource,
  then `make generate` (XcodeGen) so it's in the target. Verify with `isModelLoaded == true`.

## Model type
- A **Vision-compatible object detector** whose results Vision returns as
  `VNRecognizedObjectObservation` (bounding box + per-class labels + confidence).
- Recommended production paths:
  - **Create ML → Object Detection** (emits a Vision-native detector directly), or
  - **YOLO (v8/v11-class) → coremltools** export *including* the NMS pipeline and class-label
    metadata so Vision wraps outputs as `VNRecognizedObjectObservation`. A bare tensor-output model
    will **not** parse — it must carry the detector pipeline/metadata.

## Required class labels (exact identifiers)
The parser switches on `label.identifier`:
- **`horse`** — required. No horses detected → no target returned.
- **`person`** — optional; used to associate a rider (compound horse+rider target).
- Any other labels are ignored. Identifiers are **case-sensitive** and must match exactly.

## Input
- Vision feeds the analysis pixel buffer with `imageCropAndScaleOption = .scaleFill`, so the model may
  define its own input size (e.g. 640×640). The app passes the ~720p downscaled analysis buffer
  (`CameraViewModel.analysisSize`, long side ~1280), not the full 4K frame.
- No specific color/normalization assumptions beyond a standard RGB image input.

## Output
- Bounding boxes in **Vision-normalized coordinates** (origin bottom-left, 0…1) — the standard
  `VNRecognizedObjectObservation.boundingBox`. The app converts to source pixels via
  `VisionGeometry.pixelRect(fromNormalized:imageSize:)`.
- Each observation must expose `labels` (sorted by confidence) and `confidence`.

## Selection behavior (already implemented — informational)
- Detections below `settings.confidenceThreshold` are dropped.
- Best horse = confidence × center-proximity × size (plan §8). A rider box overlapping the upper
  horse region is associated into a compound target.

## Performance budget
- Detection runs on a **cadence** (`settings.redetectionInterval`, thermally scaled), not every frame,
  and is coalesced to one in-flight call. Tracking (Vision `VNTrackObjectRequest`) carries frames in
  between.
- Target on-device inference well under the cadence so detection never blocks tracking. Measure
  `detectionMs` (already surfaced in the debug HUD) on the iPhone 17 Pro and keep the model small
  (nano/small class) to stay within the per-frame budget (plan §15).

## Acceptance
A correct model satisfies all of:
1. Named `YOLO26n_horse`, bundled, `isModelLoaded == true`.
2. Emits `VNRecognizedObjectObservation` with `horse` (and ideally `person`) identifiers.
3. On-device `detectionMs` comfortably below the redetection interval.
4. Auto-acquisition seeds tracking from idle on a real horse (improvements2 A3/C3).
