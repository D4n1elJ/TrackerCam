import SwiftUI
import TrackerCamCore

/// Bounding box + guidance chevrons over the preview (plan §11/§12).
struct OverlayView: View {
    let state: TrackingState
    let subjectRect: CGRect?     // normalized [0,1] in preview space
    let selectedSeedRect: CGRect?
    let hint: GuidanceEngine.Hint?
    let confidence: Double
    let viewSize: CGSize

    var body: some View {
        ZStack {
            if let r = selectedSeedRect {
                let frame = viewFrame(for: r)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.cyan, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }

            if let r = subjectRect, state != .idle {
                let frame = viewFrame(for: r)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(boxColor, style: StrokeStyle(lineWidth: 3, dash: state == .lost ? [8, 6] : []))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                // Confidence ring — early warning before loss (plan §12).
                if state == .tracking || state == .locked {
                    let d = max(frame.width, frame.height) + 24
                    Circle()
                        .trim(from: 0, to: max(0, min(1, confidence)))
                        .stroke(boxColor.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d, height: d)
                        .position(x: frame.midX, y: frame.midY)
                }
            }

            if let hint, hint.severity != .none {
                ChevronArrows(direction: hint.direction, color: hintColor(hint.severity))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.12), value: subjectRect)
        .animation(.easeOut(duration: 0.12), value: selectedSeedRect)
    }

    private func viewFrame(for rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * viewSize.width, y: rect.minY * viewSize.height,
               width: rect.width * viewSize.width, height: rect.height * viewSize.height)
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
