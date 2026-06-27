import AVFoundation
import CoreGraphics
import CoreVideo
import UIKit
import os
import TrackerCamCore

private let log = Logger(subsystem: "com.trackercam.app", category: "analysis.annotate")

/// Renders an annotated copy of the clip: boxes, skeleton bones, and key angle read-outs burned in.
///
/// This is the iOS-native replacement for "OpenCV to analyze and annotate". OpenCV's drawing/encoding
/// isn't needed on iOS — Core Graphics draws the overlay and `AVAssetWriter` encodes the H.264 output.
/// (If you later want classical-CV math like optical flow or homography, that's where OpenCV would
/// earn its place; for annotation, native is lighter and avoids the ~100MB framework.)
///
/// Frames are matched to `ClipAnalysis.frames` by decode order, at the same analysis resolution the
/// analyzer used, so the pixel coordinates line up without rescaling.
actor ClipAnnotator {
    // Rider skeleton bone connections (pairs of TCRiderJoint raw values).
    private static let riderBones: [(TCRiderJoint, TCRiderJoint)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.neck, .nose),
    ]

    /// Render `analysis` over its source clip to a new `.mov` in the app's temp dir. Returns the URL.
    func render(_ analysis: ClipAnalysis) async throws -> URL {
        let asset = AVURLAsset(url: analysis.sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AnalysisError.noVideoTrack
        }
        let size = analysis.imageSize
        let width = Int(size.width), height = Int(size.height)
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let fps = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let videoComposition = AnalysisVideo.videoComposition(
            track: track,
            naturalSize: naturalSize,
            preferredTransform: transform,
            renderSize: size,
            nominalFrameRate: fps,
            duration: duration)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        readerOutput.videoComposition = videoComposition
        guard reader.canAdd(readerOutput) else { throw AnalysisError.cannotReadTrack }
        reader.add(readerOutput)

        let outURL = FileManager.default.temporaryDirectory
            .appending(path: "annotated-\(analysis.sourceURL.deletingPathExtension().lastPathComponent).mov")
        try? FileManager.default.removeItem(at: outURL)

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        guard writer.canAdd(writerInput) else { throw AnalysisError.exportFailed("cannot add writer input") }
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            throw AnalysisError.exportFailed("could not start reader/writer")
        }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        var index = 0
        while reader.status == .reading, let sample = readerOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            let frame = index < analysis.frames.count ? analysis.frames[index] : nil

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer),
               let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                   space: colorSpace, bitmapInfo: bitmapInfo) {
                Self.draw(frame, in: ctx, size: size)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            adaptor.append(pixelBuffer, withPresentationTime: time)
            index += 1
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed { throw AnalysisError.exportFailed(writer.error?.localizedDescription ?? "unknown") }
        log.notice("Annotated clip written: \(outURL.lastPathComponent)")
        return outURL
    }

    /// Draw one frame's overlay. The CGContext is top-left flipped relative to our coords, so we draw
    /// in a flipped space to match `FrameAnalysis` (top-left origin, y down).
    private static func draw(_ frame: FrameAnalysis?, in ctx: CGContext, size: TCSize) {
        guard let frame else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setLineWidth(max(2, size.width / 400))

        // Boxes.
        if let h = frame.horseBox { stroke(h, color: UIColor.systemGreen.cgColor, in: ctx) }
        if let r = frame.riderBox { stroke(r, color: UIColor.systemYellow.cgColor, in: ctx) }

        // Rider skeleton.
        if let s = frame.riderSkeleton {
            ctx.setStrokeColor(UIColor.systemTeal.cgColor)
            for (a, b) in riderBones {
                guard let pa = s.point(a.rawValue), let pb = s.point(b.rawValue) else { continue }
                ctx.move(to: CGPoint(x: pa.x, y: pa.y))
                ctx.addLine(to: CGPoint(x: pb.x, y: pb.y))
            }
            ctx.strokePath()
            ctx.setFillColor(UIColor.white.cgColor)
            let r = max(2, size.width / 250)
            for j in s.joints.values {
                ctx.fillEllipse(in: CGRect(x: j.point.x - r, y: j.point.y - r, width: 2 * r, height: 2 * r))
            }
        }
        ctx.restoreGState()

        // Angle read-outs (drawn in UIKit's top-left space).
        if let a = frame.riderAngles {
            var lines: [String] = []
            if let v = a.leftKnee { lines.append(String(format: "L knee %.0f°", v)) }
            if let v = a.rightKnee { lines.append(String(format: "R knee %.0f°", v)) }
            if let v = a.torsoLean { lines.append(String(format: "torso lean %.0f°", v)) }
            drawText(lines, in: ctx, size: size)
        }
    }

    private static func stroke(_ rect: TCRect, color: CGColor, in ctx: CGContext) {
        ctx.setStrokeColor(color)
        ctx.stroke(CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
    }

    private static func drawText(_ lines: [String], in ctx: CGContext, size: TCSize) {
        guard !lines.isEmpty else { return }
        UIGraphicsPushContext(ctx)
        let fontSize = max(12, size.height / 30)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
            .backgroundColor: UIColor.black.withAlphaComponent(0.4),
        ]
        var y = fontSize * 0.5
        for line in lines {
            (line as NSString).draw(at: CGPoint(x: fontSize * 0.5, y: y), withAttributes: attrs)
            y += fontSize * 1.2
        }
        UIGraphicsPopContext()
    }
}
