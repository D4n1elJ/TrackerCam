import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

#if targetEnvironment(simulator)
/// Feeds prerecorded video frames into the live frame router when the iOS simulator has no camera.
///
/// Drop `SimulatorFixture.mov` or `SimulatorFixture.mp4` into `TrackerCam/Resources/` before
/// building, or into the app's Documents directory at runtime. Frames are decoded as bi-planar YUV
/// so they exercise the same Metal reframe path as camera capture.
final class SimulatorVideoFeeder: @unchecked Sendable {
    private let router: FrameRouter
    private let lock = NSLock()
    private var isRunning = false
    private var task: Task<Void, Never>?

    init(router: FrameRouter) {
        self.router = router
    }

    static var fixtureURL: URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: "SimulatorFixture", withExtension: "mov") { return url }
        if let url = bundle.url(forResource: "SimulatorFixture", withExtension: "mp4") { return url }

        let docs = URL.documentsDirectory
        let mov = docs.appending(path: "SimulatorFixture.mov")
        if FileManager.default.fileExists(atPath: mov.path) { return mov }
        let mp4 = docs.appending(path: "SimulatorFixture.mp4")
        if FileManager.default.fileExists(atPath: mp4.path) { return mp4 }
        return nil
    }

    static var isFixtureAvailable: Bool { fixtureURL != nil }

    func start(url: URL) {
        stop()
        setRunning(true)
        task = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.run(url: url)
        }
    }

    func stop() {
        setRunning(false)
        task?.cancel()
        task = nil
    }

    private func run(url: URL) async {
        var sequence: UInt64 = 0
        var lastPTS: CMTime?

        while running, Task.isCancelled == false {
            guard let reader = await makeReader(url: url),
                  let output = reader.outputs.first,
                  reader.startReading() else {
                setRunning(false)
                return
            }

            while running, Task.isCancelled == false, let sample = output.copyNextSampleBuffer() {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                if let lastPTS {
                    let delta = CMTimeGetSeconds(pts - lastPTS)
                    if delta.isFinite, delta > 0 {
                        let interval = min(delta, 1.0 / 15.0)
                        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }
                }
                lastPTS = pts

                sequence &+= 1
                let w = CVPixelBufferGetWidth(pixelBuffer)
                let h = CVPixelBufferGetHeight(pixelBuffer)
                let ctx = FrameContext(
                    sequenceNumber: sequence,
                    presentationTime: pts,
                    sourceDimensions: CGSize(width: w, height: h),
                    rotationAngle: 0,
                    isMirrored: false,
                    sessionGeneration: 0,
                    effectiveStabilizationMode: .off
                )
                router.route(FramePayload(pixelBuffer: pixelBuffer, context: ctx))
            }

            reader.cancelReading()
            lastPTS = nil
        }
    }

    private var running: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    private func setRunning(_ value: Bool) {
        lock.lock()
        isRunning = value
        lock.unlock()
    }

    private func makeReader(url: URL) async -> AVAssetReader? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        return reader
    }
}
#endif
