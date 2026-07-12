import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import TrackerCam
import TrackerCamCore

/// End-to-end exercise of the offline skeleton-tracking pipeline (ClipAnalyzer → pose → angles).
/// Both fixtures are synthetic so the test remains meaningful on Simulator and in clean CI clones.
struct AnalysisPipelineTests {
    @Test func analyzerRunsAndReportsSkeletonCoverage() async throws {
        let url = try await Self.makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let analyzer = ClipAnalyzer(
            detector: SyntheticDetector(),
            riderPose: SyntheticRiderPoseEstimator(),
            horsePose: NoHorsePoseEstimator())
        let analysis = try await analyzer.analyze(url: url)

        #expect(analysis.frameCount == 6, "pipeline should analyze every generated frame")
        #expect(analysis.riderDetectionRate == 1,
                "every synthetic frame should preserve its rider skeleton")
        #expect((analysis.riderMeanJointConfidence ?? 0) > 0.9,
                "synthetic joint confidence should survive smoothing")
        #expect(analysis.riderJointCompleteness == 1,
                "all rider joints should survive the pipeline")
        #expect(analysis.riderAngleCoverage == 1,
                "synthetic joints should produce rider angles")
    }

    private static func makeVideoFixture() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trackercam-analysis-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 96,
            AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 96,
                kCVPixelBufferHeightKey as String: 64,
            ])

        guard writer.canAdd(input) else { throw FixtureError.cannotAddWriterInput }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.cannotStartWriter }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<6 {
            guard input.isReadyForMoreMediaData else { throw FixtureError.writerNotReady }
            let buffer = try makePixelBuffer(value: UInt8(32 + frameIndex * 16))
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: 10)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? FixtureError.cannotAppendFrame
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.cannotFinishWriter }
        return url
    }

    private static func makePixelBuffer(value: UInt8) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            96,
            64,
            kCVPixelFormatType_32BGRA,
            nil,
            &optionalBuffer)
        guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
            throw FixtureError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FixtureError.cannotCreatePixelBuffer
        }
        memset(baseAddress, Int32(value), CVPixelBufferGetDataSize(buffer))
        return buffer
    }
}

private struct SyntheticDetector: SubjectDetecting {
    let isModelLoaded = true

    func detect(in pixelBuffer: CVPixelBuffer, imageSize: TCSize) -> SubjectBoxes {
        SubjectBoxes(rider: TCRect(
            x: imageSize.width * 0.25,
            y: imageSize.height * 0.1,
            width: imageSize.width * 0.5,
            height: imageSize.height * 0.85))
    }
}

private struct SyntheticRiderPoseEstimator: RiderPosing {
    func skeleton(in pixelBuffer: CVPixelBuffer,
                  imageSize: TCSize,
                  regionOfInterest: CGRect?) -> TCSkeleton? {
        let positions: [TCRiderJoint: TCPoint] = [
            .nose: TCPoint(x: 48, y: 8), .neck: TCPoint(x: 48, y: 16),
            .leftShoulder: TCPoint(x: 38, y: 18), .rightShoulder: TCPoint(x: 58, y: 18),
            .leftElbow: TCPoint(x: 34, y: 29), .rightElbow: TCPoint(x: 62, y: 29),
            .leftWrist: TCPoint(x: 42, y: 37), .rightWrist: TCPoint(x: 54, y: 37),
            .leftHip: TCPoint(x: 42, y: 36), .rightHip: TCPoint(x: 54, y: 36),
            .leftKnee: TCPoint(x: 37, y: 48), .rightKnee: TCPoint(x: 59, y: 48),
            .leftAnkle: TCPoint(x: 34, y: 60), .rightAnkle: TCPoint(x: 62, y: 60),
            .root: TCPoint(x: 48, y: 36),
        ]
        return TCSkeleton(joints: positions.reduce(into: [:]) { joints, entry in
            joints[entry.key.rawValue] = TCJoint(point: entry.value, confidence: 0.98)
        })
    }
}

private struct NoHorsePoseEstimator: HorsePosing {
    let isModelLoaded = false

    func skeleton(in pixelBuffer: CVPixelBuffer, imageSize: TCSize, box: TCRect?) -> TCSkeleton? {
        nil
    }
}

private enum FixtureError: Error {
    case cannotAddWriterInput
    case cannotStartWriter
    case writerNotReady
    case cannotAppendFrame
    case cannotFinishWriter
    case cannotCreatePixelBuffer
}
