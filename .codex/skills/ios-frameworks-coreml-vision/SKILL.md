---
name: ios-frameworks-coreml-vision
description: On-device machine learning with CoreML model loading/prediction and Vision framework image analysis
---

# CoreML + Vision Skill

## Responsibility

This skill owns:

- MLModel loading (sync and async), MLFeatureProvider, MLPrediction
- PyTorch → CoreML conversion via coremltools
- Model compression: palettization, quantization, pruning (post-training, calibration-based, and training-time)
- Multi-function models (LoRA / adapter merging)
- MLComputeDevice hardware queries
- CoreMLRequest for running custom models through Vision
- Vision requests: text recognition, face detection, face landmarks, barcode detection, body pose, hand pose, object detection, image classification, aesthetics scoring
- VNRequest (legacy) and VisionRequest (modern Swift API)
- Custom model integration (.mlmodel / .mlpackage / .mlmodelc)
- On-device model updates and training (MLUpdateTask)

## Boundary — CoreML vs Foundation Models vs Vision

| Developer Intent | Skill |
|---|---|
| Run a custom ML model on-device | **This skill** — CoreML conversion + deployment |
| Compress/optimise a model for device | **This skill** — compression patterns |
| Deploy a custom LLM with KV-cache | **This skill** — stateful model patterns |
| Use Apple Intelligence / Foundation Models | **foundation-models** — Apple's on-device LLM |
| Add text generation with @Generable | **foundation-models** — structured output |
| Use Vision framework for image analysis | **This skill** — Vision request patterns |

**Rule of thumb**: Converting/compressing/deploying your own model -> this skill. Using Apple's built-in AI -> `foundation-models`.

## Core Principles

1. **Models run on-device only.** CoreML models execute locally using CPU, GPU, and Neural Engine. Never send image data or model inputs to a remote server when a CoreML/Vision path exists.

2. **Use Vision's modern Swift API.** Use the async `request.perform(on:)` pattern. The modern API returns typed observations directly.

3. **Request/Observation pattern.** Every Vision operation follows the same shape: create a request, configure it, perform it on an image, iterate the returned observations. Keep this uniform across all request types.

4. **Process off the main thread.** Model inference and Vision requests are computationally expensive. Always run them in an async context or on a background queue. Never block the main actor with inference work.

5. **Configure compute units intentionally.** Use `MLModelConfiguration.computeUnits` to control hardware dispatch (`.all`, `.cpuOnly`, `.cpuAndGPU`, `.cpuAndNeuralEngine`). Default to `.all` unless profiling shows a specific unit is better for the model.

6. **Degrade gracefully.** Not all devices support every Vision request or Neural Engine dispatch. Check availability, handle errors from `perform`, and provide fallback behaviour when a capability is unavailable.

## References

- `references/coreml-vision-patterns.md` — API patterns and code examples for CoreML and Vision
- `references/coreml-diagnostics.md` — Symptom-to-fix table for common CoreML issues
