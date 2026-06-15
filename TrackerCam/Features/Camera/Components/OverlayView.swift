import SwiftUI
import TrackerCamCore

/// Bounding box + guidance chevrons over the preview (plan §11/§12).
struct OverlayView: View {
    let state: TrackingState
    let subjectRect: CGRect?     // normalized [0,1] in preview space
    let hint: GuidanceEngine.Hint?
    let viewSize: CGSize

    var body: some View {
        ZStack {
            if let r = subjectRect, state != .idle {
                let frame = CGRect(x: r.minX * viewSize.width, y: r.minY * viewSize.height,
                                   width: r.width * viewSize.width, height: r.height * viewSize.height)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(boxColor, style: StrokeStyle(lineWidth: 3, dash: state == .lost ? [8, 6] : []))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }

            if let hint, hint.severity != .none {
                ChevronArrows(direction: hint.direction, color: hintColor(hint.severity))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: subjectRect)
    }

    private var boxColor: Color {
        switch state {
        case .searching: return .yellow
        case .locked, .tracking: return .green
        case .lost: return .red
        case .idle: return .clear
        }
    }

    private func hintColor(_ s: GuidanceEngine.Severity) -> Color {
        switch s {
        case .none, .normal: return .white
        case .amber: return .orange
        case .red: return .red
        }
    }
}

private struct ChevronArrows: View {
    let direction: TCPoint   // x right, y down (source space)
    let color: Color

    var body: some View {
        // Pick the edge nearest the dominant component of the hint.
        let horizontal = abs(direction.x) >= abs(direction.y)
        let systemName: String = horizontal
            ? (direction.x > 0 ? "chevron.right" : "chevron.left")
            : (direction.y > 0 ? "chevron.down" : "chevron.up")

        return HStack {
            if horizontal && direction.x < 0 { arrows(systemName) }
            Spacer()
            if horizontal && direction.x > 0 { arrows(systemName) }
        }
        .overlay(alignment: .top) { if !horizontal && direction.y < 0 { arrows(systemName) } }
        .overlay(alignment: .bottom) { if !horizontal && direction.y > 0 { arrows(systemName) } }
        .padding(24)
    }

    private func arrows(_ name: String) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(color.opacity(1.0 - Double(i) * 0.25))
            }
        }
    }
}
