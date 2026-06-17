/// Stateful crop smoother (plan §10). Converts a per-frame *desired* crop center/size into a
/// rate-limited, source-clamped crop so the output never snaps:
///  - asymmetric zoom: recover headroom quickly (zoom out), avoid pumping (zoom in slowly);
///  - bounded crop-center speed.
/// Operates on crop *height* as the scale variable; width follows the desired aspect ratio.
public struct CropController: Sendable {
    public private(set) var isInitialized = false

    private let maxCenterSpeed: Double       // source-frame-widths per second
    private let maxZoomOutRate: Double        // fractional crop-size growth per second
    private let maxZoomInRate: Double         // fractional crop-size shrink per second
    private let zoomInHysteresisBand: Double  // crop must shrink past this fraction to zoom in
    private let zoomInHoldSeconds: Double     // ...and stay there this long before zooming in
    private let minCropFraction: Double       // floor on crop size as a fraction of the source

    private var currentCenter: TCPoint = .zero
    private var currentSize: TCSize = .zero
    private var timeBelowBand: Double = 0      // how long the desired crop has wanted to shrink

    public init(maxCenterSpeed: Double = 1.5,
                maxZoomOutRate: Double = 0.8,
                maxZoomInRate: Double = 0.25,
                zoomInHysteresisBand: Double = 0.05,
                zoomInHoldSeconds: Double = 0.15,
                minCropFraction: Double = 0.45) {
        self.maxCenterSpeed = maxCenterSpeed
        self.maxZoomOutRate = maxZoomOutRate
        self.maxZoomInRate = maxZoomInRate
        self.zoomInHysteresisBand = zoomInHysteresisBand
        self.zoomInHoldSeconds = zoomInHoldSeconds
        self.minCropFraction = minCropFraction
    }

    public mutating func reset() {
        isInitialized = false
        currentCenter = .zero
        currentSize = .zero
        timeBelowBand = 0
    }

    public mutating func update(dt: Double,
                                desiredCenter: TCPoint,
                                desiredSize: TCSize,
                                source: TCRect) -> TCRect {
        if !isInitialized {
            currentCenter = desiredCenter
            currentSize = desiredSize
            isInitialized = true
        } else {
            currentSize = rateLimitedSize(toward: desiredSize, dt: dt)
            currentCenter = rateLimitedCenter(toward: desiredCenter, dt: dt, source: source)
        }
        // Clamp into the source (enforcing the close-up floor) and continue from the actual result.
        let crop = CropMath.clampedCrop(center: currentCenter, size: currentSize,
                                        source: source, minSizeFraction: minCropFraction)
        currentCenter = crop.center
        currentSize = crop.size
        return crop
    }

    /// Limit crop-size change asymmetrically on height; width follows the desired aspect ratio.
    /// Zoom-out is immediate; zoom-in requires the desired crop to stay below a hysteresis band
    /// for a hold time first (prevents pumping on noisy boxes — plan §10).
    private mutating func rateLimitedSize(toward desired: TCSize, dt: Double) -> TCSize {
        let aspect = desired.height > 0 ? desired.width / desired.height : currentSize.aspectRatio
        let curH = currentSize.height
        guard curH > 0 else { return desired }
        let ratio = desired.height / curH

        let clampedRatio: Double
        if ratio < 1 {
            // Wants to zoom in (crop shrink). Apply hysteresis.
            let belowBand = desired.height < curH * (1 - zoomInHysteresisBand)
            timeBelowBand = belowBand ? timeBelowBand + dt : 0
            if !belowBand || timeBelowBand < zoomInHoldSeconds {
                return currentSize  // suppress zoom-in (hold current size)
            }
            clampedRatio = max(ratio, 1 - maxZoomInRate * dt)  // eligible: slow zoom-in
        } else {
            timeBelowBand = 0
            clampedRatio = min(ratio, 1 + maxZoomOutRate * dt) // zoom-out: fast, immediate
        }
        let newH = curH * clampedRatio
        return TCSize(width: newH * aspect, height: newH)
    }

    /// Limit how far the crop center can move per frame.
    private func rateLimitedCenter(toward desired: TCPoint, dt: Double, source: TCRect) -> TCPoint {
        let maxMove = maxCenterSpeed * source.width * dt
        let dx = desired.x - currentCenter.x
        let dy = desired.y - currentCenter.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist > maxMove, dist > 0 else { return desired }
        let s = maxMove / dist
        return TCPoint(x: currentCenter.x + dx * s, y: currentCenter.y + dy * s)
    }
}
