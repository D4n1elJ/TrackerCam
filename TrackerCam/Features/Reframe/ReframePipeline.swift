import Metal
import CoreVideo
import simd
import TrackerCamCore

/// GPU crop + YUV→RGB into a fixed-size output (plan §10 GPU Pipeline).
/// One crop decision + one sampling pass feeds BOTH preview (MTLTexture) and recording
/// (the same frame as an IOSurface-backed CVPixelBuffer), so they can never diverge.
///
/// `@unchecked Sendable` with a dedicated `gpuQueue`: the entire encode+dispatch runs off the main
/// thread (the non-Sendable source buffer reaches the queue inside a Sendable `FramePayload`), so
/// the per-frame GPU work never blocks the main actor. See `render`.
final class ReframePipeline: @unchecked Sendable {

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

    /// Render the source-pixel crop into a fresh pooled output frame, off the main thread.
    /// Awaits GPU completion via a completion handler (no thread blocking). Returns nil on failure.
    /// `payload` is @unchecked Sendable so the non-Sendable buffer can cross to the GPU queue.
    func render(payload: FramePayload, cropPixelRect: TCRect, sourceSize: TCSize) async -> RenderedFrame? {
        await withCheckedContinuation { (cont: CheckedContinuation<RenderedFrame?, Never>) in
            gpuQueue.async {
                let pixelBuffer = payload.pixelBuffer
                guard let luma = self.makeTexture(pixelBuffer, plane: 0, format: .r8Unorm),
                      let chroma = self.makeTexture(pixelBuffer, plane: 1, format: .rg8Unorm) else {
                    cont.resume(returning: nil); return
                }

                // Allocate the fixed-size output (one IOSurface-backed buffer feeds preview + record).
                var outBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, self.pool, &outBuffer) == kCVReturnSuccess,
                      let outBuffer,
                      let outTex = self.makeOutputTexture(outBuffer),
                      let cmd = self.queue.makeCommandBuffer(),
                      let enc = cmd.makeComputeCommandEncoder() else {
                    cont.resume(returning: nil); return
                }

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

                let w = self.pipelineState.threadExecutionWidth
                let h = max(1, self.pipelineState.maxTotalThreadsPerThreadgroup / w)
                let grid = MTLSize(width: outTex.width, height: outTex.height, depth: 1)
                enc.dispatchThreads(grid, threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
                enc.endEncoding()

                // Resume only when the GPU signals done — no CPU spin, no main-thread stall.
                // Build the @unchecked Sendable frame first so the @Sendable handler captures only it.
                let frame = RenderedFrame(texture: outTex, pixelBuffer: outBuffer)
                cmd.addCompletedHandler { _ in cont.resume(returning: frame) }
                cmd.commit()
            }
        }
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
