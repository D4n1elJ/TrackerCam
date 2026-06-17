# CoreML + Vision Patterns

## Core ML Basics

### Loading a Model

Prefer async loading. Synchronous loading blocks the calling thread during device specialisation.

```swift
// PREFERRED — async load (non-blocking)
let config = MLModelConfiguration()
config.computeUnits = .all
let model = try await MLModel.load(contentsOf: compiledModelURL, configuration: config)

// Xcode-generated wrapper (synchronous — use only when async unavailable)
let model = try MyModel(configuration: config)
```

### Warm Cache at Launch

First load triggers device specialisation (slow). Warm the cache in the background:

```swift
Task.detached(priority: .background) {
    _ = try? await MLModel.load(contentsOf: modelURL)
}
```

### MLModelConfiguration Compute Units

| Value                   | Description                                      |
|-------------------------|--------------------------------------------------|
| `.all`                  | Let the system decide the best hardware (default) |
| `.cpuOnly`              | Force CPU-only execution                          |
| `.cpuAndGPU`            | Allow CPU and GPU, exclude Neural Engine          |
| `.cpuAndNeuralEngine`   | Allow CPU and Neural Engine, exclude GPU          |

### Querying Available Compute Devices

```swift
let devices = MLModel.availableComputeDevices

let hasNeuralEngine = devices.contains { device in
    if case .neuralEngine = device { return true }
    return false
}

for device in devices {
    switch device {
    case .cpu:
        print("CPU")
    case .gpu(let gpu):
        print("GPU: \(gpu.name)")
    case .neuralEngine(let ne):
        print("Neural Engine: \(ne.totalCoreCount) cores")
    @unknown default:
        break
    }
}
```

### Prediction

```swift
let input = MyModelInput(image: pixelBuffer, otherFeature: 1.0)
let output = try model.prediction(input: input)
print(output.label, output.labelProbabilities)
```

### Getting a Model

- **Create ML app** — train directly on Mac with drag-and-drop datasets.
- **coremltools** — convert from PyTorch, TensorFlow, ONNX, scikit-learn via `coremltools.convert()`.
- **Apple model gallery** — download pre-built models from developer.apple.com.

### Model File Lifecycle

- `.mlmodel` / `.mlpackage` is the source file added to the Xcode project.
- Xcode compiles it to `.mlmodelc` at build time.
- Xcode auto-generates a Swift class matching the model name with typed input/output classes.
- At runtime, use compiled models only (`.mlmodelc`).

---

## PyTorch → CoreML Conversion

### Basic Conversion

```python
import coremltools as ct
import torch

model.eval()
traced_model = torch.jit.trace(model, example_input)

mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(shape=example_input.shape)],
    outputs=[ct.TensorType(name="output")],
    minimum_deployment_target=ct.target.iOS18,  # ALWAYS set this
)

mlmodel.save("MyModel.mlpackage")
```

**Critical**: Always set `minimum_deployment_target` to enable SDPA fusion, per-block quantization, and other optimisations.

### Dynamic Shapes

```python
# Range dimension (variable-length sequences)
ct.TensorType(shape=(1, ct.RangeDim(1, 2048)))

# Enumerated shapes (discrete options)
ct.TensorType(shape=ct.EnumeratedShapes(shapes=[(1, 256), (1, 512), (1, 1024)]))
```

### Conversion with State (for KV-Cache)

```python
states = [
    ct.StateType(
        name="keyCache",
        wrapped_type=ct.TensorType(shape=(1, 32, 2048, 128)),
    ),
    ct.StateType(
        name="valueCache",
        wrapped_type=ct.TensorType(shape=(1, 32, 2048, 128)),
    ),
]

mlmodel = ct.convert(
    traced_model,
    inputs=inputs,
    states=states,
    minimum_deployment_target=ct.target.iOS18,
)
```

---

## Multi-Function Models (LoRA / Adapters)

Deploy multiple adapters in a single model, sharing base weights. Weights are deduplicated automatically.

### Merging Models (Python)

```python
from coremltools.models import MultiFunctionDescriptor
from coremltools.models.utils import save_multifunction

desc = MultiFunctionDescriptor()
desc.add_function("sticker", "sticker.mlpackage")
desc.add_function("storybook", "storybook.mlpackage")

save_multifunction(desc, "MultiAdapter.mlpackage")
```

### Loading a Specific Function (Swift)

```swift
let config = MLModelConfiguration()
config.functionName = "sticker"  // or "storybook"
let model = try await MLModel.load(contentsOf: modelURL, configuration: config)
```

---

## Vision Framework (iOS 18+ Swift API)

All modern Vision requests are async and return typed observation arrays directly.

### Text Recognition

```swift
var request = RecognizeTextRequest()
request.recognitionLevel = .accurate  // or .fast
request.recognitionLanguages = [Locale.Language(identifier: "en")]

let observations = try await request.perform(on: image)
for observation in observations {
    if let candidate = observation.topCandidates(1).first {
        print(candidate.string, candidate.confidence)
    }
}
```

### Face Detection

```swift
let request = DetectFaceRectanglesRequest()
let faces = try await request.perform(on: image)
for face in faces {
    print(face.boundingBox)  // normalised coordinates
}
```

### Face Landmarks

```swift
let request = DetectFaceLandmarksRequest()
let faces = try await request.perform(on: image)
for face in faces {
    if let landmarks = face.landmarks {
        // landmarks.leftEye, landmarks.rightEye, landmarks.nose,
        // landmarks.outerLips, landmarks.leftEyebrow, etc.
        print(landmarks.nose?.normalizedPoints ?? [])
    }
}
```

### Barcode Detection

```swift
var request = DetectBarcodesRequest()
request.symbologies = [.qr, .ean13, .code128]
let barcodes = try await request.perform(on: image)
for barcode in barcodes {
    print(barcode.payloadString, barcode.symbology)
}
```

### Body Pose Detection

```swift
let request = DetectHumanBodyPoseRequest()
let poses = try await request.perform(on: image)
for pose in poses {
    if let nose = try? pose.recognizedPoint(.nose) {
        print(nose.location, nose.confidence)
    }
}
```

### Hand Pose Detection

```swift
var request = DetectHumanHandPoseRequest()
request.maximumHandCount = 2
let hands = try await request.perform(on: image)
for hand in hands {
    if let thumbTip = try? hand.recognizedPoint(.thumbTip) {
        print(thumbTip.location, thumbTip.confidence)
    }
}
```

### Image Classification (Custom Model via Vision)

```swift
let mlModel = try MyClassifier(configuration: .init()).model
let request = CoreMLRequest(model: mlModel)
let results = try await request.perform(on: image)
for observation in results {
    if let classification = observation as? ClassificationObservation {
        print(classification.identifier, classification.confidence)
    }
}
```

### Object Detection

```swift
let mlModel = try MyDetector(configuration: .init()).model
let request = CoreMLRequest(model: mlModel)
let results = try await request.perform(on: image)
for observation in results {
    if let detected = observation as? RecognizedObjectObservation {
        print(detected.labels.first?.identifier, detected.boundingBox)
    }
}
```

### Aesthetics Score

```swift
let request = CalculateImageAestheticsScoresRequest()
let scores = try await request.perform(on: image)
for score in scores {
    print(score.overallScore, score.isUtility)
}
```

### Image Input Types

The modern Vision API accepts multiple image representations:

- `CGImage`
- `CIImage`
- `CVPixelBuffer`
- `Data` (raw image data)
- `URL` (file URL to an image)

---

## Model Compression

Three techniques to reduce model size and improve inference speed. All use `coremltools` in Python.

### Palettization (Weight Clustering)

Clusters weights into a lookup table. Use `per_grouped_channel` for better accuracy on iOS 18+.

```python
import coremltools as ct
from coremltools.optimize.coreml import (
    OpPalettizerConfig,
    OptimizationConfig,
    palettize_weights,
)

# Basic (iOS 16+)
op_config = OpPalettizerConfig(nbits=4)

# Better accuracy — per-grouped-channel (iOS 18+)
op_config = OpPalettizerConfig(
    mode="kmeans",
    nbits=4,
    granularity="per_grouped_channel",
    group_size=16,
)

config = OptimizationConfig(global_config=op_config)
compressed = palettize_weights(model, config)
compressed.save("model_palettized.mlpackage")
```

| Bits | Compression | Accuracy Impact |
|------|-------------|-----------------|
| 8-bit | 2x | Minimal |
| 6-bit | 2.7x | Low |
| 4-bit | 4x | Moderate (use grouped channels) |
| 2-bit | 8x | High (requires training-time) |

**When to use**: Best general-purpose compression. Best for Neural Engine. 4-bit with grouped channels is the sweet spot.

### Quantization (Linear)

Maps float weights to lower-precision integers. Use `per_block` for better accuracy on iOS 18+.

```python
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig,
    OptimizationConfig,
    linear_quantize_weights,
)

# Basic INT8 (iOS 16+)
op_config = OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")

# Better accuracy — per-block INT4 (iOS 18+)
op_config = OpLinearQuantizerConfig(
    mode="linear",
    dtype="int4",
    granularity="per_block",
    block_size=32,
)

config = OptimizationConfig(global_config=op_config)
compressed = linear_quantize_weights(model, config)
```

**When to use**: Best for GPU on Mac. INT4 per-block is competitive with 4-bit palettization but runs better on GPU.

### Pruning

Zeros out small weights to create sparse representations.

```python
from coremltools.optimize.coreml import (
    OpMagnitudePrunerConfig,
    OptimizationConfig,
    prune_weights,
)

op_config = OpMagnitudePrunerConfig(target_sparsity=0.75)
config = OptimizationConfig(global_config=op_config)
compressed = prune_weights(model, config)
```

**When to use**: Best combined with palettization or quantization. Standalone pruning needs high sparsity (~75%+) for meaningful size reduction.

### Training-Time Compression

When post-training compression loses too much accuracy, fine-tune with compression applied during training.

```python
from coremltools.optimize.torch.palettization import (
    DKMPalettizerConfig,
    DKMPalettizer,
)

config = DKMPalettizerConfig(global_config={"n_bits": 4})
palettizer = DKMPalettizer(model, config)
prepared_model = palettizer.prepare()

# Fine-tune (your training loop)
for epoch in range(num_epochs):
    train_epoch(prepared_model, data_loader)
    palettizer.step()

final_model = palettizer.post-implementation-qa()
```

**Tradeoff**: Better accuracy than post-training, but requires training data and compute time.

### Calibration-Based Compression (iOS 18+)

Middle ground: uses calibration data (no full training) for better accuracy than blind post-training.

```python
from coremltools.optimize.torch.pruning import (
    MagnitudePrunerConfig,
    LayerwiseCompressor,
)

config = MagnitudePrunerConfig(
    target_sparsity=0.4,
    n_samples=128,  # calibration samples
)

compressor = LayerwiseCompressor(model, config)
sparse_model = compressor.compress(calibration_data_loader)
```

### Compression Decision Flow

1. Profile Float16 baseline first
2. Try 8-bit palettization → check accuracy
3. Try 6-bit → check accuracy
4. Try 4-bit with `per_grouped_channel` → check accuracy
5. If still losing accuracy → calibration-based compression
6. If still losing accuracy → training-time compression
7. Only use 2-bit with training-time compression

### Anti-patterns

- **Blind compression**: Always measure accuracy after compression. Compare predictions on a validation set before/after.
- **Skipping granularity options**: 4-bit per-tensor has 16 clusters for the entire weight matrix. Grouped channels = 16 clusters per 16 channels = much better.
- **Over-compression**: Going below 2-bit palettization usually destroys model quality.
- **Ignoring deployment target**: Calibration-based compression requires iOS 18+. Post-training compression works on iOS 16+.

---

## Async Prediction with Concurrency Limiting

Never fire unlimited concurrent predictions. Use a limiting pattern:

```swift
actor ModelPredictor {
    private let model: MyModel
    private let maxConcurrent: Int
    private var activeCount = 0

    init(model: MyModel, maxConcurrent: Int = 4) {
        self.model = model
        self.maxConcurrent = maxConcurrent
    }

    func predict(_ input: MyModelInput) async throws -> MyModelOutput {
        while activeCount >= maxConcurrent {
            try await Task.sleep(for: .milliseconds(10))
        }
        activeCount += 1
        defer { activeCount -= 1 }
        return try await model.prediction(input: input)
    }
}
```

For batch processing, use `TaskGroup` with a concurrency limit:

```swift
func predictBatch(_ inputs: [MyModelInput]) async throws -> [MyModelOutput] {
    try await withThrowingTaskGroup(of: (Int, MyModelOutput).self) { group in
        var results = [Int: MyModelOutput]()
        let maxConcurrent = 4

        for (index, input) in inputs.enumerated() {
            if index >= maxConcurrent {
                if let result = try await group.next() {
                    results[result.0] = result.1
                }
            }
            group.addTask {
                let output = try await self.model.prediction(input: input)
                return (index, output)
            }
        }

        for try await result in group {
            results[result.0] = result.1
        }

        return (0..<inputs.count).map { results[$0]! }
    }
}
```

---

## Stateful Models (KV-Cache for LLMs)

For transformer-based models that need key-value caching across predictions:

```swift
// Load model with state
let config = MLModelConfiguration()
config.computeUnits = .cpuAndNeuralEngine
let model = try MLModel(contentsOf: modelURL, configuration: config)

// Create state — persists across prediction calls
let state = model.makeState()

// Each prediction reads/writes the KV-cache state automatically
let input = try MLDictionaryFeatureProvider(dictionary: [
    "input_ids": MLMultiArray(shape: [1, sequenceLength], dataType: .int32)
])
let output = try model.prediction(from: input, using: state)
```

**Key points**:
- State is created once and reused across sequential predictions (autoregressive generation)
- The model must be converted with state support in coremltools (`ct.StateType`)
- Reset state for a new conversation/sequence by creating a new state object
- State lives in memory — large KV-caches can consume significant RAM

---

## MLTensor Pipeline Stitching (iOS 18+)

`MLTensor` enables connecting multiple models without copying data through CPU:

```swift
// Run model A, get output as MLTensor (stays on compute device)
let inputA = try MLDictionaryFeatureProvider(dictionary: ["x": inputData])
let outputA = try modelA.prediction(from: inputA)
let tensor = outputA.featureValue(for: "embedding")!.multiArrayValue!.mlTensor

// Transform on-device (no CPU round-trip)
let normalised = tensor / tensor.norm()

// Feed directly into model B
let inputB = try MLDictionaryFeatureProvider(dictionary: [
    "embedding": MLFeatureValue(mlTensor: normalised)
])
let outputB = try modelB.prediction(from: inputB)
```

**Key points**:
- Data stays on GPU/Neural Engine between models — avoids expensive CPU copies
- Use `.shapedArray(of:)` to materialise results only when you need CPU access
- MLTensor math operations: `+`, `-`, `*`, `/`, `.matmul()`, `.transposed()`, `.norm()`

---

## Deployment Target Feature Matrix

| Feature | Minimum iOS |
|---|---|
| CoreML basic inference | iOS 11 |
| Compute unit selection | iOS 12 |
| On-device model updates | iOS 13 |
| Async prediction (completion-based) | iOS 14 |
| MLComputeDevice (query hardware) | iOS 17 |
| Thread-safe async prediction | iOS 17 |
| MLTensor | iOS 18 |
| Stateful models (KV-cache) | iOS 18 |
| SDPA fusion | iOS 18 |
| Per-block quantization | iOS 18 |
| Per-grouped-channel palettization | iOS 18 |
| Multi-function models | iOS 18 |
| Calibration-based compression | iOS 18 |
| MLComputePlan (performance profiling) | iOS 18 |

### Spec Version → iOS Mapping

| Spec Version | Minimum iOS |
|---|---|
| 4 | iOS 13 |
| 5 | iOS 14 |
| 6 | iOS 15 |
| 7 | iOS 16 |
| 8 | iOS 17 |
| 9 | iOS 18 |

---

## On-Device Model Updates

CoreML supports incremental on-device training for updatable models.

```swift
let modelURL = try MLModel.compileModel(at: sourceModelURL)

let trainingData = try MLArrayBatchProvider(array: trainingInputs)
let config = MLModelConfiguration()

let updateTask = try MLUpdateTask(
    forModelAt: modelURL,
    trainingData: trainingData,
    configuration: config
) { context in
    let updatedModel = context.model
    let loss = context.metrics[.lossValue] as? Double
    print("Training complete, loss: \(loss ?? -1)")

    // Save the updated model
    try? context.model.write(to: updatedModelURL)
}
updateTask.resume()
```

Requirements for on-device updates:
- The model must be marked as updatable in Create ML or coremltools.
- Training data must conform to the model's training input schema.
- Updates happen on-device; no data leaves the device.
