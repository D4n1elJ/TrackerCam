import CoreGraphics

// Shared geometry for the preview texture; tap hit-testing and overlay drawing must use the same
// draw rect or the selected subject will drift when the output is zoomed/cropped.
enum PreviewGeometry {
    static func textureDrawRect(viewSize: CGSize,
                                outputSize: CGSize,
                                aspectFill: Bool) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0,
              outputSize.width > 0, outputSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }

        let textureAspect = outputSize.width / outputSize.height
        let viewAspect = viewSize.width / viewSize.height
        let drawSize: CGSize
        if aspectFill {
            drawSize = viewAspect > textureAspect
                ? CGSize(width: viewSize.width, height: viewSize.width / textureAspect)
                : CGSize(width: viewSize.height * textureAspect, height: viewSize.height)
        } else {
            drawSize = viewAspect > textureAspect
                ? CGSize(width: viewSize.height * textureAspect, height: viewSize.height)
                : CGSize(width: viewSize.width, height: viewSize.width / textureAspect)
        }

        return CGRect(x: (viewSize.width - drawSize.width) / 2,
                      y: (viewSize.height - drawSize.height) / 2,
                      width: drawSize.width,
                      height: drawSize.height)
    }

    static func normalizedTexturePoint(from location: CGPoint,
                                       viewSize: CGSize,
                                       outputSize: CGSize,
                                       aspectFill: Bool) -> CGPoint? {
        let draw = textureDrawRect(viewSize: viewSize, outputSize: outputSize, aspectFill: aspectFill)
        guard draw.width > 0, draw.height > 0 else { return nil }

        let x = (location.x - draw.minX) / draw.width
        let y = (location.y - draw.minY) / draw.height
        if !aspectFill, (x < 0 || x > 1 || y < 0 || y > 1) {
            return nil
        }

        return CGPoint(x: min(1, max(0, x)),
                       y: min(1, max(0, y)))
    }
}
