import SwiftUI
import MetalKit

/// Draws the view model's latest reframed texture into an MTKView drawable (plan §10 preview).
struct MetalPreviewView: UIViewRepresentable {
    var viewModel: CameraViewModel

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        context.coordinator.configure(device: view.device)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    // MTKViewDelegate methods are NS_SWIFT_UI_ACTOR (@MainActor) in the SDK, so the coordinator
    // is @MainActor and its methods satisfy the requirements directly.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private let viewModel: CameraViewModel
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?

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
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentTexture(texture, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cmd.present(drawable)
            cmd.commit()
        }
    }
}
