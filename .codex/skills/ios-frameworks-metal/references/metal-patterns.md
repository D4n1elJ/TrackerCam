# Metal -- Patterns & API Reference

Complete reference for Metal render pipelines, compute pipelines, resource management, Metal Shading Language, MetalKit, MPS, SwiftUI integration, and debugging. All examples target iOS 26+.

---

## Core Object Model

Metal's API follows a strict hierarchy. Understanding ownership and lifetime is essential.

```
MTLDevice (GPU)
 +-- MTLCommandQueue (serial submission point)
      +-- MTLCommandBuffer (one per frame or dispatch)
           +-- MTLRenderCommandEncoder (draw calls)
           +-- MTLComputeCommandEncoder (compute dispatches)
           +-- MTLBlitCommandEncoder (copy/fill operations)
```

### MTLDevice

The GPU itself. Obtain once, hold forever.

```swift
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal is not supported on this device")
}
```

On iOS there is exactly one GPU, so this always returns the same object. Never call `MTLCreateSystemDefaultDevice()` more than once -- store the result.

### MTLCommandQueue

Serial submission point for command buffers. Thread-safe. Create one at init.

```swift
let commandQueue = device.makeCommandQueue()!
```

For independent workloads (e.g., rendering + async compute), you can create separate queues, but one is sufficient for most apps.

### MTLCommandBuffer

Transient container for encoded GPU work. Create per frame, do not reuse.

```swift
guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

// Encode work...

commandBuffer.present(drawable)
commandBuffer.commit()
```

**Completion handling:**

```swift
commandBuffer.addCompletedHandler { buffer in
    if let error = buffer.error {
        print("GPU error: \(error)")
    }
    // Signal semaphore, read back results, etc.
}
```

### MTLLibrary

Container for compiled shader functions. Load from the default library (compiled from `.metal` files in your target) or from source at runtime.

```swift
// From precompiled .metal files in the app bundle
let library = device.makeDefaultLibrary()!

// From source string (slow -- avoid in production)
let library = try device.makeLibrary(source: shaderSource, options: nil)
```

---

## Render Pipeline

### Pipeline Descriptor and State

The descriptor configures which shaders run and the pixel format of the output. The state object is the compiled, immutable GPU program.

```swift
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: "vertexShader")
descriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

// Enable alpha blending
descriptor.colorAttachments[0].isBlendingEnabled = true
descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

// Depth
descriptor.depthAttachmentPixelFormat = .depth32Float

let pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
```

**Rule**: Compile pipeline states at initialization. Each call to `makeRenderPipelineState` triggers shader compilation -- it takes milliseconds to seconds. Never do it per frame.

### Vertex Descriptor

Maps CPU vertex data layout to shader inputs.

```swift
let vertexDescriptor = MTLVertexDescriptor()

// Position: float3 at offset 0
vertexDescriptor.attributes[0].format = .float3
vertexDescriptor.attributes[0].offset = 0
vertexDescriptor.attributes[0].bufferIndex = 0

// Color: float4 at offset 12
vertexDescriptor.attributes[1].format = .float4
vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
vertexDescriptor.attributes[1].bufferIndex = 0

// Layout
vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
vertexDescriptor.layouts[0].stepFunction = .perVertex

descriptor.vertexDescriptor = vertexDescriptor
```

### Render Pass

A render pass describes what to render into (color/depth/stencil attachments) and how to initialize them.

```swift
// MTKView provides a default render pass descriptor
guard let passDescriptor = view.currentRenderPassDescriptor else { return }

// Or build manually:
let passDescriptor = MTLRenderPassDescriptor()
passDescriptor.colorAttachments[0].texture = targetTexture
passDescriptor.colorAttachments[0].loadAction = .clear
passDescriptor.colorAttachments[0].storeAction = .store
passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
```

**Load actions**:
- `.clear` -- fill with clear color (use when rendering a full frame)
- `.load` -- preserve existing contents (use when drawing over previous pass)
- `.dontCare` -- undefined contents (use when you will overwrite every pixel)

### Drawing

```swift
let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
encoder.setRenderPipelineState(pipelineState)
encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
encoder.setFragmentTexture(texture, index: 0)
encoder.setFragmentSamplerState(sampler, index: 0)

// Non-indexed
encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)

// Indexed
encoder.drawIndexedPrimitives(
    type: .triangle,
    indexCount: indexCount,
    indexType: .uint16,
    indexBuffer: indexBuffer,
    indexBufferOffset: 0
)

encoder.endEncoding()
```

### Depth and Stencil

```swift
let depthDescriptor = MTLDepthStencilDescriptor()
depthDescriptor.depthCompareFunction = .less
depthDescriptor.isDepthWriteEnabled = true
let depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!

// In draw loop:
encoder.setDepthStencilState(depthState)
```

---

## Compute Pipeline

### Setup

```swift
let kernelFunction = library.makeFunction(name: "myKernel")!
let computePipeline = try device.makeComputePipelineState(function: kernelFunction)
```

### Dispatching Threads

Two dispatch modes:

**`dispatchThreads` (preferred)** -- Metal handles non-uniform grid sizes automatically.

```swift
let encoder = commandBuffer.makeComputeCommandEncoder()!
encoder.setComputePipelineState(computePipeline)
encoder.setBuffer(dataBuffer, offset: 0, index: 0)

let gridSize = MTLSize(width: totalElements, height: 1, depth: 1)
let threadgroupSize = MTLSize(
    width: min(computePipeline.maxTotalThreadsPerThreadgroup, totalElements),
    height: 1, depth: 1
)
encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
encoder.endEncoding()
```

**`dispatchThreadgroups`** -- you compute the grid of threadgroups yourself.

```swift
let threadgroupCount = MTLSize(
    width: (totalElements + threadgroupSize.width - 1) / threadgroupSize.width,
    height: 1, depth: 1
)
encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
```

### Threadgroup Sizing Guidelines

- Query `computePipeline.maxTotalThreadsPerThreadgroup` -- it varies by shader register usage
- Common values: 256, 512, or 1024 threads per threadgroup
- For 2D work (images): use square-ish threadgroups like `MTLSize(width: 16, height: 16, depth: 1)` = 256 threads
- For 1D work: use `MTLSize(width: 256, height: 1, depth: 1)`
- Threadgroup memory is shared within the group -- use for reductions and prefix sums

---

## Buffers and Resource Management

### Creating Buffers

```swift
// From data
let buffer = device.makeBuffer(bytes: &vertices, length: byteLength, options: .storageModeShared)!

// Empty, writable
let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared)!
```

### Storage Modes (iOS)

| Mode | CPU Access | GPU Access | Use Case |
|---|---|---|---|
| `.storageModeShared` | Read/Write | Read/Write | Default for iOS; unified memory |
| `.storageModePrivate` | None | Read/Write | GPU-only textures, render targets |
| `.storageModeMemoryless` | None | Tile memory only | Transient render targets (TBDR optimization) |

On iOS, `.storageModeShared` is the workhorse. The CPU and GPU share the same physical memory. No explicit synchronization is needed beyond ensuring the GPU has finished before reading back.

### Triple Buffering

Prevents CPU and GPU from fighting over the same buffer. The standard pattern for dynamic per-frame data.

```swift
let maxFramesInFlight = 3
let inflightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
var currentBufferIndex = 0
var uniformBuffers: [MTLBuffer] = []

// At init: create 3 buffers
for _ in 0..<maxFramesInFlight {
    uniformBuffers.append(device.makeBuffer(length: uniformSize, options: .storageModeShared)!)
}

// Each frame:
func draw(in view: MTKView) {
    inflightSemaphore.wait()

    let bufferIndex = currentBufferIndex
    currentBufferIndex = (currentBufferIndex + 1) % maxFramesInFlight

    // Update uniforms on CPU -- safe because GPU is not using this buffer
    let uniforms = uniformBuffers[bufferIndex].contents().bindMemory(to: Uniforms.self, capacity: 1)
    uniforms.pointee = currentUniforms

    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

    commandBuffer.addCompletedHandler { [weak self] _ in
        self?.inflightSemaphore.signal()
    }

    // Encode draws using uniformBuffers[bufferIndex]...

    commandBuffer.present(view.currentDrawable!)
    commandBuffer.commit()
}
```

### Shared Structs Between Swift and MSL

Define a shared header or mirror the struct exactly.

```swift
// Swift side
struct Uniforms {
    var modelViewProjection: simd_float4x4
    var normalMatrix: simd_float3x3
    var lightPosition: SIMD3<Float>
    var padding: Float = 0 // Align to 16 bytes
}
```

```metal
// MSL side
struct Uniforms {
    float4x4 modelViewProjection;
    float3x3 normalMatrix;
    float3 lightPosition;
    float padding;
};
```

**Alignment rule**: Metal requires struct members to be aligned to their natural size. `float3` is 16-byte aligned in Metal. Use `simd` types on the Swift side to match.

---

## Textures and Samplers

### Creating Textures

```swift
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba8Unorm,
    width: 512,
    height: 512,
    mipmapped: true
)
descriptor.usage = [.shaderRead, .renderTarget]
let texture = device.makeTexture(descriptor: descriptor)!
```

### Loading Textures with MTKTextureLoader

```swift
import MetalKit

let textureLoader = MTKTextureLoader(device: device)

// From asset catalog
let texture = try textureLoader.newTexture(name: "myTexture", scaleFactor: 1.0, bundle: nil)

// From URL
let texture = try textureLoader.newTexture(URL: imageURL)

// With options
let options: [MTKTextureLoader.Option: Any] = [
    .textureUsage: MTLTextureUsage.shaderRead.rawValue,
    .textureStorageMode: MTLStorageMode.private.rawValue,
    .generateMipmaps: true
]
let texture = try textureLoader.newTexture(name: "myTexture", scaleFactor: 1.0, bundle: nil, options: options)
```

### Samplers

```swift
let samplerDescriptor = MTLSamplerDescriptor()
samplerDescriptor.minFilter = .linear
samplerDescriptor.magFilter = .linear
samplerDescriptor.mipFilter = .linear
samplerDescriptor.sAddressMode = .repeat
samplerDescriptor.tAddressMode = .repeat
let sampler = device.makeSamplerState(descriptor: samplerDescriptor)!

// In encoder:
encoder.setFragmentSamplerState(sampler, index: 0)
```

---

## Metal Shading Language (MSL) Basics

MSL is a C++14-based language. Shaders are compiled from `.metal` files added to your Xcode target.

### Vertex and Fragment Shader

```metal
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertexShader(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position = uniforms.modelViewProjection * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
    return in.color;
}
```

### Compute Kernel

```metal
kernel void addArrays(
    device const float *a [[buffer(0)]],
    device const float *b [[buffer(1)]],
    device float *result   [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    result[id] = a[id] + b[id];
}
```

### Texture Sampling in Shader

```metal
fragment float4 texturedFragment(
    VertexOut in [[stage_in]],
    texture2d<float> colorTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    return colorTexture.sample(textureSampler, in.texCoord);
}
```

### Key MSL Qualifiers

| Qualifier | Meaning |
|---|---|
| `[[position]]` | Clip-space vertex output |
| `[[stage_in]]` | Interpolated per-vertex data in fragment shader |
| `[[buffer(n)]]` | Buffer binding at index n |
| `[[texture(n)]]` | Texture binding at index n |
| `[[sampler(n)]]` | Sampler binding at index n |
| `[[thread_position_in_grid]]` | Global thread ID in compute |
| `[[thread_position_in_threadgroup]]` | Local thread ID within threadgroup |
| `[[threadgroup_position_in_grid]]` | Threadgroup ID |
| `[[threads_per_threadgroup]]` | Threadgroup dimensions |
| `device` | Device address space (read/write, global) |
| `constant` | Constant address space (read-only, optimized) |
| `threadgroup` | Shared memory within threadgroup |
| `thread` | Per-thread private memory |

### Common MSL Types

| MSL Type | Swift Equivalent |
|---|---|
| `float2`, `float3`, `float4` | `SIMD2<Float>`, `SIMD3<Float>`, `SIMD4<Float>` |
| `float4x4` | `simd_float4x4` |
| `uint` | `UInt32` |
| `half` / `half4` | `Float16` (use for mobile perf) |
| `bool` | `Bool` |

**Performance tip**: Prefer `half` precision in fragment shaders on iOS. Apple GPUs have native half-precision ALUs that run twice as fast.

---

## MetalKit (MTKView)

`MTKView` is the standard view for Metal rendering. It handles the CAMetalLayer, drawable management, and frame timing.

### Configuration

```swift
let metalView = MTKView(frame: .zero, device: device)
metalView.colorPixelFormat = .bgra8Unorm
metalView.depthStencilPixelFormat = .depth32Float
metalView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
metalView.preferredFramesPerSecond = 60
metalView.isPaused = false
metalView.enableSetNeedsDisplay = false // Timer-driven rendering
```

**Frame modes**:
- Timer-driven (default): `isPaused = false`, `enableSetNeedsDisplay = false` -- renders continuously
- Event-driven: `isPaused = true`, `enableSetNeedsDisplay = true` -- renders only on `setNeedsDisplay()`

### MTKViewDelegate

```swift
final class Renderer: NSObject, MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Update projection matrix, resize depth texture, etc.
    }

    func draw(in view: MTKView) {
        // Encode and submit GPU work
    }
}
```

---

## Metal + SwiftUI Integration

### UIViewRepresentable Wrapper

```swift
struct MetalView: UIViewRepresentable {
    @Binding var rotation: Float

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        let renderer = Renderer(metalView: view)
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.rotation = rotation
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: Renderer?
    }
}
```

### On-Demand Rendering for SwiftUI

When Metal content only updates in response to SwiftUI state, use event-driven rendering to save battery.

```swift
func makeUIView(context: Context) -> MTKView {
    let view = MTKView()
    view.device = MTLCreateSystemDefaultDevice()
    view.isPaused = true
    view.enableSetNeedsDisplay = true
    // ...
    return view
}

func updateUIView(_ uiView: MTKView, context: Context) {
    context.coordinator.renderer?.updateState(rotation)
    uiView.setNeedsDisplay()
}
```

### LowLevelTexture and TextureResource (RealityKit Interop)

For feeding Metal-rendered textures into RealityKit entities:

```swift
let lowLevelTexture = try LowLevelTexture(descriptor: .init(
    pixelFormat: .bgra8Unorm,
    width: 1024, height: 1024,
    textureUsage: [.shaderRead, .renderTarget]
))

// Render into lowLevelTexture.replace(using:) in your Metal pipeline
// Then create a RealityKit TextureResource from it
let textureResource = try TextureResource(from: lowLevelTexture)
```

---

## Metal Performance Shaders (MPS)

MPS provides GPU-optimized implementations of common image processing, linear algebra, and neural network operations.

### Image Processing

```swift
import MetalPerformanceShaders

// Gaussian blur
let blur = MPSImageGaussianBlur(device: device, sigma: 5.0)
blur.encode(commandBuffer: commandBuffer, sourceTexture: inputTexture, destinationTexture: outputTexture)

// Image resize
let resize = MPSImageBilinearScale(device: device)
let transform = MPSScaleTransform(scaleX: 0.5, scaleY: 0.5, translateX: 0, translateY: 0)
withUnsafePointer(to: transform) { ptr in
    resize.scaleTransform = ptr
}
resize.encode(commandBuffer: commandBuffer, sourceTexture: inputTexture, destinationTexture: outputTexture)

// Sobel edge detection
let sobel = MPSImageSobel(device: device)
sobel.encode(commandBuffer: commandBuffer, sourceTexture: inputTexture, destinationTexture: outputTexture)
```

### Matrix Operations

```swift
let matMul = MPSMatrixMultiplication(
    device: device,
    transposeLeft: false,
    transposeRight: false,
    resultRows: m,
    resultColumns: n,
    interiorColumns: k,
    alpha: 1.0,
    beta: 0.0
)
matMul.encode(commandBuffer: commandBuffer, leftMatrix: matA, rightMatrix: matB, resultMatrix: matC)
```

### Histogram and Statistics

```swift
let histogram = MPSImageHistogram(device: device, histogramInfo: &histogramInfo)
histogram.encode(to: commandBuffer, sourceTexture: texture, histogram: histogramBuffer, histogramOffset: 0)
```

---

## GPU Debugging

### Xcode GPU Frame Capture

The single most important debugging tool for Metal. Captures an entire frame of GPU work for inspection.

**How to capture:**
1. Run the app from Xcode
2. Click the camera icon in the debug bar (or Debug > Capture GPU Frame)
3. Inspect draw calls, shader execution, buffer contents, and texture states

**What to look for:**
- Draw call count -- minimize by batching
- Texture bandwidth -- check for unnecessary load/store actions
- Shader execution time -- find hotspot instructions
- Buffer sizes and memory pressure

### Metal Validation Layer

Enabled automatically in Xcode debug builds. Catches API misuse at runtime. For extra checking:

Product > Scheme > Edit Scheme > Run > Diagnostics > GPU > Metal Validation (Enhanced)

### Shader Debugging

Xcode supports stepping through shaders:
1. Capture a GPU frame
2. Select a draw call
3. Click a pixel in the output
4. Step through the vertex/fragment shader for that pixel

### Common Debug Scenarios

| Symptom | Likely Cause | Fix |
|---|---|---|
| Black screen | No draw calls encoded, wrong clear color, missing `present()` | Check encoder setup and `commandBuffer.present(drawable)` |
| Flickering | Writing and reading same buffer without sync | Triple buffer or add `waitUntilCompleted()` |
| Garbage pixels | Uninitialized texture, wrong load action | Set `.loadAction = .clear` or initialize texture |
| Crash in shader | Buffer overrun, null texture | Check buffer sizes, validate bindings |
| Low FPS | Shader too complex, too many draw calls | Profile with GPU Frame Capture, batch draws |
| Validation error on `endEncoding` | Mismatched encoder lifecycle | Every encoder must have exactly one `endEncoding()` |

---

## Migration from OpenGL ES

OpenGL ES is fully deprecated. Metal is the replacement. These tables are also useful when adapting GLSL shader snippets found online.

### Concept Mapping

| OpenGL ES | Metal |
|---|---|
| `EAGLContext` | `MTLDevice` |
| `glCreateProgram` + `glLinkProgram` | `MTLRenderPipelineState` |
| `glCreateShader` (GLSL) | `.metal` file (MSL) |
| `glGenBuffers` + `glBindBuffer` | `device.makeBuffer()` |
| `glGenTextures` + `glBindTexture` | `device.makeTexture()` |
| `glDrawArrays` / `glDrawElements` | `encoder.drawPrimitives()` / `encoder.drawIndexedPrimitives()` |
| `glUniform*` | `encoder.setVertexBytes()` or buffer binding |
| FBO | `MTLRenderPassDescriptor` |
| `glViewport` | `encoder.setViewport()` |
| `glEnable(GL_BLEND)` | `MTLRenderPipelineDescriptor.colorAttachments[0].isBlendingEnabled` |
| VAO | `MTLVertexDescriptor` |
| `glFinish` | `commandBuffer.waitUntilCompleted()` |

### Key Differences

- **No global state**: Metal is object-based. Everything is explicit. No `glBind*` equivalents.
- **Precompiled shaders**: MSL compiles at build time, not runtime. Eliminates shader compilation stalls.
- **Explicit command submission**: You build command buffers and commit them. No implicit flush.
- **Multi-threaded by design**: Command buffers and encoders can be created on any thread. OpenGL ES was single-threaded.
- **Tile-based deferred rendering (TBDR)**: iOS GPUs are TBDR. Metal exposes this via `memoryless` storage, load/store actions, and tile shaders. OpenGL ES hid this architecture.

### GLSL → MSL Type Mapping

| GLSL | MSL | Notes |
|---|---|---|
| `vec2` / `vec3` / `vec4` | `float2` / `float3` / `float4` | |
| `ivec2` / `ivec3` / `ivec4` | `int2` / `int3` / `int4` | |
| `uvec2` / `uvec3` / `uvec4` | `uint2` / `uint3` / `uint4` | |
| `bvec2` / `bvec3` / `bvec4` | `bool2` / `bool3` / `bool4` | |
| `mat2` / `mat3` / `mat4` | `float2x2` / `float3x3` / `float4x4` | |
| `mat2x3` / `mat3x4` | `float2x3` / `float3x4` | Columns x Rows |
| `double` | N/A | No 64-bit float in MSL; use `float` |
| `sampler2D` | `texture2d<float>` + `sampler` | Separate objects in MSL |
| `sampler3D` | `texture3d<float>` + `sampler` | |
| `samplerCube` | `texturecube<float>` + `sampler` | |
| `sampler2DArray` | `texture2d_array<float>` + `sampler` | |
| `sampler2DShadow` | `depth2d<float>` + `sampler` | |

### GLSL → MSL Built-in Variables

| GLSL | MSL | Stage |
|---|---|---|
| `gl_Position` | Return `[[position]]` | Vertex |
| `gl_PointSize` | Return `[[point_size]]` | Vertex |
| `gl_VertexID` | `[[vertex_id]]` parameter | Vertex |
| `gl_InstanceID` | `[[instance_id]]` parameter | Vertex |
| `gl_FragCoord` | `[[position]]` parameter | Fragment |
| `gl_FrontFacing` | `[[front_facing]]` parameter | Fragment |
| `gl_PointCoord` | `[[point_coord]]` parameter | Fragment |
| `gl_FragDepth` | Return `[[depth(any)]]` | Fragment |

### GLSL → MSL Function Mapping

| GLSL | MSL | Notes |
|---|---|---|
| `texture(sampler, uv)` | `tex.sample(sampler, uv)` | Method on texture object |
| `textureLod(sampler, uv, lod)` | `tex.sample(sampler, uv, level(lod))` | |
| `texelFetch(sampler, coord, lod)` | `tex.read(coord, lod)` | Integer coordinates |
| `textureSize(sampler, lod)` | `tex.get_width(lod)`, `tex.get_height(lod)` | Separate calls |
| `dFdx(v)` / `dFdy(v)` | `dfdx(v)` / `dfdy(v)` | |
| `mod(x, y)` | `fmod(x, y)` | Different name |
| `inversesqrt(x)` | `rsqrt(x)` | Different name |
| `atan(y, x)` | `atan2(y, x)` | Different name |
| `mix()` / `clamp()` / `smoothstep()` / `step()` / `fract()` | Same names | Identical |

### GLSL → MSL Precision Qualifiers

GLSL precision qualifiers have no direct MSL equivalent -- use explicit types:

| GLSL | MSL |
|---|---|
| `lowp float` / `mediump float` | `half` (16-bit) |
| `highp float` | `float` (32-bit) |
| `lowp int` / `mediump int` | `short` (16-bit) |
| `highp int` | `int` (32-bit) |

### GLSL → MSL Shader Structure

```glsl
// GLSL vertex shader
#version 300 es
layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec2 aTexCoord;
uniform mat4 uMVP;
out vec2 vTexCoord;
void main() {
    vTexCoord = aTexCoord;
    gl_Position = uMVP * vec4(aPosition, 1.0);
}
```

```metal
// Equivalent MSL vertex shader
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};
struct Uniforms { float4x4 mvp; };

vertex VertexOut vertexShader(VertexIn in [[stage_in]],
                              constant Uniforms &u [[buffer(1)]]) {
    VertexOut out;
    out.texCoord = in.texCoord;
    out.position = u.mvp * float4(in.position, 1.0);
    return out;
}
```

Key structural differences:
- GLSL globals → MSL function parameters with `[[attribute]]` qualifiers
- `uniform` → `constant T& [[buffer(N)]]` with explicit binding index
- `sampler2D` → separate `texture2d<float>` and `sampler` parameters
- `#version 300 es` → `#include <metal_stdlib>` + `using namespace metal;`
- MSL is stricter about implicit type conversions -- add explicit casts

### Buffer Alignment (Critical for Shared Structs)

GLSL/C allows `vec3` at 12 bytes with any alignment. MSL requires `float3` to be **16-byte aligned**. Use `simd` types in Swift for CPU-GPU shared structs:

```swift
struct Uniforms {
    var mvp: simd_float4x4           // 64 bytes, 16-byte aligned
    var cameraPosition: simd_float3  // 16-byte aligned (not 12!)
    var padding: Float = 0           // Explicit padding if needed
}
```

### Coordinate System Differences

| | OpenGL | Metal |
|---|---|---|
| Origin | Bottom-left | Top-left |
| Y-axis | Up | Down |
| NDC Z range | [-1, 1] | [0, 1] |
| Texture origin | Bottom-left | Top-left |

**Fixes**: Flip Y in vertex shader (`pos.y = -pos.y`), or flip texture UV (`uv.y = 1.0 - uv.y`), or use `MTKTextureLoader` with `.origin: .bottomLeft` to match GL convention.

---

## Display Performance

### CAMetalDisplayLink

For Metal apps needing precise timing control, `CAMetalDisplayLink` provides more control than CADisplayLink. It delivers the drawable directly in the callback and supports render latency control.

```swift
class MetalRenderer: NSObject, CAMetalDisplayLinkDelegate {
    var displayLink: CAMetalDisplayLink?
    var metalLayer: CAMetalLayer!

    func setupDisplayLink() {
        displayLink = CAMetalDisplayLink(metalLayer: metalLayer)
        displayLink?.delegate = self
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 120,
            preferred: 120
        )
        displayLink?.preferredFrameLatency = 2
        displayLink?.add(to: .main, forMode: .common)
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard let drawable = update.drawable else { return }

        let workingTime = update.targetTimestamp - CACurrentMediaTime()
        // workingTime = seconds available before deadline

        renderFrame(to: drawable)
    }
}
```

| Feature | CADisplayLink | CAMetalDisplayLink |
|---|---|---|
| Drawable access | Manual via layer | Provided in callback |
| Latency control | None | `preferredFrameLatency` |
| Target timing | timestamp/targetTimestamp | + targetPresentationTimestamp |
| Use case | General animation | Metal-specific rendering |

### GPU Frame Time Measurement

```swift
func draw(in view: MTKView) {
    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

    // Render...

    commandBuffer.addCompletedHandler { buffer in
        let gpuTime = buffer.gpuEndTime - buffer.gpuStartTime
        let gpuMs = gpuTime * 1000
        if gpuMs > 8.33 {
            // Exceeds 120Hz budget -- consider targeting 60fps
        }
    }

    commandBuffer.commit()
}
```

If you can't sustain 8.33ms, explicitly target 60fps for smooth cadence rather than fluctuating:

```swift
if averageGpuTime > 8.33 && averageGpuTime <= 16.67 {
    mtkView.preferredFramesPerSecond = 60
}
```

### Frame Pacing

Even with good average FPS, inconsistent frame timing causes visible micro-stuttering. Presenting immediately after rendering causes uneven intervals.

**`present(afterMinimumDuration:)`** -- ensures consistent spacing between frames:

```swift
func draw(in view: MTKView) {
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let drawable = view.currentDrawable else { return }

    renderScene(to: drawable)

    // Lock to consistent 60fps cadence
    commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 60.0)
    commandBuffer.commit()
}
```

**`present(at:)`** -- schedule presentation at a specific time:

```swift
let presentTime = CACurrentMediaTime() + 0.033
commandBuffer.present(drawable, atTime: presentTime)
```

### Frame Drop Detection

Use `addPresentedHandler` to verify frames actually reached the display:

```swift
drawable.addPresentedHandler { drawable in
    if drawable.presentedTime == 0.0 {
        // Frame was dropped
    }
}
```

### Hitch Mechanics

A **hitch** is a frame that misses its deadline and stays onscreen longer than intended (1-3 frames, 16-50ms). Different from a hang (>1 second).

**Commit hitch**: App process misses the Core Animation commit deadline.
- Cause: Too much main thread work before commit
- Fix: Move work off main thread, reduce view complexity

**Render hitch**: Render server misses the presentation deadline.
- Cause: GPU work too complex (blur, shadows, overdraw)
- Fix: Simplify visual effects, reduce layer count

The system uses double buffering by default (2 vsync frame lifetime). It automatically switches to triple buffering (3 vsync, higher latency but more headroom) to recover from render hitches.

```
Hitch Duration = Actual Frame Lifetime - Expected Frame Lifetime
```

### MetricKit Animation Telemetry

Monitor hitches in production:

```swift
import MetricKit

class MetricsManager: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let animationMetrics = payload.animationMetrics {
                let scrollHitchRatio = animationMetrics.scrollHitchTimeRatio
                let hitchRatio = animationMetrics.hitchTimeRatio
            }
        }
    }
}

// Register at launch:
MXMetricManager.shared.add(metricsManager)
```

- `scrollHitchTimeRatio`: fraction of time spent hitching during scrolls (UIScrollView only)
- `hitchTimeRatio`: fraction of time spent hitching across all tracked animations

---

## Advanced Patterns

### Indirect Command Buffers

Let the GPU build its own draw calls, avoiding CPU round-trips.

```swift
let icbDescriptor = MTLIndirectCommandBufferDescriptor()
icbDescriptor.commandTypes = .draw
icbDescriptor.maxVertexBufferBindCount = 1
icbDescriptor.maxFragmentBufferBindCount = 0

let icb = device.makeIndirectCommandBuffer(descriptor: icbDescriptor, maxCommandCount: 1024)!

// In compute shader: encode draw commands into the ICB
// In render pass:
encoder.executeCommandsInBuffer(icb, range: 0..<drawCount)
```

### Argument Buffers

Pack multiple resources into a single buffer binding, reducing API call overhead.

```swift
let argumentEncoder = pipelineState.makeArgumentEncoder(bufferIndex: 0)
let argumentBuffer = device.makeBuffer(length: argumentEncoder.encodedLength)!
argumentEncoder.setArgumentBuffer(argumentBuffer, offset: 0)
argumentEncoder.setTexture(albedoTexture, index: 0)
argumentEncoder.setTexture(normalTexture, index: 1)
argumentEncoder.setSamplerState(sampler, index: 2)

encoder.setFragmentBuffer(argumentBuffer, offset: 0, index: 0)
encoder.useResource(albedoTexture, usage: .read)
encoder.useResource(normalTexture, usage: .read)
```

### Render-to-Texture (Post-Processing)

```swift
// 1. Render scene to offscreen texture
let offscreenDescriptor = MTLRenderPassDescriptor()
offscreenDescriptor.colorAttachments[0].texture = offscreenTexture
offscreenDescriptor.colorAttachments[0].loadAction = .clear
offscreenDescriptor.colorAttachments[0].storeAction = .store

let sceneEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: offscreenDescriptor)!
// ... encode scene draws ...
sceneEncoder.endEncoding()

// 2. Full-screen pass reading offscreen texture, writing to drawable
let screenEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: view.currentRenderPassDescriptor!)!
screenEncoder.setRenderPipelineState(postProcessPipeline)
screenEncoder.setFragmentTexture(offscreenTexture, index: 0)
screenEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
screenEncoder.endEncoding()
```

### GPU-Driven Rendering with Mesh Shaders (iOS 16+)

Mesh shaders replace the traditional vertex-input-assembly pipeline with a more flexible compute-like model.

```swift
let meshDescriptor = MTLMeshRenderPipelineDescriptor()
meshDescriptor.objectFunction = library.makeFunction(name: "objectShader")
meshDescriptor.meshFunction = library.makeFunction(name: "meshShader")
meshDescriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
meshDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

let (meshPipeline, _) = try device.makeRenderPipelineState(descriptor: meshDescriptor, options: [])

// Draw with mesh:
encoder.setRenderPipelineState(meshPipeline)
encoder.drawMeshThreadgroups(
    MTLSize(width: meshletCount, height: 1, depth: 1),
    threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
    threadsPerMeshThreadgroup: MTLSize(width: 128, height: 1, depth: 1)
)
```

---

## Performance Checklist

| Area | Guideline |
|---|---|
| Pipeline states | Compile once at init; cache by configuration |
| Draw calls | Batch geometry; use instanced drawing for repeated objects |
| Buffers | Triple buffer dynamic data; use `storageModePrivate` for static GPU data |
| Textures | Use compressed formats (ASTC) for iOS; generate mipmaps |
| Shaders | Use `half` precision where possible; minimize branches |
| Load/Store | Set appropriate `loadAction` and `storeAction` to avoid unnecessary memory traffic |
| Memoryless | Use `.storageModeMemoryless` for transient render targets (MSAA, depth) |
| Threadgroups | Query `maxTotalThreadsPerThreadgroup`; use power-of-2 sizes |
| Profiling | GPU Frame Capture for every performance investigation -- never guess |
