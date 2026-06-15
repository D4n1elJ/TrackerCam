// Framework-free geometry value types for TrackerCamCore.
//
// The core intentionally avoids CoreGraphics/Foundation so it stays portable and unit-testable
// without the platform SDK. The iOS layer bridges these to CGPoint/CGSize/CGRect at the boundary
// (see TrackerCamCore+CoreGraphics in the app target).

public struct TCPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public static let zero = TCPoint(x: 0, y: 0)
}

public struct TCSize: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public static let zero = TCSize(width: 0, height: 0)
    public var aspectRatio: Double { height == 0 ? 0 : width / height }
}

/// Axis-aligned rectangle in a top-left origin space (x right, y down) unless stated otherwise.
public struct TCRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public static let zero = TCRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var center: TCPoint { TCPoint(x: midX, y: midY) }
    public var size: TCSize { TCSize(width: width, height: height) }
    public var area: Double { width * height }

    public init(center: TCPoint, size: TCSize) {
        self.init(x: center.x - size.width / 2,
                  y: center.y - size.height / 2,
                  width: size.width, height: size.height)
    }

    /// Smallest rectangle containing both rectangles (assumes finite, non-negative sizes).
    public func union(_ other: TCRect) -> TCRect {
        let minX = Swift.min(self.minX, other.minX)
        let minY = Swift.min(self.minY, other.minY)
        let maxX = Swift.max(self.maxX, other.maxX)
        let maxY = Swift.max(self.maxY, other.maxY)
        return TCRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Intersection-over-union with another rectangle. 0 when disjoint or degenerate.
    public func iou(_ other: TCRect) -> Double {
        let ix = Swift.max(0, Swift.min(maxX, other.maxX) - Swift.max(minX, other.minX))
        let iy = Swift.max(0, Swift.min(maxY, other.maxY) - Swift.max(minY, other.minY))
        let intersection = ix * iy
        let denom = area + other.area - intersection
        return denom <= 0 ? 0 : intersection / denom
    }

    public var isFiniteAndPositive: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0
    }

    /// Grow (or shrink, if negative) each dimension by `fraction` of its size, keeping the center.
    /// e.g. `fraction: 0.2` enlarges a 200-wide box to 240 wide.
    public func expanded(byFraction fraction: Double) -> TCRect {
        let dw = width * fraction
        let dh = height * fraction
        return TCRect(x: x - dw / 2, y: y - dh / 2, width: width + dw, height: height + dh)
    }
}
