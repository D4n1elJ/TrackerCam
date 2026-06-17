# GPU Debugging Workflow

Systematic workflow for diagnosing Metal performance issues and shader bugs. Use this when a Metal app renders incorrectly, runs slowly, or crashes on the GPU.

---

## GPU Frame Capture — Step by Step

The primary tool for all Metal debugging. Captures a single frame of GPU work for offline inspection.

### How to Capture

1. Run the app from Xcode (debug build)
2. Click the **camera icon** in the debug bar — or **Debug > Capture GPU Workload > Metal**
3. Wait for the capture to complete (1-3 seconds)
4. The GPU debugger opens automatically

### What to Inspect

| Panel | What to Look For |
|---|---|
| **Navigator (left)** | Full list of command buffers, render passes, compute dispatches, blit operations |
| **Bound Resources** | Buffers and textures bound to each draw call — verify correct data |
| **Shader Debugger** | Step through vertex/fragment/compute shaders per-pixel or per-thread |
| **Attachments** | View colour, depth, stencil textures at each render pass |
| **Performance** | Per-draw-call GPU time, shader instruction counts, occupancy |
| **Memory** | Texture and buffer allocations, storage modes, total GPU memory |
| **Dependencies** | Resource dependency graph — reveals unnecessary barriers or sync |

### Per-Pixel Shader Debugging

1. Capture a frame
2. Select a render pass in the navigator
3. Click a **specific pixel** in the colour attachment preview
4. Xcode opens the fragment shader with the exact values for that pixel
5. Step through line by line — inspect intermediate values

### Per-Thread Compute Debugging

1. Capture a frame
2. Select a compute dispatch
3. Click **Debug** on the shader function
4. Select a thread ID to inspect
5. Step through the kernel with that thread's values

---

## Metal Validation Layer

Catches API misuse at runtime. Enabled by default in Xcode debug builds.

### Levels

| Level | Setting | Catches |
|---|---|---|
| **Standard** | Default in debug | Missing `endEncoding()`, invalid buffer sizes, wrong pixel formats |
| **Enhanced** | Product > Scheme > Edit Scheme > Run > Diagnostics > GPU > Metal Validation | Resource hazards, uninitialized reads, out-of-bounds access |
| **Shader Validation** | Same panel > Shader Validation | Out-of-bounds buffer access in shaders, invalid texture reads |

**Rule**: Always develop with at least Standard validation. Enable Enhanced when debugging corruption or crashes.

### Common Validation Errors

| Error | Cause | Fix |
|---|---|---|
| `validateFunctionArguments` | Missing buffer/texture binding | Ensure every `[[buffer(n)]]` / `[[texture(n)]]` is set |
| `validateEndEncoding` | Forgot `endEncoding()` | Every encoder must end before another begins on the same buffer |
| `validateRenderPassDescriptor` | Nil texture on attachment | Check `currentDrawable` and render pass setup |
| `Hazard: Read-after-write` | GPU reads buffer that's still being written | Add a barrier or use separate buffers |

---

## Metal Command-Line Tools

Available in the Xcode toolchain. Useful for CI pipelines, scripted builds, and offline analysis.

### Compiler and Linker

```bash
# Compile .metal to .air (intermediate representation)
xcrun metal -c MyShader.metal -o MyShader.air

# Link .air files into a .metallib
xcrun metallib MyShader.air -o MyShader.metallib

# Compile with specific target and language version
xcrun metal -std=metal3.2 -target air64-apple-ios26.0 -c MyShader.metal -o MyShader.air

# Compile with warnings as errors
xcrun metal -Werror -c MyShader.metal -o MyShader.air
```

### Inspection

```bash
# Dump human-readable IR from .metallib
xcrun metal-objdump -d MyShader.metallib

# Show function list in a metallib
xcrun metal-objdump -t MyShader.metallib

# Disassemble to AIR
xcrun metal-source MyShader.metallib -o MyShader.air.txt
```

### Practical Uses

- **CI shader validation**: Compile all `.metal` files in CI to catch syntax errors before runtime
- **Offline metallib generation**: Precompile shader libraries for faster app launch
- **Shader analysis**: Inspect compiled output to understand register usage and instruction count

---

## Metal System Trace (Instruments)

For system-wide GPU analysis beyond a single frame.

### Setup

1. Open **Instruments** (Product > Profile or Cmd+I)
2. Choose the **Metal System Trace** template
3. Record for 5-10 seconds of representative workload
4. Analyse the timeline

### Key Tracks

| Track | Shows |
|---|---|
| **GPU** | Vertex, fragment, compute shader execution time |
| **Metal GPU Counters** | ALU utilisation, memory bandwidth, occupancy, cache hit rates |
| **Display** | VSync timing, frame presentation, dropped frames |
| **Metal Application** | API call duration on CPU side |
| **Shader Timeline** | Per-shader execution timeline on GPU |

### What to Look For

- **GPU idle gaps**: CPU is the bottleneck — optimise API call overhead or reduce draw calls
- **Long fragment shader bars**: Fragment-bound — simplify shaders, use `half` precision, reduce overdraw
- **Long vertex shader bars**: Vertex-bound — reduce vertex count, use mesh shaders or LOD
- **Memory bandwidth saturation**: Texture-bound — use compressed formats (ASTC), reduce texture size, check load/store actions

---

## Shader Profiler Metrics

Available in GPU Frame Capture after selecting a draw call or compute dispatch.

### Key Metrics

| Metric | Meaning | Target |
|---|---|---|
| **ALU Utilisation** | How busy the shader cores are | 80%+ is good |
| **Memory Bandwidth** | Bytes read/written per second | Minimise; use ASTC, `half`, appropriate load actions |
| **Occupancy** | Percentage of available threads running | Higher is better; register pressure reduces this |
| **Shader Instruction Count** | Total instructions per invocation | Fewer is faster; watch for loop-heavy shaders |
| **Overdraw** | How many times each pixel is written | 1x ideal; 2-3x acceptable; 4x+ investigate |
| **Texture Cache Hit Rate** | Percentage of texture fetches served from cache | 90%+ is good |

### Reading the Performance Heat Map

1. In GPU Frame Capture, select **Performance** in the bottom panel
2. Shader source is highlighted with per-line cost
3. **Red lines** are hot spots — focus optimisation here
4. Look for expensive operations: `pow`, `sin`/`cos`, texture fetches in loops, high iteration counts

---

## Symptom-Based Diagnostics

Start here when something is wrong. Find your symptom, follow the checks in order.

### Black Screen

**Time cost**: With GPU Frame Capture: 5-10 min. Without: 1-4 hours.

```
Black screen after setup
│
├─ Metal validation errors in console?
│   └─ YES → Fix validation errors first (they tell you exactly what's wrong)
│
├─ Render pass descriptor valid?
│   ├─ Check: view.currentRenderPassDescriptor != nil
│   ├─ Check: view.currentDrawable != nil
│   └─ FIX: Ensure MTKView.device is set and view is on screen
│
├─ Pipeline state created?
│   ├─ Check: makeRenderPipelineState doesn't throw
│   └─ FIX: Verify shader function names match .metal file exactly
│
├─ Draw calls being issued?
│   ├─ Add: encoder.label = "Main Pass" for frame capture
│   └─ DEBUG: GPU Frame Capture → verify draw calls appear
│
├─ Resources bound?
│   ├─ Check: setVertexBuffer, setFragmentTexture called
│   └─ FIX: Metal requires explicit binding every frame (no GL-style persistent state)
│
├─ Vertex data correct?
│   └─ DEBUG: GPU Frame Capture → inspect vertex buffer contents
│
├─ Coordinates in Metal's range?
│   ├─ Metal NDC: X [-1,1], Y [-1,1], Z [0,1]
│   ├─ OpenGL NDC: X [-1,1], Y [-1,1], Z [-1,1]
│   └─ FIX: Adjust projection matrix for Metal's Z range
│
└─ Clear color visible?
    ├─ Default is (0,0,0,0) — transparent black
    └─ FIX: Set view.clearColor or renderPassDescriptor.colorAttachments[0].clearColor
```

### Wrong Colours or Coordinates

**Time cost**: With GPU Frame Capture texture inspection: 5-10 min. Without: 1-2 hours.

```
Rendering looks wrong
│
├─ Image upside down
│   ├─ Cause: Metal Y-axis is opposite OpenGL
│   ├─ FIX (vertex): pos.y = -pos.y
│   ├─ FIX (texture load): MTKTextureLoader .origin: .bottomLeft
│   └─ FIX (UV): uv.y = 1.0 - uv.y in fragment shader
│
├─ Colours swapped (red/blue)
│   ├─ Cause: Pixel format mismatch
│   └─ FIX: Match .bgra8Unorm vs .rgba8Unorm to your data format
│
├─ Colours washed out / too bright
│   ├─ Cause: sRGB vs linear colour space
│   └─ FIX: Use _srgb format variants (.bgra8Unorm_srgb) for gamma-correct rendering
│
├─ Depth fighting / z-fighting
│   ├─ Cause: NDC Z range difference (GL [-1,1] vs Metal [0,1])
│   └─ FIX: Adjust projection matrix for Metal's Z range
│
└─ Transparency wrong
    ├─ Cause: Blend state not configured
    └─ FIX: pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
```

### Shader Compilation Errors

**Time cost**: With conversion table: 2-5 min per shader. Without: 15-30 min per shader.

| Error Message | Cause | Fix |
|---|---|---|
| "Use of undeclared identifier" | Missing stdlib | Add `#include <metal_stdlib>` and `using namespace metal;` |
| "No matching function for call to 'texture'" | GLSL texture() syntax | Use `tex.sample(sampler, uv)` — texture sampling is a method |
| "Invalid type 'vec4'" | GLSL types | `vec4` → `float4`, `mat4` → `float4x4` — see migration tables in `metal-patterns.md` |
| "Attribute index out of range" | Vertex descriptor mismatch | `[[attribute(N)]]` must match `vertexDescriptor.attributes[N]` |
| "Cannot convert value of type" | Implicit conversion | MSL is stricter than GLSL — add explicit casts: `float(intValue)` |

### Performance Regression

**Time cost**: Metal System Trace diagnosis: 15-30 min. Guessing without tools: hours.

```
Performance worse than expected
│
├─ Validation enabled?
│   └─ Adds ~30% overhead — disable for release profiling
│
├─ Creating resources every frame?
│   ├─ BAD: device.makeBuffer() in draw()
│   └─ FIX: Create buffers once, reuse with triple buffering
│
├─ Creating pipeline state every frame?
│   ├─ BAD: makeRenderPipelineState() in draw()
│   └─ FIX: Create PSO once at init, store as property
│
├─ GPU-CPU sync stalls?
│   ├─ DEBUG: Metal System Trace → look for idle gaps
│   ├─ Cause: waitUntilCompleted() blocks CPU
│   └─ FIX: Triple buffering with DispatchSemaphore(value: 3)
│
├─ Wrong storage mode?
│   ├─ .shared: Good for small dynamic data (uniforms)
│   ├─ .private: Good for static GPU-only data (geometry, textures)
│   └─ .memoryless: Good for transient render targets (MSAA, depth)
│
└─ Too many draw calls?
    ├─ DEBUG: GPU Frame Capture → count draw calls
    └─ FIX: Batch geometry, use instancing, sort by pipeline state
```

### Crashes During GPU Work

**Time cost**: With validation + Frame Capture: 10-15 min. Without: hours.

| Crash | Cause | Fix |
|---|---|---|
| EXC_BAD_ACCESS in Metal | Accessing released resource | Keep strong references until command buffer completes |
| "Command buffer execution aborted" | GPU timeout (>10 sec on iOS) | Check for infinite loops in shaders |
| Debug validation assertion | API misuse | Read the full message — it says exactly what's wrong |
| SIGABRT in shader | Out-of-bounds buffer access | Enable Shader Validation, check array bounds |

### Flickering / Corruption

**Time cost**: With Frame Capture: 5-10 min. Without: 1-2 hours.

```
Visual artefacts
│
├─ Flickering between frames
│   ├─ Cause: CPU/GPU race on shared buffer
│   └─ FIX: Triple buffering with semaphore
│
├─ Garbage pixels in regions
│   ├─ Cause: Uninitialised texture or wrong load action
│   └─ FIX: Set loadAction = .clear, or initialise texture data
│
└─ Depth artefacts
    ├─ Cause: Missing or misconfigured depth state
    └─ FIX: Verify depthStencilPixelFormat matches between view and pipeline
```

### Mandatory First Step

Before any GPU debugging, verify validation is enabled:

```
Xcode → Edit Scheme → Run → Diagnostics
✓ Metal API Validation
✓ Metal Shader Validation
✓ GPU Frame Capture (Metal)
```

**Time cost**: 30 seconds setup vs hours of blind debugging. Most Metal bugs produce clear validation errors — if you're debugging without validation enabled, stop and enable it first.

---

## Performance Optimisation Checklist

| Area | Action | Priority |
|---|---|---|
| Draw calls | Batch geometry, use instanced drawing | High |
| Pipeline switches | Sort draws by pipeline state to minimise switches | High |
| `half` precision | Use in fragment shaders for colour, UV, normals | High |
| Load/Store actions | Set `.dontCare` for transient attachments, `.clear` only when needed | High |
| Memoryless | Use `.storageModeMemoryless` for MSAA resolve targets and transient depth | Medium |
| Texture formats | ASTC compression for all non-generated textures | Medium |
| Mipmaps | Generate for any texture sampled at varying distances | Medium |
| Buffer alignment | Align uniform buffers to 256 bytes for optimal GPU cache | Medium |
| Shader branches | Minimise divergent branches within a threadgroup/SIMD group | Medium |
| Precompiled pipelines | Use `MTLBinaryArchive` to avoid runtime compilation stalls | Low |
| Indirect command buffers | For GPU-driven rendering with many small draws | Low |
