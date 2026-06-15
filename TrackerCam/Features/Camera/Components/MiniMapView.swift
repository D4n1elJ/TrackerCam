import SwiftUI

/// Small inset showing the full sensor frame with the current crop window, so the operator can
/// see remaining headroom (plan §12 Mini-Map). `cropFraction` is the crop in normalized [0,1]
/// source coordinates.
struct MiniMapView: View {
    let cropFraction: CGRect?
    var aspect: CGFloat = 16.0 / 9.0
    private let width: CGFloat = 120

    var body: some View {
        let height = width / aspect
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.black.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.4), lineWidth: 1))

            if let c = cropFraction {
                Rectangle()
                    .stroke(.green, lineWidth: 1.5)
                    .frame(width: max(2, c.width * width), height: max(2, c.height * height))
                    .offset(x: c.minX * width, y: c.minY * height)
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("Crop position within full frame")
    }
}
