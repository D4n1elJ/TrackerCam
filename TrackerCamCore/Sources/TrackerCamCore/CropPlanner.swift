/// Decides the *desired* crop (center + size) for the current tracking state, including the
/// lost-recovery ladder. Plan §10 Crop State Machine. The result is fed to `CropController`,
/// which rate-limits the transition. Pure / stateless.
///
/// Lost ladder:
///  - `< lostPredictSeconds`: continue constant-velocity prediction while zooming out;
///  - `lostPredictSeconds … lostEaseEndSeconds`: ease the center toward the source center;
///  - `> lostEaseEndSeconds`: hold a centered max-zoom-out crop.
public struct CropPlanner: Sendable {
    public var lostPredictSeconds: Double
    public var lostEaseEndSeconds: Double
    public var searchingWiden: Double

    public init(lostPredictSeconds: Double = 0.75,
                lostEaseEndSeconds: Double = 2.0,
                searchingWiden: Double = 0.15) {
        self.lostPredictSeconds = lostPredictSeconds
        self.lostEaseEndSeconds = lostEaseEndSeconds
        self.searchingWiden = searchingWiden
    }

    public func plan(state: TrackingState,
                     secondsSinceLost: Double,
                     lastCenter: TCPoint,
                     velocity: TCPoint,
                     trackingDesiredCenter: TCPoint?,
                     trackingDesiredSize: TCSize?,
                     defaultSize: TCSize,
                     source: TCRect) -> (center: TCPoint, size: TCSize) {
        let maxOut = Self.maxAspectCrop(aspect: defaultSize.aspectRatio, in: source)

        switch state {
        case .idle:
            return (source.center, defaultSize)

        case .searching:
            let widened = TCSize(width: defaultSize.width * (1 + searchingWiden),
                                 height: defaultSize.height * (1 + searchingWiden))
            return (lastCenter, widened)

        case .locked, .tracking:
            return (trackingDesiredCenter ?? lastCenter, trackingDesiredSize ?? defaultSize)

        case .lost:
            let t = secondsSinceLost
            if t < lostPredictSeconds {
                // Continue constant-velocity prediction while zooming out.
                let c = TCPoint(x: lastCenter.x + velocity.x * t,
                                y: lastCenter.y + velocity.y * t)
                return (c, maxOut)
            } else if t < lostEaseEndSeconds {
                // Ease the (capped) predicted center toward the source center.
                let predicted = TCPoint(x: lastCenter.x + velocity.x * lostPredictSeconds,
                                        y: lastCenter.y + velocity.y * lostPredictSeconds)
                let factor = (t - lostPredictSeconds) / (lostEaseEndSeconds - lostPredictSeconds)
                let c = TCPoint(x: predicted.x + (source.midX - predicted.x) * factor,
                                y: predicted.y + (source.midY - predicted.y) * factor)
                return (c, maxOut)
            } else {
                // Hold a centered max-zoom-out crop.
                return (source.center, maxOut)
            }
        }
    }

    /// Largest crop of the given aspect ratio that fits inside the source.
    static func maxAspectCrop(aspect: Double, in source: TCRect) -> TCSize {
        guard aspect > 0 else { return source.size }
        if source.width / source.height >= aspect {
            return TCSize(width: source.height * aspect, height: source.height)   // height-bound
        } else {
            return TCSize(width: source.width, height: source.width / aspect)      // width-bound
        }
    }
}
