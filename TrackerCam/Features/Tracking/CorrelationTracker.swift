import CoreVideo
import Accelerate
import TrackerCamCore

// =============================================================================================
// CorrelationTracker — scaffold + integration guidance (TrackerCam tracking upgrade)
// =============================================================================================
//
// WHY THIS EXISTS
// ---------------
// `VNTrackObjectRequest` (Apple's tracker, used in TrackingEngine) drifts on fast, deformable
// subjects like a cantering horse, and the iOS *simulator* can't run ANE-backed Vision at all
// ("Failed to create espresso context"). We want a tracker that is (a) more robust and (b) runs on
// the CPU so it works in the simulator and on device.
//
// The chosen direction is a **Discriminative Correlation Filter** tracker (the family OpenCV's CSRT
// belongs to). CSRT itself lives in `opencv_contrib` and is impractical to ship here (no CocoaPods,
// no prebuilt +contrib iOS xcframework, multi-hour from-source build + an Obj-C++ bridge). So we
// implement the *core* of the same family — a **MOSSE / DCF** correlation filter (Bolme et al.,
// "Visual Object Tracking using Adaptive Correlation Filters", CVPR 2010) — in pure Swift + Accelerate.
// No dependency, CPU-only, verifiable in the simulator.
//
// OWNERSHIP / COLLABORATION
// -------------------------
// Scaffold + guidance by Claude; **codex to implement the marked TODOs**. Keep the public interface
// (`init?` / `update` / `confidence`) stable so `TrackingEngine` can swap between this and Vision
// without ripple. Add a unit-testable seam where practical (the FFT/peak math is pure and can be
// covered in TrackerCamCore-style tests if the core is moved there later).
//
// INTEGRATION POINT (TrackingEngine.track, ~lines 107–150)
// --------------------------------------------------------
//   - On seed (currentSeed set): `tracker = CorrelationTracker(lumaPlane: …, box: seed, source: …)`.
//   - Per frame instead of `sequenceHandler.perform([req] …)`:
//         if let box = tracker?.update(lumaPlane: …, source: …) { subjectPixel = box; … }
//         else { /* lost → null measurement, let the state machine/lost-ladder handle it */ }
//   - Reset the tracker in `clearTarget()` / `seed()` exactly where `trackingRequest` is reset today.
//   - Keep the existing `acceptsVisionMeasurement` sanity gate — it guards against jumps regardless
//     of tracker.
//
// INPUT: use the **luma (Y) plane** of the 420v pixel buffer directly — it *is* the grayscale image
// the filter needs, no color conversion. `CVPixelBufferGetBaseAddressOfPlane(_, 0)` after locking.
//
// =============================================================================================

/// A CPU correlation-filter tracker (MOSSE/DCF). Single-owner, not thread-safe; drive it from the
/// TrackingEngine actor only. Coordinates are full-resolution source pixels (convert at the edges).
final class CorrelationTracker {

    /// Fixed filter/template size (power of two for vDSP FFT). 64×64 is a good speed/accuracy balance
    /// at the ~720p analysis resolution. Tune if needed.
    private static let side = 64

    /// Peak Sidelobe Ratio of the last response — a confidence proxy. Low PSR ⇒ lost (re-detect).
    private(set) var confidence: Double = 0

    // --- Filter state (frequency domain), accumulated across frames (MOSSE running average) ---
    // H = A / B, where A = Σ η·(G ⊙ conj(F)),  B = Σ η·(F ⊙ conj(F)) + ε   (η = learning rate)
    // Store A and B as split-complex arrays of length side*side. TODO(codex): allocate these.

    private var center: TCPoint            // current target center, source pixels
    private var size: TCSize               // current target size, source pixels (scale handled below)

    // -----------------------------------------------------------------------------------------
    // INIT — seed the filter from the first frame + detection box.
    // -----------------------------------------------------------------------------------------
    /// - Parameters:
    ///   - luma: pointer + rowBytes + dimensions of the Y plane (caller locks the buffer).
    ///   - box: target box in source pixels.
    ///   - source: full source dimensions.
    init?(luma: LumaPlane, box: TCRect, source: TCSize) {
        self.center = box.center
        self.size = TCSize(width: box.width, height: box.height)
        // TODO(codex):
        //  1. Extract a `side×side` patch centered on `box.center`, scaled so the box maps to the
        //     patch (sample the luma plane with bilinear interpolation; clamp at edges).
        //  2. Preprocess: log(1+x), normalize to zero-mean/unit-norm, multiply by a 2-D Hann window
        //     (kills FFT edge effects). vDSP has window helpers (vDSP_hann_window).
        //  3. Build the desired response G: a 2-D Gaussian peak at the patch center (σ ≈ 2 px),
        //     then FFT it once (this is constant, can be cached).
        //  4. FFT the patch → F. Initialize A = G ⊙ conj(F), B = F ⊙ conj(F) + ε.
        //  Use vDSP_fft2d_zrop / vDSP_DFT_Execute. Keep split-complex (real/imag) buffers.
        // Return nil if the patch can't be extracted (degenerate box).
        return nil   // TODO(codex): remove once init is implemented
    }

    // -----------------------------------------------------------------------------------------
    // UPDATE — locate the target in the new frame, then adapt the filter.
    // -----------------------------------------------------------------------------------------
    /// Returns the new target box in source pixels, or nil if tracking is lost (low PSR).
    func update(luma: LumaPlane, source: TCSize) -> TCRect? {
        // TODO(codex):
        //  1. Extract the `side×side` patch at the *current* `center`/`size`, same preprocessing.
        //  2. F = FFT(patch). Response R = IFFT(F ⊙ conj(H)) where H = A / B (elementwise).
        //  3. Peak location (argmax of R) → sub-pixel refine (quadratic fit around the peak) →
        //     displacement in patch space → scale back to source pixels → update `center`.
        //  4. confidence = PSR(R) = (peak − mean_sidelobe) / std_sidelobe. If PSR < ~5 → return nil.
        //  5. Adapt: recompute F at the new center, A = (1-η)A + η·(G ⊙ conj(F)),
        //     B = (1-η)B + η·(F ⊙ conj(F)).  η ≈ 0.025.
        //  6. SCALE (optional, CSRT-like robustness): evaluate the filter at a few scales
        //     (e.g. ×0.96, 1.0, ×1.04) and pick the best PSR to update `size`. Keeps the box on a
        //     horse that grows/shrinks in frame. Start without it; add if the box size drifts.
        //  Return TCRect(center: center, size: size).
        return nil   // TODO(codex): implement
    }
}

/// Lightweight view over a locked luma (Y) plane. Caller owns the lock; do not retain past the call.
struct LumaPlane {
    let base: UnsafePointer<UInt8>
    let width: Int
    let height: Int
    let rowBytes: Int

    /// Convenience: build from a (locked) 420v/420f CVPixelBuffer's plane 0.
    static func fromLockedPixelBuffer(_ pb: CVPixelBuffer) -> LumaPlane? {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
        return LumaPlane(
            base: base.assumingMemoryBound(to: UInt8.self),
            width: CVPixelBufferGetWidthOfPlane(pb, 0),
            height: CVPixelBufferGetHeightOfPlane(pb, 0),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pb, 0))
    }
}

// =============================================================================================
// ALTERNATIVE: real OpenCV CSRT (if a +contrib iOS xcframework is later obtained)
// ---------------------------------------------------------------------------------------------
// If we get a prebuilt OpenCV with the `tracking` (contrib) module:
//   1. Add `opencv2.xcframework` to project.yml (`dependencies: - framework: …`), regenerate.
//   2. Bridge in Objective-C++ (`CSRTBridge.mm`, `.h` in the bridging header): wrap
//      `cv::TrackerCSRT::create()`, `init(Mat, Rect)`, `update(Mat, Rect&)`.
//   3. Convert the luma plane to a single-channel `cv::Mat(height, width, CV_8UC1, base, rowBytes)`
//      (no copy) and call the bridge. Map Rect↔TCRect at the edge.
//   4. Same TrackingEngine swap point as above. CSRT adds channel/spatial-reliability + scale
//      estimation, so it'll out-track this MOSSE core — but only ships if the framework is available.
// =============================================================================================
