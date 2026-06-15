import SwiftUI

/// First-launch tutorial (plan §12 Onboarding). Explains the core interaction model and the
/// ground-operator safety constraint before recording.
struct OnboardingView: View {
    var onDone: () -> Void

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(symbol: "camera.fill",
             title: "Welcome to TrackerCam",
             body: "TrackerCam films a moving subject and keeps it framed for you, recording a smooth, tracked 1080p video."),
        Page(symbol: "hand.tap.fill",
             title: "Tap or Refocus to track",
             body: "Tracking starts automatically. Tap the subject, or press Refocus, to choose a different one. Recording starts and stops only when you press Record."),
        Page(symbol: "arrow.left.arrow.right",
             title: "Arrows guide your aim",
             body: "Edge arrows show which way to pan the phone to keep the subject framed. They are a camera-aiming aid only — keep your attention on your surroundings."),
        Page(symbol: "figure.walk",
             title: "Stay safe",
             body: "Use TrackerCam while standing or walking. Do not run, ride, or navigate while watching the screen."),
    ]

    @State private var index = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                    VStack(spacing: 20) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.tint)
                        Text(page.title).font(.title.bold()).multilineTextAlignment(.center)
                        Text(page.body)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 32)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Spacer()
            Button(index == pages.count - 1 ? "Get Started" : "Next") {
                if index == pages.count - 1 { onDone() }
                else { withAnimation { index += 1 } }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.tint, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
