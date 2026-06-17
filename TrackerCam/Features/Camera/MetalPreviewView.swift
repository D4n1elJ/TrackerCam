import SwiftUI
import MetalKit

/// Draws the view model's latest reframed texture into an MTKView drawable (plan §10 preview).
struct MetalPreviewView: UIViewRepresentable {
    var viewModel: CameraViewModel
    /// Aspect-FILL (cover, crops edges) when true; aspect-FIT (letterbox) when false.
    var aspectFill: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        // Draw on demand (one redraw per delivered frame) instead of a fixed 60fps clock, so the GPU
        // idles when no new frame is ready — saves power, especially below 60fps capture.
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.isOpaque = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        // Push model: don't free-run. Draw exactly once per fresh reframed frame → low latency AND
        // no judder from two unsynced 60 Hz loops.
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        context.coordinator.configure(device: view.device)
        viewModel.requestPreviewRedraw = { [weak view] in view?.setNeedsDisplay() }

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.aspectFill = aspectFill
        uiView.setNeedsDisplay()
    }

    // MTKViewDelegate methods are NS_SWIFT_UI_ACTOR (@MainActor) in the SDK, so the coordinator
    // is @MainActor and its methods satisfy the requirements directly.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private let viewModel: CameraViewModel
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        var aspectFill: Bool = true

        init(viewModel: CameraViewModel) { self.viewModel = viewModel }

        func configure(device: MTLDevice?) {
            guard let device, let library = device.makeDefaultLibrary() else { return }
            queue = device.makeCommandQueue()
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "blitVertex")
            desc.fragmentFunction = library.makeFunction(name: "blitFragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try? device.makeRenderPipelineState(descriptor: desc)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let texture = viewModel.latestPreviewTexture,
                  let pipeline,
                  let drawable = view.currentDrawable,
                  let rpd = view.currentRenderPassDescriptor,
                  let cmd = queue?.makeCommandBuffer(),
                  let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

            // Scale the texture into the drawable preserving aspect: FILL covers (crops overflow),
            // FIT letterboxes (whole frame visible). No skew either way.
            let texA = Float(texture.width) / Float(texture.height)
            let drwA = Float(drawable.texture.width) / Float(drawable.texture.height)
            var scale = SIMD2<Float>(1, 1)
            if aspectFill {
                if drwA > texA { scale.y = drwA / texA } else { scale.x = texA / drwA }
            } else {
                if drwA > texA { scale.x = texA / drwA } else { scale.y = drwA / texA }
            }

            enc.setRenderPipelineState(pipeline)
            enc.setVertexBytes(&scale, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            enc.setFragmentTexture(texture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }
    }
}
