import SwiftUI
import TrackerCamCore

/// Bounding box + guidance chevrons over the preview (plan §11/§12).
struct OverlayView: View {
    let state: TrackingState
    let subjectRect: CGRect?     // normalized [0,1] in preview space
    let selectedSeedRect: CGRect?
    let debugDetectionRect: CGRect?
    let debugDetectionAccepted: Bool
    let showDebug: Bool
    let hint: GuidanceEngine.Hint?
    let confidence: Double
    let outputSize: CGSize
    let aspectFill: Bool
    let viewSize: CGSize

    var body: some View {
        ZStack {
            if showDebug, let r = debugDetectionRect {
                debugBox(rect: r,
                         color: debugDetectionAccepted ? .mint : .orange,
                         label: debugDetectionAccepted ? "detect accepted" : "detect rejected",
                         dash: [7, 5])
            }

            if let r = selectedSeedRect {
                debugBox(rect: r, color: .cyan, label: showDebug ? "tap seed" : nil, dash: [5, 4])
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

                if showDebug {
                    label("track", color: boxColor)
                        .position(x: frame.midX, y: max(12, frame.minY - 10))
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
        .animation(.easeOut(duration: 0.12), value: debugDetectionRect)
    }

    private func viewFrame(for rect: CGRect) -> CGRect {
        let draw = textureDrawRect()
        return CGRect(x: draw.minX + rect.minX * draw.width,
                      y: draw.minY + rect.minY * draw.height,
                      width: rect.width * draw.width,
                      height: rect.height * draw.height)
    }

    private func textureDrawRect() -> CGRect {
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

    private func debugBox(rect: CGRect, color: Color, label text: String?, dash: [CGFloat]) -> some View {
        let frame = viewFrame(for: rect)
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dash))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            if let text {
                label(text, color: color)
                    .position(x: frame.midX, y: max(12, frame.minY - 10))
            }
        }
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.65), in: Capsule())
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
