/// Computes operator pan/aim hints from framing error, predicted drift, and crop headroom.
/// Plan §11 Framing Guidance System. This is camera-aiming guidance, never navigation advice.
/// Framework-free / pure so it can be unit-tested without the app.
public struct GuidanceEngine: Sendable {
    public enum Severity: Sendable { case none, normal, amber, red }

    public struct Hint: Sendable {
        /// Unit direction in source space (x right, y down) the operator should pan toward.
        public var direction: TCPoint
        /// Magnitude relative to frame size (0 = centered).
        public var magnitude: Double
        public var severity: Severity
        public init(direction: TCPoint, magnitude: Double, severity: Severity) {
            self.direction = direction; self.magnitude = magnitude; self.severity = severity
        }
    }

    public var deadZoneFraction: Double   // settings.guidanceDeadZone
    public var lookaheadSeconds: Double   // settings.guidanceLookahead

    public init(deadZoneFraction: Double, lookaheadSeconds: Double) {
        self.deadZoneFraction = deadZoneFraction
        self.lookaheadSeconds = lookaheadSeconds
    }

    public func hint(subjectCenter: TCPoint,
                     predictedVelocity: TCPoint,
                     source: TCRect,
                     crop: TCRect) -> Hint {
        let frameCenter = source.center
        let errorX = subjectCenter.x - frameCenter.x + predictedVelocity.x * lookaheadSeconds
        let errorY = subjectCenter.y - frameCenter.y + predictedVelocity.y * lookaheadSeconds

        let normX = errorX / source.width
        let normY = errorY / source.height
        let magnitude = (normX * normX + normY * normY).squareRoot()

        if magnitude < deadZoneFraction {
            return Hint(direction: .zero, magnitude: magnitude, severity: .none)
        }

        let headroom = CropMath.headroom(crop: crop, source: source)
        let minHeadroom = min(headroom.left, headroom.right, headroom.top, headroom.bottom)
        let severity: Severity
        if minHeadroom < 0.08 { severity = .red }          // plan §10 edge thresholds
        else if minHeadroom < 0.20 { severity = .amber }
        else { severity = .normal }

        return Hint(direction: normalizedOrZero(TCPoint(x: errorX, y: errorY)),
                    magnitude: magnitude,
                    severity: severity)
    }
}
