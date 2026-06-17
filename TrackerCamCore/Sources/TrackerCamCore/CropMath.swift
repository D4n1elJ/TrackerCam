/// Normalized crop headroom per edge: 0 means the crop is flush against that wall,
/// 1 means it is as far as possible from that wall. Plan §10 Edge Behavior.
public struct Headroom: Equatable, Sendable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var bottom: Double
    public init(left: Double, right: Double, top: Double, bottom: Double) {
        self.left = left; self.right = right; self.top = top; self.bottom = bottom
    }
}

/// Pure crop geometry. Plan §10 Reframe, Crop & Stabilization.
public enum CropMath {

    /// Union of the horse box with the rider box (when present), then expanded by `padding`.
    /// Plan §8 Compound Horse-and-Rider Target.
    public static func compoundSubject(horse: TCRect, rider: TCRect?, padding: Double) -> TCRect {
        let union = rider.map { horse.union($0) } ?? horse
        return padding == 0 ? union : union.expanded(byFraction: padding)
    }

    /// Crop size (at `outputAspect`) that renders the padded subject at the target height fraction.
    /// Derives from height first; if that crop would not contain the subject's width, derive from width.
    public static func requiredCropSize(forPaddedSubject subject: TCRect,
                                        targetSubjectHeightFraction: Double,
                                        outputAspect: Double) -> TCSize {
        let h = subject.height / targetSubjectHeightFraction
        let w = h * outputAspect
        if w >= subject.width {
            return TCSize(width: w, height: h)
        }
        // Subject too wide for the height-derived crop: size from width instead.
        let w2 = subject.width
        return TCSize(width: w2, height: w2 / outputAspect)
    }

    /// Place a crop of `size` centered at `center`, scaled to fit inside `source` if oversized,
    /// then translated so it lies fully within the source. Aspect ratio is preserved.
    ///
    /// `minSizeFraction` (0…1) enforces a minimum crop size: the crop is grown uniformly so each
    /// dimension is at least that fraction of the source — so the framing never zooms into a
    /// close-up that loses the surrounding environment (plan §10 / improvements #36). The growth is
    /// capped so the crop never exceeds the source. 0 (the default) disables the floor.
    public static func clampedCrop(center: TCPoint, size: TCSize, source: TCRect,
                                   minSizeFraction: Double = 0) -> TCRect {
        var w = size.width
        var h = size.height
        // Scale uniformly to fit the source if either dimension overflows.
        let fitScale = min(1.0, min(source.width / w, source.height / h))
        w *= fitScale
        h *= fitScale
        // Enforce the minimum crop size, never growing past what fits the source.
        if minSizeFraction > 0 {
            let needed = max((minSizeFraction * source.width) / w, (minSizeFraction * source.height) / h)
            let maxFit = min(source.width / w, source.height / h)   // ≥ 1 after the fit scale above
            let grow = min(max(1.0, needed), maxFit)
            w *= grow
            h *= grow
        }
        // Translate so the crop stays inside the source bounds.
        let x = clamp(center.x - w / 2, low: source.minX, high: source.maxX - w)
        let y = clamp(center.y - h / 2, low: source.minY, high: source.maxY - h)
        return TCRect(x: x, y: y, width: w, height: h)
    }

    /// Composition target center: subject center + motion lead (direction of travel) + vertical bias.
    /// Plan §10 Composition Model. Negative `verticalOffsetFraction` raises the crop center
    /// (placing the subject lower in frame), in the top-left (y-down) coordinate space.
    public static func compositionCenter(subjectCenter: TCPoint,
                                         velocity: TCPoint,
                                         cropSize: TCSize,
                                         leadFraction: Double,
                                         verticalOffsetFraction: Double) -> TCPoint {
        let dir = normalizedOrZero(velocity)
        let horizontalLead = dir.x * cropSize.width * leadFraction
        let verticalOffset = cropSize.height * verticalOffsetFraction
        return TCPoint(x: subjectCenter.x + horizontalLead,
                       y: subjectCenter.y + verticalOffset)
    }

    /// Per-edge normalized headroom. Reports 0 for an axis with no pan room (avoids divide-by-zero).
    public static func headroom(crop: TCRect, source: TCRect) -> Headroom {
        let panX = source.width - crop.width
        let panY = source.height - crop.height
        let left = panX > 0 ? (crop.minX - source.minX) / panX : 0
        let right = panX > 0 ? (source.maxX - crop.maxX) / panX : 0
        let top = panY > 0 ? (crop.minY - source.minY) / panY : 0
        let bottom = panY > 0 ? (source.maxY - crop.maxY) / panY : 0
        return Headroom(left: left, right: right, top: top, bottom: bottom)
    }
}

// MARK: - Small helpers

public func clamp(_ value: Double, low: Double, high: Double) -> Double {
    if high < low { return low }      // degenerate range (crop larger than source post-scale)
    return min(max(value, low), high)
}

public func normalizedOrZero(_ v: TCPoint) -> TCPoint {
    let mag = (v.x * v.x + v.y * v.y).squareRoot()
    guard mag > 0 else { return .zero }
    return TCPoint(x: v.x / mag, y: v.y / mag)
}
