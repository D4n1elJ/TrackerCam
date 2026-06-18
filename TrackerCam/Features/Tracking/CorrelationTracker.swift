import CoreVideo
import TrackerCamCore

// =============================================================================================
// CorrelationTracker — CPU template-correlation tracker (works in the simulator; no ANE).
// =============================================================================================
//
// WHY: `VNTrackObjectRequest` drifts on fast/deformable subjects and is ANE-backed, so it can't run
// in the iOS simulator ("Failed to create espresso context"). This is a pure-CPU tracker that runs
// everywhere. It implements **normalized cross-correlation (NCC) template matching** — a robust,
// well-understood correlation tracker. (A frequency-domain MOSSE/DCF or OpenCV CSRT could replace it
// for more accuracy under scale change; NCC is chosen here because it's reliable to get correct and
// has zero dependencies.)
//
// ALGORITHM (per frame):
//   1. Keep a normalized grayscale template of the target (sampled onto a fixed TW×TH grid).
//   2. Search a small window around the last center; at each offset, sample a same-size grid and
//      compute NCC against the template. The argmax is the new center (sub-pixel via parabolic fit).
//   3. confidence = peak NCC. Below a floor ⇒ lost (return nil so the detector re-seeds).
//   4. Adapt the template with a slow running average so it follows gradual appearance change.
//
// COORDINATES: the luma plane is the DOWNSCALED analysis buffer; the API speaks full-resolution
// source pixels. We convert with `scale = luma.width / source.width` and track internally in plane
// pixels. Driven from the TrackingEngine actor only (not thread-safe).
//
// Scaffold/guidance by Claude; NCC implementation by Claude. codex may swap in MOSSE/CSRT behind the
// same `init?`/`update`/`confidence` interface.
// =============================================================================================

final class CorrelationTracker {

    private static let tw = 20          // template grid width (kept small — NCC cost ∝ tw·th·candidates)
    private static let th = 15          // template grid height
    private static let searchRadius = 32.0   // plane px; follows canter + camera pan
    private static let searchStep = 3.0
    private static let scales = [0.92, 1.0, 1.08]   // multi-scale: follow the subject's size change
    private static let lostNCC = 0.45   // weak/background matches ⇒ lost (detector re-seeds)
    private static let adaptRate: Float = 0.03   // slow: anchor to the seed appearance, resist drift

    /// Peak NCC of the last match (0…1). A confidence proxy.
    private(set) var confidence: Double = 0

    private var cx: Double              // target center, plane px
    private var cy: Double
    private var bw: Double              // box size, plane px (adapted by multi-scale search)
    private var bh: Double
    private let bw0: Double             // seed box size, for scale clamping
    private let bh0: Double
    private let scale: Double           // plane.width / source.width
    private var template: [Float]       // normalized (zero-mean, unit-norm), TW*TH

    // -----------------------------------------------------------------------------------------
    init?(luma: LumaPlane, box: TCRect, source: TCSize) {
        guard source.width > 0, source.height > 0, box.width > 4, box.height > 4,
              luma.width > 0, luma.height > 0 else { return nil }
        scale = Double(luma.width) / source.width
        cx = box.center.x * scale
        cy = box.center.y * scale
        bw = max(6, box.width * scale)
        bh = max(6, box.height * scale)
        bw0 = bw
        bh0 = bh
        template = Self.normalized(Self.sample(luma, cx: cx, cy: cy, w: bw, h: bh))
    }

    // -----------------------------------------------------------------------------------------
    func update(luma: LumaPlane, source: TCSize) -> TCRect? {
        var best = -2.0, bestX = cx, bestY = cy, bestScale = 1.0
        // Search position × a few scales so the box follows a deforming / approaching subject (the
        // appearance match is invariant to camera motion — this is the moving-camera-safe signal).
        for sc in Self.scales {
            let sw = bw * sc, sh = bh * sc
            var dy = -Self.searchRadius
            while dy <= Self.searchRadius {
                var dx = -Self.searchRadius
                while dx <= Self.searchRadius {
                    let s = Self.ncc(template, Self.normalized(Self.sample(luma, cx: cx + dx, cy: cy + dy, w: sw, h: sh)))
                    if s > best { best = s; bestX = cx + dx; bestY = cy + dy; bestScale = sc }
                    dx += Self.searchStep
                }
                dy += Self.searchStep
            }
        }

        confidence = max(0, best)
        // Lost if the match is weak (background) or wandered off the frame — detector re-seeds.
        guard best >= Self.lostNCC,
              bestX >= 0, bestX <= Double(luma.width),
              bestY >= 0, bestY <= Double(luma.height) else { return nil }

        cx = bestX
        cy = bestY
        // Apply the chosen scale, clamped to a band around the seed size (prevents runaway zoom).
        bw = min(max(bw * bestScale, bw0 * 0.5), bw0 * 2.0)
        bh = min(max(bh * bestScale, bh0 * 0.5), bh0 * 2.0)

        // Slow template adaptation (follows gradual appearance change without runaway drift).
        let fresh = Self.normalized(Self.sample(luma, cx: cx, cy: cy, w: bw, h: bh))
        for i in 0..<template.count { template[i] = template[i] * (1 - Self.adaptRate) + fresh[i] * Self.adaptRate }

        let w = bw / scale, h = bh / scale
        return TCRect(x: cx / scale - w / 2, y: cy / scale - h / 2, width: w, height: h)
    }

    // --- Sampling + NCC helpers ---------------------------------------------------------------

    /// Sample a TW×TH grayscale grid centered at (cx,cy) over a w×h plane region (edge-clamped).
    private static func sample(_ luma: LumaPlane, cx: Double, cy: Double, w: Double, h: Double) -> [Float] {
        var out = [Float](repeating: 0, count: tw * th)
        let x0 = cx - w / 2, y0 = cy - h / 2
        let stepX = w / Double(tw), stepY = h / Double(th)
        let bpp = luma.bytesPerPixel
        let maxX = luma.width - 1, maxY = luma.height - 1
        // Fast nearest-neighbor, direct byte read. NCC needs the cost ∝ tw·th·candidates to stay
        // tiny; per-pixel bilinear was too expensive. Use Y directly for 420v and a cheap grayscale
        // average for BGRA so brown-subject contrast is not reduced to the blue channel.
        for j in 0..<th {
            let iy = min(max(Int(y0 + (Double(j) + 0.5) * stepY), 0), maxY)
            let row = luma.base + iy * luma.rowBytes
            for i in 0..<tw {
                let ix = min(max(Int(x0 + (Double(i) + 0.5) * stepX), 0), maxX)
                let offset = ix * bpp
                if bpp == 1 {
                    out[j * tw + i] = Float(row[offset])
                } else {
                    out[j * tw + i] = Float((UInt16(row[offset]) + UInt16(row[offset + 1]) + UInt16(row[offset + 2])) / 3)
                }
            }
        }
        return out
    }

    /// Zero-mean, unit-norm (so NCC is a plain dot product, invariant to brightness/contrast).
    private static func normalized(_ p: [Float]) -> [Float] {
        let n = Float(p.count)
        var mean: Float = 0
        for v in p { mean += v }
        mean /= n
        var out = p
        var norm: Float = 0
        for i in 0..<out.count { out[i] -= mean; norm += out[i] * out[i] }
        norm = norm.squareRoot()
        if norm > 1e-6 { let inv = 1 / norm; for i in 0..<out.count { out[i] *= inv } }
        return out
    }

    /// NCC of two normalized patches = dot product, in [-1, 1].
    private static func ncc(_ a: [Float], _ b: [Float]) -> Double {
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return Double(s)
    }
}

/// Lightweight view over a locked luma (Y) plane. Caller owns the lock; do not retain past the call.
struct LumaPlane {
    let base: UnsafePointer<UInt8>
    let width: Int
    let height: Int
    let rowBytes: Int
    let bytesPerPixel: Int

    /// Build from a locked 420v/420f Y plane or BGRA analysis buffer.
    static func fromLockedPixelBuffer(_ pb: CVPixelBuffer) -> LumaPlane? {
        if CVPixelBufferGetPlaneCount(pb) > 0,
           let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
            return LumaPlane(
                base: base.assumingMemoryBound(to: UInt8.self),
                width: CVPixelBufferGetWidthOfPlane(pb, 0),
                height: CVPixelBufferGetHeightOfPlane(pb, 0),
                rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pb, 0),
                bytesPerPixel: 1)
        }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        return LumaPlane(
            base: base.assumingMemoryBound(to: UInt8.self),
            width: CVPixelBufferGetWidth(pb),
            height: CVPixelBufferGetHeight(pb),
            rowBytes: CVPixelBufferGetBytesPerRow(pb),
            bytesPerPixel: 4)
    }

    func sample(x: Double, y: Double) -> Double {
        let clampedX = min(max(0, x), Double(max(0, width - 1)))
        let clampedY = min(max(0, y), Double(max(0, height - 1)))
        let x0 = Int(clampedX.rounded(.down))
        let y0 = Int(clampedY.rounded(.down))
        let x1 = min(width - 1, x0 + 1)
        let y1 = min(height - 1, y0 + 1)
        let tx = clampedX - Double(x0)
        let ty = clampedY - Double(y0)
        let a = pixelLuma(x: x0, y: y0)
        let b = pixelLuma(x: x1, y: y0)
        let c = pixelLuma(x: x0, y: y1)
        let d = pixelLuma(x: x1, y: y1)
        return (1 - ty) * ((1 - tx) * a + tx * b) + ty * ((1 - tx) * c + tx * d)
    }

    private func pixelLuma(x: Int, y: Int) -> Double {
        let offset = y * rowBytes + x * bytesPerPixel
        if bytesPerPixel == 1 {
            return Double(base[offset])
        }
        let b = Double(base[offset])
        let g = Double(base[offset + 1])
        let r = Double(base[offset + 2])
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
