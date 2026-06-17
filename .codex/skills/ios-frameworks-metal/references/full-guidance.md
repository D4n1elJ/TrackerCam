# Metal Quick Reference

## Purpose

Opinionated guide for choosing when to use Metal, structuring render and compute pipelines, and avoiding common GPU programming mistakes. iOS 26+ only -- no `@available` checks needed.

## How to Use

1. **Decide if Metal is the right tool** using the decision tree below
2. **Pick the pipeline type** (render vs compute)
3. **Follow the setup checklist** for your pipeline
4. **Check anti-patterns** before shipping
5. **For full API details**, read `references/metal-patterns.md`

## Decision Tree: Metal vs Higher-Level Frameworks

```
Need custom GPU shaders or compute?           -> Metal
Need real-time 3D with physics/animation?     -> SceneKit (uses Metal underneath)
Need AR content or entity-component 3D?       -> RealityKit (uses Metal underneath)
Need 2D sprite-based games?                   -> SpriteKit (uses Metal underneath)
Need image filters only?                      -> Core Image (GPU-accelerated, no Metal code)
Need ML inference on GPU?                     -> Core ML or MPS (Metal Performance Shaders)
Need video compositing/effects?               -> AVFoundation + Core Image first, Metal for custom
```

| Framework | Use When | Metal Needed? |
|---|---|---|
| Core Image | Standard filters, chains, CIKernel for custom | Only for custom CIKernel |
| SpriteKit | 2D games, particle effects | Only for custom SKShader |
| SceneKit | 3D scenes, PBR materials | Only for custom SCNProgram |
| RealityKit | AR, entity-component architecture | Only for CustomMaterial shaders |
| Core ML | ML model inference | No -- uses Metal internally |
| Metal | Custom rendering, GPGPU compute, full control | Yes -- you write it |

## Pipeline Setup Checklist

### Render Pipeline

1. Obtain `MTLDevice` (singleton per GPU)
2. Create `MTLCommandQueue` (one per app, reuse it)
3. Load shader library (`device.makeDefaultLibrary()`)
4. Build `MTLRenderPipelineDescriptor` with vertex + fragment functions
5. Create `MTLRenderPipelineState` (compile once, reuse forever)
6. Each frame: command buffer -> render command encoder -> draw calls -> end encoding -> commit

### Compute Pipeline

1. Obtain `MTLDevice`
2. Create `MTLCommandQueue`
3. Load kernel function from library
4. Create `MTLComputePipelineState`
5. Each dispatch: command buffer -> compute command encoder -> set buffers/textures -> dispatch threads -> end encoding -> commit

## Anti-Patterns

| Mistake | Fix |
|---|---|
| Creating `MTLDevice` per frame | Create once at init, store as property |
| Creating pipeline state per frame | Compile pipeline state once, reuse |
| Blocking main thread on GPU work | Use `addCompletedHandler` or `waitUntilCompleted` on background queue |
| Single buffer for CPU+GPU writes | Use triple buffering with semaphore |
| Forgetting `endEncoding()` before commit | Always call `endEncoding()` on every encoder before `commit()` |
| Large shader compilations at runtime | Use `MTLBinaryArchive` or precompile pipelines at build time |
| Ignoring `maxTotalThreadsPerThreadgroup` | Query pipeline state for actual limit; varies by GPU |
| Using `Float` uniforms without alignment | Metal requires 16-byte alignment for `float4`; use `simd_float4` |
| Allocating textures every frame | Create texture pool or reuse with `MTLTextureDescriptor` |
| Not profiling with GPU Frame Capture | Always profile -- GPU bottlenecks are invisible without tools |

## Display Performance & ProMotion

**Key insight**: "ProMotion available" does NOT mean your app automatically runs at 120Hz. You must configure it correctly, account for system caps, and ensure proper frame pacing.

### Stuck at 60fps? Diagnostic Triage Order

Check in this order:

1. **Info.plist key missing?** (iPhone only) -- see below
2. **Render loop configured for 60?** (MTKView defaults, CADisplayLink) -- see below
3. **System caps enabled?** (Low Power Mode, Limit Frame Rate, Thermal) -- see below
4. **Frame time > 8.33ms?** (Can't sustain 120fps) -- see Frame Budget
5. **Frame pacing issues?** (Micro-stuttering despite good FPS) -- see `references/metal-patterns.md` Frame Pacing section
6. **Measuring wrong thing?** (`UIScreen` reports capability, not actual rate)

### Enabling ProMotion on iPhone (Info.plist)

Core Animation won't access frame rates above 60Hz on iPhone unless you add this key. iPad Pro does NOT require it.

```xml
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
```

Without this key, `preferredFrameRateRange` hints above 60Hz are silently ignored on iPhone.

### MTKView Configuration

```swift
let metalView = MTKView(frame: frame, device: device)
metalView.preferredFramesPerSecond = 120
metalView.isPaused = false                // Don't pause the render loop
metalView.enableSetNeedsDisplay = false   // Continuous mode, not on-demand
metalView.delegate = self
```

All three properties matter for continuous high-rate rendering. Missing `isPaused = false` or `enableSetNeedsDisplay = false` can silently throttle your frame rate.

### CADisplayLink

For custom render loops outside MTKView, use `preferredFrameRateRange`:

```swift
let displayLink = CADisplayLink(target: self, selector: #selector(render))
displayLink.preferredFrameRateRange = CAFrameRateRange(
    minimum: 80,
    maximum: 120,
    preferred: 120
)
displayLink.add(to: .main, forMode: .common)
```

Note: 30Hz and 60Hz get special priority scheduling from iOS. For Metal apps, prefer `CAMetalDisplayLink` -- see `references/metal-patterns.md`.

### Frame Budget

| Target FPS | Budget per Frame | Vsync Interval |
|---|---|---|
| 120 Hz | 8.33 ms | Every vsync |
| 60 Hz | 16.67 ms | Every 2nd vsync |
| 30 Hz | 33.33 ms | Every 4th vsync |

If you consistently exceed budget, the system drops to the next sustainable rate. **Uneven frame pacing looks worse than a consistent lower rate.** Use `present(afterMinimumDuration:)` to lock cadence -- see `references/metal-patterns.md` Frame Pacing section.

### System Frame Rate Caps

The system can silently cap your frame rate. Check these when frames drop:

| Cap | Detection | Fix |
|---|---|---|
| Low Power Mode | `ProcessInfo.processInfo.isLowPowerModeEnabled` | Observe `.NSProcessInfoPowerStateDidChange` and reduce target |
| Limit Frame Rate (Accessibility) | No API to detect | Have user check Settings > Accessibility > Motion |
| Thermal throttling | `ProcessInfo.processInfo.thermalState` | Observe `thermalStateDidChangeNotification`; drop to 60fps at `.serious` |
| Adaptive Power (iOS 26) | No API to detect | User: Settings > Battery > Power Mode > disable Adaptive Power |

### Metal Performance HUD

Quick on-device frame rate overlay without Instruments:

- **Xcode scheme**: Edit Scheme > Run > Diagnostics > Show Graphics Overview
- **Environment variable**: `MTL_HUD_ENABLED=1`
- **Device settings**: Settings > Developer > Graphics HUD > Show Graphics HUD

Shows FPS, GPU time per frame, frame interval chart, and memory usage.

### Measuring Actual Frame Rate

`UIScreen.maximumFramesPerSecond` reports hardware capability, not achieved rate.

```swift
@objc func displayLinkCallback(_ link: CADisplayLink) {
    if lastTimestamp > 0 {
        let interval = link.timestamp - lastTimestamp
        let actualFPS = 1.0 / interval
    }
    lastTimestamp = link.timestamp
}
```

For GPU frame time measurement, frame pacing, frame drop detection, hitch mechanics, CAMetalDisplayLink, and MetricKit animation telemetry, see `references/metal-patterns.md` Display Performance section.

## Anti-Rationalization

| Thought | Reality |
|---|---|
| "I don't need to set preferredFramesPerSecond" | MTKView defaults to 60fps. ProMotion won't activate without explicit opt-in. |
| "I don't need the Info.plist key" | On iPhone, Core Animation silently caps at 60Hz without `CADisableMinimumFrameDurationOnPhone`. |
| "I'll just use a Timer for my render loop" | Timer has no display synchronisation. Use CADisplayLink or MTKView delegate. |
| "My frame rate is fine, I checked UIScreen" | `UIScreen.maximumFramesPerSecond` reports capability, not actual rate. Measure from CADisplayLink or drawable presentation. |
| "GPU Frame Capture is overkill for this" | GPU bottlenecks are invisible without tools. 5 min in Frame Capture beats 30 min guessing. |
| "I'll create the pipeline state when I need it" | Pipeline compilation stalls the GPU. Compile at init, reuse forever. |
| "Core Image can do this custom effect" | If you need per-pixel control or compute, Metal is the right tool. Don't fight CIKernel limitations. |
| "I'll profile on Simulator" | Simulator uses CPU rendering. GPU performance data requires a physical device. |

## Common Patterns

### Minimal Render Setup

```swift
import MetalKit

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState

    init(metalView: MTKView) {
        device = metalView.device!
        commandQueue = device.makeCommandQueue()!

        let library = device.makeDefaultLibrary()!
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineState = try! device.makeRenderPipelineState(descriptor: descriptor)

        super.init()
        metalView.delegate = self
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
```

### Metal + SwiftUI

```swift
struct MetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.coordinator.renderer = Renderer(metalView: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: Renderer?
    }
}
```

### Compute Dispatch

```swift
let buffer = commandQueue.makeCommandBuffer()!
let encoder = buffer.makeComputeCommandEncoder()!
encoder.setComputePipelineState(computePipeline)
encoder.setBuffer(inputBuffer, offset: 0, index: 0)
encoder.setBuffer(outputBuffer, offset: 0, index: 1)

let gridSize = MTLSize(width: elementCount, height: 1, depth: 1)
let threadgroupSize = MTLSize(
    width: min(computePipeline.maxTotalThreadsPerThreadgroup, elementCount),
    height: 1, depth: 1
)
encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
encoder.endEncoding()
buffer.commit()
```

## Full Reference

| Document | Covers |
|---|---|
| `references/metal-patterns.md` | Pipeline configuration, buffer management, triple buffering, MSL basics, MPS, textures, debugging, display performance (CAMetalDisplayLink, frame pacing, hitch mechanics, MetricKit), OpenGL ES migration, advanced patterns |
| `references/shader-techniques.md` | Shader math recipes in MSL: SDF (2D/3D), ray marching, procedural noise, lighting (Blinn-Phong, PBR), post-processing, domain warping, volumetrics, particles, fractals, colour utilities |
| `references/gpu-debugging-workflow.md` | GPU Frame Capture walkthrough, Metal validation levels, command-line tools (metal, metallib, metal-objdump), Metal System Trace, shader profiler metrics, debugging decision tree |

## Global Rules

| Rule | Value |
|---|---|
| `MTLDevice` | Create once, store as property |
| `MTLCommandQueue` | One per app (or per independent workload) |
| Pipeline states | Compile at init, never per-frame |
| Buffer updates | Triple buffer with `DispatchSemaphore(value: 3)` |
| Thread safety | Command buffers are not thread-safe; encoders are not thread-safe; command queue is thread-safe |
| Debugging | Use Xcode GPU Frame Capture for every performance investigation |
| Deployment target | iOS 26+ only -- no `@available` checks |
