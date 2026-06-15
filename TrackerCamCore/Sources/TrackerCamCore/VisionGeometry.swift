/// Converts between Vision's normalized coordinate space (origin bottom-left, y upward, [0,1])
/// and TrackerCam's canonical source-pixel space (origin top-left, y downward). See plan §10.
public enum VisionGeometry {

    /// Vision normalized rect (bottom-left origin) → source pixel rect (top-left origin).
    public static func pixelRect(fromNormalized n: TCRect, imageSize size: TCSize) -> TCRect {
        let w = n.width * size.width
        let h = n.height * size.height
        let x = n.x * size.width
        // Flip Y: the normalized top edge measured from the bottom is (n.y + n.height);
        // its distance from the top is 1 - (n.y + n.height).
        let y = (1.0 - (n.y + n.height)) * size.height
        return TCRect(x: x, y: y, width: w, height: h)
    }

    /// Source pixel rect (top-left origin) → Vision normalized rect (bottom-left origin).
    public static func normalizedRect(fromPixel p: TCRect, imageSize size: TCSize) -> TCRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let w = p.width / size.width
        let h = p.height / size.height
        let x = p.x / size.width
        // Inverse of the Y flip above.
        let y = 1.0 - (p.y + p.height) / size.height
        return TCRect(x: x, y: y, width: w, height: h)
    }
}
