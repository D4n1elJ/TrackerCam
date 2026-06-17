import AVFoundation
import Metal
import CoreVideo

/// AVAssetWriter pipeline for the cropped HEVC output (plan §14 Recording & Export).
/// Writes to a unique temp URL; the caller moves it to its final location after finalization.
/// `@MainActor`: all of start/append/finish are driven from the main-actor frame loop in
/// CameraViewModel, so isolating here avoids sending this non-Sendable type across actors.
@MainActor
final class RecordingService {
    enum State { case idle, recording, finishing }

    struct FinishResult {
        var url: URL?
        var droppedFrames: Int
        var appendFailures: Int
        var writerErrorDescription: String?
    }

    private(set) var state: State = .idle
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private(set) var outputURL: URL?

    private let outputSize: CGSize
    private var droppedFrames = 0
    private var appendFailures = 0
    private var writerErrorDescription: String?

    init(outputSize: CGSize) {
        self.outputSize = outputSize
    }

    func start(frameRate: Int) throws {
        guard state == .idle else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrackerCam_\(Int(Date().timeIntervalSince1970)).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: adaptorAttrs)

        guard writer.canAdd(input) else { throw NSError(domain: "TrackerCam", code: 1) }
        writer.add(input)
        writer.startWriting()

        self.writer = writer
        self.videoInput = input
        self.pixelAdaptor = adaptor
        self.outputURL = url
        self.sessionStarted = false
        self.droppedFrames = 0
        self.appendFailures = 0
        self.writerErrorDescription = nil
        self.state = .recording
    }

    /// Append one rendered output frame. Never blocks the capture callback (plan §14): if the writer
    /// input is not ready, the frame is counted and dropped.
    func append(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard state == .recording, let writer, let input = videoInput, let adaptor = pixelAdaptor else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: presentationTime)  // start at first accepted PTS
            sessionStarted = true
        }
        guard input.isReadyForMoreMediaData else { droppedFrames += 1; return }
        if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            appendFailures += 1
            writerErrorDescription = writer.error?.localizedDescription ?? "Writer append failed with status \(writer.status.rawValue)"
        }
    }

    func finish() async -> FinishResult {
        guard state == .recording, let writer, let input = videoInput else {
            return FinishResult(url: nil, droppedFrames: droppedFrames, appendFailures: appendFailures, writerErrorDescription: writerErrorDescription)
        }
        state = .finishing
        input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        let errorDescription = writer.error?.localizedDescription ?? writerErrorDescription
        let result: URL? = writer.status == .completed ? outputURL : nil
        state = .idle
        return FinishResult(url: result, droppedFrames: droppedFrames, appendFailures: appendFailures, writerErrorDescription: errorDescription)
    }
}
