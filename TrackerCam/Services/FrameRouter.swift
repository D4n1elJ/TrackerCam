import CoreMedia
import CoreVideo
import AVFoundation

/// Authoritative per-frame identity & timing (plan §6 Frame Identity and Timing Contract).
struct FrameContext: Sendable, Equatable {
    var sequenceNumber: UInt64
    var presentationTime: CMTime
    var sourceDimensions: CGSize
    var rotationAngle: CGFloat
    var isMirrored: Bool
    var sessionGeneration: UInt64
    var effectiveStabilizationMode: AVCaptureVideoStabilizationMode
}

/// Single-owner transfer wrapper for a non-Sendable pixel buffer + its context (plan §6 Swift 6 caveat).
///
/// `CVPixelBuffer` is not `Sendable`. We wrap it `@unchecked Sendable` and adopt a strict contract:
/// once a payload is handed off (enqueued), the sender must not touch the buffer again. The pixel
/// buffer is retained for the payload's lifetime and released when the payload is dropped.
struct FramePayload: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let context: FrameContext
}

/// Retains each source frame, schedules the downscaled ML branch, and routes the full-res buffer
/// to reframe/record consumers (plan §6 Module Responsibilities). The MVP topology is a single
/// 4K `AVCaptureVideoDataOutput`; the processing image is derived on the GPU (plan §9).
///
/// Backpressure (plan §6): detection is latest-wins (drop stale); tracking is sequential and must
/// not drop frames. This router exposes both an analysis sink (coalescing) and an ordered sink.
final class FrameRouter: @unchecked Sendable {
    /// Called for every delivered frame, in capture order, on the processing queue.
    /// Consumers must be fast; heavy work should hop to their own queues.
    /// `@Sendable` because it is invoked off the main actor (capture/processing queues).
    var onFrame: (@Sendable (FramePayload) -> Void)?

    private let processingQueue: DispatchQueue

    init(processingQueue: DispatchQueue) {
        self.processingQueue = processingQueue
    }

    /// Entry point from the capture callback. Keep the capture queue's work minimal (plan §6).
    func route(_ payload: FramePayload) {
        processingQueue.async { [weak self] in
            self?.onFrame?(payload)
        }
    }
}
