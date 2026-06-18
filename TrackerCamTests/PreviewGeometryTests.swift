import CoreGraphics
import Testing
@testable import TrackerCam

struct PreviewGeometryTests {
    @Test func aspectFillPointUsesDrawnTextureRect() {
        let viewSize = CGSize(width: 100, height: 100)
        let outputSize = CGSize(width: 16, height: 9)

        // Aspect-fill draws a 177.78 pt wide texture into the 100 pt view, cropping both sides.
        // A tap on the visible left edge is therefore not the left edge of the source texture.
        let p = PreviewGeometry.normalizedTexturePoint(from: CGPoint(x: 0, y: 50),
                                                       viewSize: viewSize,
                                                       outputSize: outputSize,
                                                       aspectFill: true)

        #expect(abs((p?.x ?? -1) - 0.21875) < 0.0001)
        #expect(abs((p?.y ?? -1) - 0.5) < 0.0001)
    }

    @Test func aspectFitRejectsLetterboxTaps() {
        let viewSize = CGSize(width: 100, height: 100)
        let outputSize = CGSize(width: 16, height: 9)

        let p = PreviewGeometry.normalizedTexturePoint(from: CGPoint(x: 50, y: 0),
                                                       viewSize: viewSize,
                                                       outputSize: outputSize,
                                                       aspectFill: false)

        #expect(p == nil)
    }
}
