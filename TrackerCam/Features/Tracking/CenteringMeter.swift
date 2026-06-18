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
    private static let motionThreshold = 12   // per-cell luma delta to count as motion
    private static let minMotionMass = 250.0  // ignore frames with too little motion (subject still)

    private var prev: [UInt8]?
    private(set) var scoreEMA: Double = 0
    private(set) var samples = 0

    /// Returns this frame's centering score (0…1), or nil if there isn't enough motion to judge.
    /// `crop` is the output window in source pixels; `luma` is the full source frame's Y plane.
    mutating func measure(luma: LumaPlane, crop: TCRect, source: TCSize) -> Double? {
        var grid = [UInt8](repeating: 0, count: Self.gw * Self.gh)
        for j in 0..<Self.gh {
            let sy = (Double(j) + 0.5) / Double(Self.gh) * Double(luma.height)
            for i in 0..<Self.gw {
                let sx = (Double(i) + 0.5) / Double(Self.gw) * Double(luma.width)
                grid[j * Self.gw + i] = UInt8(clamping: Int(luma.sample(x: sx, y: sy)))
            }
        }
        defer { prev = grid }
        guard let p = prev, p.count == grid.count else { return nil }

        // Weighted motion centroid in normalized [0,1] source coords.
        var sumX = 0.0, sumY = 0.0, sumW = 0.0
        for j in 0..<Self.gh {
            for i in 0..<Self.gw {
                let d = abs(Int(grid[j * Self.gw + i]) - Int(p[j * Self.gw + i]))
                if d > Self.motionThreshold {
                    let w = Double(d)
                    sumX += (Double(i) + 0.5) / Double(Self.gw) * w
                    sumY += (Double(j) + 0.5) / Double(Self.gh) * w
                    sumW += w
                }
            }
        }
        guard sumW >= Self.minMotionMass, source.width > 0, source.height > 0 else { return nil }

        let centroidX = sumX / sumW
        let centroidY = sumY / sumW
        let cropCenterX = crop.midX / source.width
        let cropCenterY = crop.midY / source.height
        let halfX = (crop.width / 2) / source.width
        let halfY = (crop.height / 2) / source.height
        let px = halfX > 0 ? (centroidX - cropCenterX) / halfX : 0
        let py = halfY > 0 ? (centroidY - cropCenterY) / halfY : 0
        let score = max(0, 1 - (px * px + py * py).squareRoot())

        samples += 1
        scoreEMA = samples == 1 ? score : scoreEMA * 0.95 + score * 0.05
        return score
    }
}
