import AVFoundation
import CoreVideo
import CoreMedia
import os

private let vlog = Logger(subsystem: "com.trackercam.app", category: "videosrc")

/// Debug/simulator frame source: plays a bundled video through the SAME pipeline as the camera, so
/// tracking, detection, and reframe can be exercised without a physical camera. The iOS simulator
/// does not deliver camera buffers to `AVCaptureVideoDataOutput`, so this is the only way to validate
/// the full pipeline (and the green tracking box) in the simulator. Produces 420v biplanar buffers
/// identical to `CameraService`, routed via the same `FrameRouter` single-owner contract (plan §6).
final class DebugVideoSource: @unchecked Sendable {
    private let router: FrameRouter
    private let url: URL
    private var task: Task<Void, Never>?
    private var sequence: UInt64 = 0

    init(router: FrameRouter, url: URL) {
        self.router = router
        self.url = url
    }

    /// The video's natural pixel dimensions (for the effective-config summary). Loaded lazily.
    static func dimensions(of url: URL) async -> CGSize {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize) else { return CGSize(width: 1920, height: 1080) }
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    func start() {
        task = Task.detached(priority: .userInitiated) { [weak self] in
            // Loop the clip so tracking keeps running for inspection.
            while !Task.isCancelled { await self?.playOnce() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func playOnce() async {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)

        let fps = (try? await track.load(.nominalFrameRate)).map { Double($0) } ?? 30
        let frameNanos = UInt64(1_000_000_000 / max(1, fps))
        guard reader.startReading() else { return }

        while !Task.isCancelled, reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            sequence &+= 1
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let ctx = FrameContext(
                sequenceNumber: sequence,
                presentationTime: pts,
                sourceDimensions: CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                         height: CVPixelBufferGetHeight(pixelBuffer)),
                rotationAngle: 0,
                isMirrored: false,
                sessionGeneration: 0,
                effectiveStabilizationMode: .off
            )
            // The payload retains the pixel buffer (single-owner contract), so it stays valid after
            // the sample buffer is released on the next loop iteration.
            router.route(FramePayload(pixelBuffer: pixelBuffer, context: ctx))
            try? await Task.sleep(nanoseconds: frameNanos)
        }
        reader.cancelReading()
    }
}
