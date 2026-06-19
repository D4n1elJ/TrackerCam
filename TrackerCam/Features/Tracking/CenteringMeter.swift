import TrackerCamCore

// =============================================================================================
// CenteringMeter — objective, ground-truth-free tracking-quality metric.
// =============================================================================================
//
// "Is the tracked subject centered in the output?" — quantified so each run produces a comparable
// number (instead of eyeballing screenshots). The subject (horse) is the MOVING object, so we use
// frame-difference motion as a proxy for where it is, with no manual labels.
//
//   score (per frame) = 1 − (distance from the motion centroid to the crop center,
//                            normalized by the crop half-size)
//   → 1.0 = the moving subject sits dead-center in the output crop
//   → 0.0 = it sits at (or beyond) the crop edge
//
// A running average (`scoreEMA`) is the headline number to compare across runs / tuning changes and
// to drive coarse-to-fine box sizing (start large, shrink while holding the score). Pure
// instrumentation — it does not influence tracking.
// =============================================================================================

struct CenteringMeter {
    private static let gw = 80          // motion grid width
    private static let gh = 45          // motion grid height (16:9)
    private static let motionThreshold = 8    // per-cell luma delta to count as motion
    private static let minMotionMass = 60.0   // ignore frames with too little motion (subject still)

    private var prev: [UInt8]?
    private(set) var scoreEMA: Double = 0
    private(set) var samples = 0
    /// Latest motion centroid in normalized [0,1] source coords (nil if too little motion).
    private(set) var centroidNorm: (x: Double, y: Double)?
    /// Latest motion extent in normalized [0,1] source coords (nil if too little motion).
    private(set) var motionRectNorm: (minX: Double, minY: Double, maxX: Double, maxY: Double)?

    /// Compute the motion centroid from this frame vs the previous one. Call once per frame, BEFORE
    /// the crop decision, so the result can both steer the crop and be scored. Updates `centroidNorm`.
    mutating func updateCentroid(luma: LumaPlane) {
        var grid = [UInt8](repeating: 0, count: Self.gw * Self.gh)
        for j in 0..<Self.gh {
            let sy = (Double(j) + 0.5) / Double(Self.gh) * Double(luma.height)
            for i in 0..<Self.gw {
                let sx = (Double(i) + 0.5) / Double(Self.gw) * Double(luma.width)
                grid[j * Self.gw + i] = UInt8(clamping: Int(luma.sample(x: sx, y: sy)))
            }
        }
        defer { prev = grid }
        guard let p = prev, p.count == grid.count else {
            centroidNorm = nil
            motionRectNorm = nil
            return
        }

        var sumX = 0.0, sumY = 0.0, sumW = 0.0
        var minI = Self.gw, minJ = Self.gh, maxI = -1, maxJ = -1
        for j in 0..<Self.gh {
            for i in 0..<Self.gw {
                let d = abs(Int(grid[j * Self.gw + i]) - Int(p[j * Self.gw + i]))
                if d > Self.motionThreshold {
                    let w = Double(d)
                    sumX += (Double(i) + 0.5) / Double(Self.gw) * w
                    sumY += (Double(j) + 0.5) / Double(Self.gh) * w
                    sumW += w
                    minI = Swift.min(minI, i)
                    minJ = Swift.min(minJ, j)
                    maxI = Swift.max(maxI, i)
                    maxJ = Swift.max(maxJ, j)
                }
            }
        }
        guard sumW >= Self.minMotionMass else {
            centroidNorm = nil
            motionRectNorm = nil
            return
        }
        centroidNorm = (sumX / sumW, sumY / sumW)
        let padX = 2.0 / Double(Self.gw)
        let padY = 2.0 / Double(Self.gh)
        motionRectNorm = (
            max(0, Double(minI) / Double(Self.gw) - padX),
            max(0, Double(minJ) / Double(Self.gh) - padY),
            min(1, Double(maxI + 1) / Double(Self.gw) + padX),
            min(1, Double(maxJ + 1) / Double(Self.gh) + padY)
        )
    }

    /// The motion centroid in source pixels (for steering the crop), if available.
    func centroidPixels(source: TCSize) -> TCPoint? {
        guard let c = centroidNorm else { return nil }
        return TCPoint(x: c.x * source.width, y: c.y * source.height)
    }

    /// The motion extent in source pixels (for simulator/static-fixture crop sizing), if available.
    func motionRectPixels(source: TCSize) -> TCRect? {
        guard let r = motionRectNorm else { return nil }
        let x = r.minX * source.width
        let y = r.minY * source.height
        return TCRect(x: x,
                      y: y,
                      width: max(1, r.maxX * source.width - x),
                      height: max(1, r.maxY * source.height - y))
    }

    /// Score how centered the latest motion centroid is in `crop` (call after the crop is decided).
    mutating func score(crop: TCRect, source: TCSize) -> Double? {
        guard let c = centroidNorm, source.width > 0, source.height > 0 else { return nil }
        let halfX = (crop.width / 2) / source.width
        let halfY = (crop.height / 2) / source.height
        let px = halfX > 0 ? (c.x - crop.midX / source.width) / halfX : 0
        let py = halfY > 0 ? (c.y - crop.midY / source.height) / halfY : 0
        let s = max(0, 1 - (px * px + py * py).squareRoot())
        samples += 1
        scoreEMA = samples == 1 ? s : scoreEMA * 0.95 + s * 0.05
        return s
    }
}
