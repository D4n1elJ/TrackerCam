import Metal
import CoreVideo
import simd
import TrackerCamCore

/// GPU crop + YUV→RGB into a fixed-size output (plan §10 GPU Pipeline).
/// One crop decision + one sampling pass feeds BOTH preview (MTLTexture) and recording
/// (the same frame as an IOSurface-backed CVPixelBuffer), so they can never diverge.
///
/// Main-actor isolated: it is only ever driven from `CameraViewModel`'s per-frame path, so this
/// keeps the (non-Sendable) source pixel buffer from crossing isolation while still letting the
/// GPU run asynchronously (see `render`).
@MainActor
final class ReframePipeline {

    struct CropParams { var cropOrigin: SIMD2<Float>; var cropSize: SIMD2<Float> }

    /// One reframed frame, available simultaneously as a texture and a pixel buffer.
    /// @unchecked Sendable: handed from the GPU queue back to the caller under single-owner use.
    struct RenderedFrame: @unchecked Sendable {
        let texture: MTLTexture
        let pixelBuffer: CVPixelBuffer
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache!
    private let pool: CVPixelBufferPool
    let outputSize: CGSize
    // Dedicated GPU queue so reframe never runs on the main thread (perf).
    private let gpuQueue = DispatchQueue(label: "com.trackercam.gpu", qos: .userInitiated)

    init?(outputSize: CGSize, poolSize: Int = 4) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let fn = library.makeFunction(name: "reframeYUV"),
              let state = try? device.makeComputePipelineState(function: fn) else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.pipelineState = state
        self.outputSize = outputSize

        let poolAttrs = [kCVPixelBufferPoolMinimumBufferCountKey as String: poolSize]
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary,
                                      bufferAttrs as CFDictionary, &pool) == kCVReturnSuccess,
              let pool else { return nil }
        self.pool = pool

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    /// Render the source-pixel crop of `pixelBuffer` into a fresh pooled output frame.
    /// Returns nil if textures/buffers could not be created (the frame is dropped for preview).
    ///
    /// Awaits the GPU via a completion handler rather than `waitUntilCompleted()`, so the caller's
    /// thread (the main actor) is freed to service UI and other frames while the GPU runs.
    func render(pixelBuffer: CVPixelBuffer, cropPixelRect: TCRect, sourceSize: TCSize) async -> RenderedFrame? {
        guard let luma = makeTexture(pixelBuffer, plane: 0, format: .r8Unorm),
              let chroma = makeTexture(pixelBuffer, plane: 1, format: .rg8Unorm) else { return nil }


                var params = CropParams(
                    cropOrigin: SIMD2(Float(cropPixelRect.minX / sourceSize.width),
                                      Float(cropPixelRect.minY / sourceSize.height)),
                    cropSize: SIMD2(Float(cropPixelRect.width / sourceSize.width),
                                    Float(cropPixelRect.height / sourceSize.height)))

                enc.setComputePipelineState(self.pipelineState)
                enc.setTexture(luma, index: 0)
                enc.setTexture(chroma, index: 1)
                enc.setTexture(outTex, index: 2)
                enc.setBytes(&params, length: MemoryLayout<CropParams>.stride, index: 0)

        enc.setComputePipelineState(pipelineState)
        enc.setTexture(luma, index: 0)
        enc.setTexture(chroma, index: 1)
        enc.setTexture(outTex, index: 2)
        enc.setBytes(&params, length: MemoryLayout<CropParams>.stride, index: 0)

        let w = pipelineState.threadExecutionWidth
        let h = max(1, pipelineState.maxTotalThreadsPerThreadgroup / w)
        let grid = MTLSize(width: outTex.width, height: outTex.height, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        enc.endEncoding()

        // Suspend until the GPU finishes instead of blocking the thread. The completed-handler
        // closure captures only the (Sendable) continuation; the non-Sendable texture/buffer are
        // returned after the await, so nothing crosses isolation.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cmd.addCompletedHandler { _ in continuation.resume() }
            cmd.commit()
        }

        return RenderedFrame(texture: outTex, pixelBuffer: outBuffer)

    }

    private func makeTexture(_ pixelBuffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            format, width, height, plane, &cvTexture) == kCVReturnSuccess,
              let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func makeOutputTexture(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm, Int(outputSize.width), Int(outputSize.height), 0, &cvTexture) == kCVReturnSuccess,
              let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }
}
