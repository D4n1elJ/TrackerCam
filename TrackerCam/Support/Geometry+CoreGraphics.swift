import CoreGraphics
import TrackerCamCore

// Bridges the framework-free core geometry types to CoreGraphics at the app boundary.
// The core stays portable/testable; only the app depends on CoreGraphics.

extension TCPoint {
    var cg: CGPoint { CGPoint(x: x, y: y) }
    init(_ p: CGPoint) { self.init(x: Double(p.x), y: Double(p.y)) }
}

extension TCSize {
    var cg: CGSize { CGSize(width: width, height: height) }
    init(_ s: CGSize) { self.init(width: Double(s.width), height: Double(s.height)) }
}

extension TCRect {
    var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    init(_ r: CGRect) {
        self.init(x: Double(r.origin.x), y: Double(r.origin.y),
                  width: Double(r.size.width), height: Double(r.size.height))
    }
}
