# CoreML Diagnostics

## Quick Reference

| Symptom | First Check | Pattern |
|---|---|---|
| Model won't load | Deployment target / spec version | 1 |
| Model loads on some devices, not others | Compute unit support | 2 |
| Slow first load, fast after | Cache miss | 3 |
| All predictions slow | Compute unit dispatch | 4 |
| Fast on Mac, slow on iPhone (or vice versa) | Hardware differences | 5 |
| Memory grows during predictions | Concurrent prediction buffers | 6 |
| OOM on model load | Model too large | 7 |
| Bad accuracy after palettization | Granularity too coarse | 8 |
| Bad accuracy after quantization | Granularity / bit depth | 9 |
| Bad accuracy after pruning | Sparsity too aggressive | 10 |
| Outputs differ between devices | Compute unit float differences | 11 |
| Conversion fails (unsupported op) | Operation support | 12 |
| Conversion succeeds but wrong output | Input/precision mismatch | 13 |
| Works on simulator, not device | Simulator uses host hardware | 14 |

## Decision Tree

```
CoreML issue
├─ Load failure?
│   ├─ "Unsupported model version" → Pattern 1
│   ├─ "Failed to create compute plan" → Pattern 2
│   ├─ First launch only? → Pattern 3
│   └─ Out of memory? → Pattern 7
├─ Performance issue?
│   ├─ First prediction slow, rest fast? → Pattern 3
│   ├─ All predictions slow? → Pattern 4
│   └─ Slow on specific device only? → Pattern 5
├─ Memory issue?
│   ├─ Grows during predictions? → Pattern 6
│   └─ Crash on load? → Pattern 7
├─ Accuracy degraded?
│   ├─ After palettization? → Pattern 8
│   ├─ After quantization? → Pattern 9
│   ├─ After pruning? → Pattern 10
│   └─ Different between devices? → Pattern 11
└─ Conversion issue?
    ├─ Op not supported? → Pattern 12
    └─ Wrong output? → Pattern 13
```

---

## Pattern 1 — Model Version Mismatch

**Symptom**: "Unsupported model version" error on load.

**Cause**: Model compiled for newer iOS than the device supports.

**Diagnosis**:
```python
import coremltools as ct
model = ct.models.MLModel("Model.mlpackage")
print(model.get_spec().specificationVersion)
```

| Spec Version | Minimum iOS |
|---|---|
| 4 | iOS 13 |
| 5 | iOS 14 |
| 6 | iOS 15 |
| 7 | iOS 16 |
| 8 | iOS 17 |
| 9 | iOS 18 |

**Fix**: Re-convert with lower deployment target:
```python
mlmodel = ct.convert(traced, minimum_deployment_target=ct.target.iOS16)
```

**Tradeoff**: Loses SDPA fusion, per-block quantization, MLTensor, and state support.

---

## Pattern 2 — Compute Plan Failure

**Symptom**: Model loads on some devices but not others.

**Cause**: Unsupported operations for target compute unit on that hardware.

**Diagnosis**: Open model in Xcode → Performance Report → check "Unsupported" operations.

**Fix progression**:
1. Force CPU-only to confirm the model itself is valid:
   ```swift
   let config = MLModelConfiguration()
   config.computeUnits = .cpuOnly
   ```
2. If CPU works, the issue is GPU/NE op support. Convert with Float16:
   ```python
   mlmodel = ct.convert(traced, compute_precision=ct.precision.FLOAT16)
   ```

---

## Pattern 3 — Slow First Load (Cache Miss)

**Symptom**: First prediction after install/update is slow, subsequent are fast.

**Cause**: Device specialisation not cached. CoreML compiles the model for the specific hardware on first load.

**Diagnosis** (Instruments → Core ML template):
- "prepare and cache" = cache miss (slow)
- "cached" = cache hit (fast)

**Cache invalidated by**: system updates, low disk space, model file modification.

**Fix**: Warm cache at app launch:
```swift
Task.detached(priority: .background) {
    _ = try? await MLModel.load(contentsOf: modelURL)
}
```

Cache key = (model path + configuration + device). Different `computeUnits` = different cache entries.

---

## Pattern 4 — All Predictions Slow

**Symptom**: Predictions consistently slow, not just first one.

**Diagnosis**:
1. Create Xcode Performance Report — check compute unit distribution
2. Profile with MLComputePlan:
   ```swift
   let plan = try await MLComputePlan.load(contentsOf: modelURL)
   for op in plan.modelStructure.operations {
       let info = plan.computeDeviceInfo(for: op)
       print("\(op.name): \(info.preferredDevice)")
   }
   ```

**Common causes and fixes**:

| Cause | Fix |
|---|---|
| Running on CPU when GPU/NE available | Check `computeUnits` config isn't `.cpuOnly` |
| Model too large for Neural Engine | Compress model (Pattern 7) |
| Frequent CPU↔GPU↔NE data transfers | Adjust compute unit config to reduce transfers |
| Dynamic shapes recompiling | Use fixed or enumerated shapes |
| Missing deployment target | Re-convert with `minimum_deployment_target=ct.target.iOS18` |

---

## Pattern 5 — Slow on Specific Device

**Symptom**: Fast on Mac, slow on iPhone (or vice versa).

**Cause**: Different hardware — Mac GPU vs iPhone Neural Engine have different strengths.

| Scenario | Cause | Fix |
|---|---|---|
| Fast on M-series Mac, slow on iPhone | Model optimised for GPU | Use palettization (better for Neural Engine) |
| Fast on iPhone, slow on Intel Mac | No Neural Engine | Use quantization (better for GPU) |
| Slow on older devices | Less compute | More aggressive compression |

**Rule**: Always profile on target devices, not just development Mac.

---

## Pattern 6 — Memory Grows During Predictions

**Symptom**: Memory increases with each prediction, doesn't release.

**Cause**: Input/output buffers from concurrent predictions accumulating.

**Fix**: Limit concurrent predictions:
```swift
actor PredictionLimiter {
    private let maxConcurrent = 2
    private var inFlight = 0

    func predict(_ model: MLModel, input: MLFeatureProvider) async throws -> MLFeatureProvider {
        while inFlight >= maxConcurrent {
            await Task.yield()
        }
        inFlight += 1
        defer { inFlight -= 1 }
        return try await model.prediction(from: input)
    }
}
```

Also check: retained `MLMultiArray` references in tight loops. Use `autoreleasepool` if needed.

---

## Pattern 7 — Out of Memory on Load

**Symptom**: App crashes or model fails to load on memory-constrained devices.

**Fix progression** (try each, check accuracy after):

| Approach | Size Reduction | Memory Impact |
|---|---|---|
| 8-bit palettization | 2x | 2x less |
| 4-bit palettization (grouped) | 4x | 4x less |
| Pruning (50%) + palettization | ~4-8x | ~4-8x less |

Compressed weights are decompressed just-in-time, so smaller on-disk = smaller in memory.

---

## Pattern 8 — Bad Accuracy After Palettization

**Fix progression**:
1. Switch to `per_grouped_channel` granularity:
   ```python
   config = OpPalettizerConfig(nbits=4, granularity="per_grouped_channel", group_size=16)
   ```
2. If still bad, try more bits (6-bit or 8-bit)
3. If still need 4-bit, use calibration-based compression
4. Last resort: training-time compression (DKMPalettizer)

**Key insight**: 4-bit per-tensor = 16 clusters for entire weight matrix. Per-grouped-channel = 16 clusters per 16 channels = much better granularity.

---

## Pattern 9 — Bad Accuracy After Quantization

**Fix progression**:
1. Switch to per-block granularity:
   ```python
   config = OpLinearQuantizerConfig(dtype="int4", granularity="per_block", block_size=32)
   ```
2. Use calibration data via LayerwiseCompressor
3. INT4 quantization works best on Mac GPU. For Neural Engine, prefer palettization.

---

## Pattern 10 — Bad Accuracy After Pruning

**Sparsity thresholds** (model-dependent):
- 0-30%: Usually safe post-training
- 30-50%: May need calibration data
- 50%+: Usually needs training-time pruning

**Fix**: Use calibration-based pruning:
```python
from coremltools.optimize.torch.pruning import MagnitudePrunerConfig, LayerwiseCompressor
config = MagnitudePrunerConfig(target_sparsity=0.4, n_samples=128)
compressor = LayerwiseCompressor(model, config)
sparse = compressor.compress(calibration_loader)
```

---

## Pattern 11 — Outputs Differ Between Devices

**Cause**: GPU and Neural Engine produce slightly different floating-point results. This is expected.

**Fix**: Pin to `.cpuOnly` if exact reproducibility is required. Otherwise, accept small numerical differences.

---

## Pattern 12 — Conversion Fails (Unsupported Op)

**Options**:
1. Upgrade coremltools: `pip install --upgrade coremltools`
2. Decompose into supported primitives
3. Register a custom op (advanced, requires MIL programming)

---

## Pattern 13 — Conversion Succeeds but Wrong Output

**Checklist**:
1. **Input normalisation**: Ensure preprocessing matches PyTorch pipeline
2. **Shape ordering**: PyTorch (NCHW) vs CoreML (may differ for some ops)
3. **Precision**: Float16 may differ from Float32 — try `compute_precision=ct.precision.FLOAT32`
4. **Eval mode**: Ensure `model.eval()` before tracing (dropout, batch norm differ)

**Debug**:
```python
import numpy as np
torch_output = model(input).detach().numpy()
coreml_output = mlmodel.predict({"input": input.numpy()})["output"]
print(f"Max diff: {np.max(np.abs(torch_output - coreml_output))}")
```

---

## Pattern 14 — Works on Simulator, Not Device

**Cause**: Simulator uses host Mac's CPU/GPU, not device Neural Engine. Model may use ops unsupported on device hardware.

**Fix**: Always test on physical device. Check spec version (Pattern 1) and compute unit support (Pattern 2).

---

## Pressure Scenarios

### "Model is 5GB, need it under 2GB for iPhone"

**Wrong**: Jump straight to 2-bit palettization.
**Right**:
1. 8-bit palettization → check accuracy
2. 6-bit → check accuracy
3. 4-bit with `per_grouped_channel` → check accuracy
4. Still too large → calibration-based compression
5. Still losing accuracy → training-time compression

### "LLM inference is too slow"

**Wrong**: Try different compute units randomly.
**Right**:
1. Profile with Core ML Instrument
2. Check if load is cached (Pattern 3)
3. Enable stateful KV-cache
4. Verify SDPA optimisation enabled (set `minimum_deployment_target=ct.target.iOS18`)
5. Consider INT4 quantization for GPU

### "Ship now, optimise later"

**Wrong**: Compress to smallest possible size without testing.
**Right**:
1. Ship Float16 baseline first
2. Profile on target devices
3. Apply compression incrementally with accuracy testing
4. Document compression settings for future optimisation

---

## Profiling with MLComputePlan

```swift
let plan = try await MLComputePlan.load(contentsOf: modelURL)

for op in plan.modelStructure.operations {
    let info = plan.computeDeviceInfo(for: op)
    print("\(op.name): preferred=\(info.preferredDevice), cost=\(info.estimatedCost)")
}
```

Use to identify operations falling back to CPU when you expect Neural Engine execution, or to find bottleneck operations in multi-model pipelines.

### Core ML Instrument

```
Instruments → Core ML template
  ├─ Load events: "cached" vs "prepare and cache"
  ├─ Prediction intervals
  ├─ Compute unit usage
  └─ Neural Engine activity
```
