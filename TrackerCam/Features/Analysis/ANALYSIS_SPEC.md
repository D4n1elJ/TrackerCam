# Clip Analysis Spec — on-device "coach mode" (RF-DETR + pose + annotation)

Offline, **on-device, no-cloud** analysis of a recorded clip. Pipeline (see `ClipAnalyzer`):

```
clip.mov ──▶ downscale (long side 1280, 32BGRA)
         ──▶ RF-DETR (Core ML)        → horse + rider boxes      [SubjectDetector.swift]
         ──▶ Vision body pose         → rider skeleton + angles  [RiderPoseEstimator.swift]
         ──▶ horse-keypoint (Core ML) → horse skeleton (optional)[HorsePoseEstimator.swift]
         ──▶ angle math (pure)        → RiderAngles              [TrackerCamCore/PoseGeometry.swift]
         ──▶ Core Graphics + AVAssetWriter → annotated.mov       [ClipAnnotator.swift]
```

## What runs today with NO extra model
- **Rider pose & angles** — Vision `VNDetectHumanBodyPoseRequest`. Native, on-device (Neural Engine),
  zero third-party deps. This is the iOS stand-in for MediaPipe Pose. Runs on device; like all
  ANE-backed Vision requests it may fail in the **simulator** (espresso) — validate on device.
- **Annotation & export** — Core Graphics overlay + `AVAssetWriter` H.264. Native; OpenCV not required.

## Drop-in model #1 — RF-DETR detector (horse + rider boxes)
- **Resource:** `RFDETR_horse_rider.mlpackage` → compiled `RFDETR_horse_rider.mlmodelc`.
- Place under `TrackerCam/ML/`, add to `project.yml` target resources, run `make generate`.
- **Type:** Vision-compatible object detector → results as `VNRecognizedObjectObservation`
  (export from Roboflow/coremltools **including** the NMS pipeline + class-label metadata; a bare
  tensor output won't parse).
- **Required labels** (case-sensitive): `horse` (required), `person` or `rider` (rider box).
- Until bundled, `RFDETRDetector.isModelLoaded == false`; the analyzer still runs rider pose on the
  whole frame (no ROI crop) so the feature degrades gracefully.
- **Training:** label a horse+rider dataset (start from Roboflow Universe), train RF-DETR, export to
  Core ML. This is the box detector — the live tracker's `YOLO26n_horse` slot is analogous.

## Drop-in model #2 — Horse keypoints (the long pole) ⚠️
- **Resource:** `Horse_keypoints.mlpackage` → `Horse_keypoints.mlmodelc` under `TrackerCam/ML/`.
- **No native option exists** (Vision/MediaPipe pose are human-only). Requires a custom **animal-pose
  keypoint model** (train on AP-10K / a horse-specific keypoint set; export with coremltools).
- Implement decode in `CoreMLHorsePoseEstimator.skeleton(...)` → `TCSkeleton` keyed by
  `TCHorseJoint` raw values. Suggested joints: nose, poll, withers, croup, tailBase, the four hooves,
  carpus/hock. Adjust `TCHorseJoint` to match the trained model.
- Until bundled: horse *box* (from RF-DETR) and rider analysis work; horse *angles* are absent and the
  UI says so.

## Coordinate conventions
- Analysis image: top-left origin, y-down, pixels in the downscaled space (`ClipAnalysis.imageSize`).
- Vision outputs are normalized bottom-left — `RiderPoseEstimator` and `SubjectDetector` convert at the
  boundary (via `VisionGeometry`) so everything downstream (angles, annotation) shares one space.

## Why MediaPipe / OpenCV aren't bundled
- **MediaPipe** → replaced by Vision body pose (native, no CocoaPods dep). To match a desktop MediaPipe
  pipeline exactly, implement `RiderPosing` with MediaPipe Tasks `PoseLandmarker` and map 33 landmarks
  to `TCRiderJoint`. The seam is already there.
- **OpenCV** → replaced by Core Graphics (draw) + AVAssetWriter (encode). Add `opencv2.xcframework`
  only if you need classical CV math (optical flow, homography, contour analysis).
