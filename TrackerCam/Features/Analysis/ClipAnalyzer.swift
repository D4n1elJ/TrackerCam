import AVFoundation
import CoreVideo
import os
import TrackerCamCore

private let log = Logger(subsystem: "com.trackercam.app", category: "analysis")

/// Offline, on-device clip analyzer. Reads a recorded `.mov` frame-by-frame (no cloud), downscales to
/// an analysis resolution, and runs the pipeline per frame:
///
///   RF-DETR (horse + rider boxes) → Vision body pose (rider angles) → horse-keypoint model (optional)
///
/// Producing a `ClipAnalysis` the UI can summarize and `ClipAnnotator` can render. Designed to run off
/// the main thread; report progress via the async stream so the UI stays responsive.
///
/// This mirrors the live pipeline's analysis-buffer convention: frames are downscaled to a long side
/// of ~`analysisLongSide` so the models run fast, and all rects/points in `FrameAnalysis` are in that
/// downscaled pixel space.
actor ClipAnalyzer {
    /// Long side of the analysis image; boxes/skeletons are in this space.
    static let analysisLongSide: Double = 1280

    private let detector: SubjectDetecting
    private let riderPose: RiderPosing
    private let horsePose: HorsePosing

    init(detector: SubjectDetecting = RFDETRDetector(),
         riderPose: RiderPosing = VisionRiderPoseEstimator(),
         horsePose: HorsePosing = CoreMLHorsePoseEstimator()) {
        self.detector = detector
        self.riderPose = riderPose
        self.horsePose = horsePose
    }

    /// Analyze `url`. `progress` is called on the analyzer's executor as frames complete.
    func analyze(url: URL,
                 frameStride: Int = 1,
                 progress: (@Sendable (AnalysisProgress) -> Void)? = nil) async throws -> ClipAnalysis {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AnalysisError.noVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let oriented = naturalSize.applying(transform)
        let srcW = abs(oriented.width), srcH = abs(oriented.height)
        let scale = min(1, Self.analysisLongSide / max(srcW, srcH))
        let analysisSize = TCSize(width: (srcW * scale).rounded(), height: (srcH * scale).rounded())
        let videoComposition = AnalysisVideo.videoComposition(
            track: track,
            naturalSize: naturalSize,
            preferredTransform: transform,
            renderSize: analysisSize,
            nominalFrameRate: fps,
            duration: duration)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(analysisSize.width),
            kCVPixelBufferHeightKey as String: Int(analysisSize.height),
        ])
        output.videoComposition = videoComposition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AnalysisError.cannotReadTrack }
        reader.add(output)
        guard reader.startReading() else { throw AnalysisError.cannotReadTrack }

        // Estimate frame count for progress (duration * nominalFrameRate).
        let estimatedTotal = max(1, Int((duration.seconds * Double(fps)) / Double(max(1, frameStride))))

        var frames: [FrameAnalysis] = []
        var riderSmoother = TCSkeletonSmoother(positionAlpha: 0.45, confidenceAlpha: 0.55, minConfidence: 0.2)
        var index = 0
        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            defer { index += 1 }
            guard index % frameStride == 0,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)

            let boxes = detector.detect(in: pixelBuffer, imageSize: analysisSize)
            // Restrict pose to the rider box (Vision ROI is normalized, bottom-left origin).
            let roi = boxes.rider.map { Self.visionROI($0, imageSize: analysisSize) }
            let rawRiderSkeleton = riderPose.skeleton(in: pixelBuffer, imageSize: analysisSize, regionOfInterest: roi)
            let riderSkeleton = riderSmoother.smooth(rawRiderSkeleton)
            let horseSkeleton = horsePose.skeleton(in: pixelBuffer, imageSize: analysisSize, box: boxes.horse)

            frames.append(FrameAnalysis(
                time: time,
                horseBox: boxes.horse,
                riderBox: boxes.rider ?? riderSkeleton.map { Self.boundingBox(of: $0) ?? .zero },
                riderSkeleton: riderSkeleton,
                horseSkeleton: horseSkeleton,
                riderAngles: riderSkeleton.map(RiderAngles.init)))

            progress?(AnalysisProgress(processed: frames.count, total: estimatedTotal))
        }

        if reader.status == .failed { throw reader.error ?? AnalysisError.cannotReadTrack }
        log.notice("Analyzed \(frames.count) frames of \(url.lastPathComponent)")
        return ClipAnalysis(sourceURL: url, imageSize: analysisSize, frames: frames, annotatedURL: nil)
    }

    /// Convert a top-left pixel rect to Vision's normalized, bottom-left-origin ROI, with padding.
    private static func visionROI(_ rect: TCRect, imageSize: TCSize) -> CGRect {
        let pad = 0.1
        let x = max(0, rect.minX / imageSize.width - pad)
        let w = min(1 - x, rect.width / imageSize.width + 2 * pad)
        let yTop = rect.minY / imageSize.height
        let h = min(1, rect.height / imageSize.height + 2 * pad)
        let yBottom = max(0, 1 - yTop - h)
        return CGRect(x: x, y: yBottom, width: max(0.01, w), height: max(0.01, h))
    }

    private static func boundingBox(of s: TCSkeleton) -> TCRect? {
        let pts = s.joints.values.map(\.point)
        guard let first = pts.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return TCRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

enum AnalysisVideo {
    static func videoComposition(track: AVAssetTrack,
                                 naturalSize: CGSize,
                                 preferredTransform: CGAffineTransform,
                                 renderSize: TCSize,
                                 nominalFrameRate: Float,
                                 duration: CMTime) -> AVVideoComposition {
        let fps = max(1, nominalFrameRate)
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(trackID: track.trackID)
        layerConfiguration.setTransform(
            renderTransform(naturalSize: naturalSize, preferredTransform: preferredTransform, renderSize: renderSize),
            at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        let instructionConfiguration = AVVideoCompositionInstruction.Configuration(
            layerInstructions: [layerInstruction],
            timeRange: CMTimeRange(start: .zero, duration: duration))
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfiguration)
        let compositionConfiguration = AVVideoComposition.Configuration(
            frameDuration: CMTime(value: 1, timescale: CMTimeScale(fps.rounded())),
            instructions: [instruction],
            renderSize: CGSize(width: renderSize.width, height: renderSize.height))
        return AVVideoComposition(configuration: compositionConfiguration)
    }

    private static func renderTransform(naturalSize: CGSize,
                                        preferredTransform: CGAffineTransform,
                                        renderSize: TCSize) -> CGAffineTransform {
        let transformedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let sx = renderSize.width / max(1, transformedRect.width)
        let sy = renderSize.height / max(1, transformedRect.height)
        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY))
            .concatenating(CGAffineTransform(scaleX: sx, y: sy))
    }
}

enum AnalysisError: Error, LocalizedError {
    case noVideoTrack
    case cannotReadTrack
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The clip has no video track."
        case .cannotReadTrack: return "Could not read the clip's video."
        case .exportFailed(let m): return "Annotated export failed: \(m)"
        }
    }
}
