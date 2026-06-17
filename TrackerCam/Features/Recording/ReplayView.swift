import SwiftUI
import AVKit
import AVFoundation

/// Plays a saved clip with the tracking box overlaid from its sidecar (coaching review, plan §14).
/// Falls back to plain playback when no `.ndjson` sidecar exists.
struct ReplayView: View {
    let url: URL
    var outputAspect: CGSize = CGSize(width: 16, height: 9)

    @State private var player = AVPlayer()
    @State private var frames: [SidecarFrame] = []
    @State private var subject: CGRect?
    @State private var observer: Any?
    @State private var currentTime: Double = 0
    @State private var showTrackingOverlay = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VideoPlayer(player: player)
                if showTrackingOverlay, let s = subject {
                    let fit = Self.aspectFit(outputAspect, in: geo.size)
                    let w = s.width * fit.width, h = s.height * fit.height
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.green, lineWidth: 2)
                        .frame(width: max(2, w), height: max(2, h))
                        .position(x: fit.minX + (s.minX + s.width / 2) * fit.width,
                                  y: fit.minY + (s.minY + s.height / 2) * fit.height)
                        .allowsHitTesting(false)
                }
            }
            reviewHUD
        }
        .ignoresSafeArea()
        .onAppear {
            let loadedFrames = Sidecar.load(videoURL: url)
            frames = loadedFrames
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            observer = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { time in
                let seconds = time.seconds
                let currentSubject = Sidecar.subject(at: seconds, in: loadedFrames)
                Task { @MainActor in
                    currentTime = seconds
                    subject = currentSubject
                }
            }
            player.play()
        }
        .onDisappear {
            if let observer { player.removeTimeObserver(observer); self.observer = nil }
            player.pause()
        }
    }

    private var reviewHUD: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Label(frames.isEmpty ? "No tracking metadata" : "\(frames.count) tracking frames",
                      systemImage: frames.isEmpty ? "rectangle.slash" : "scope")
                Text(Self.timeString(currentTime))
                    .monospacedDigit()
                Spacer()
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share recording")
                Toggle("Overlay", isOn: $showTrackingOverlay)
                    .labelsHidden()
                    .disabled(frames.isEmpty)
                Text("Overlay")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.65), in: Capsule())
            .padding(.bottom, 24)
            .padding(.horizontal)
        }
        .allowsHitTesting(true)
    }

    private static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func aspectFit(_ content: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / content.width, container.height / content.height)
        let w = content.width * scale, h = content.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
