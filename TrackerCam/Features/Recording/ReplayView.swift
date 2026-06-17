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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VideoPlayer(player: player)
                if let s = subject {
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
        }
        .ignoresSafeArea()
        .onAppear {
            frames = Sidecar.load(videoURL: url)
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            observer = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { time in
                subject = Sidecar.subject(at: time.seconds, in: frames)
            }
            player.play()
        }
        .onDisappear {
            if let observer { player.removeTimeObserver(observer); self.observer = nil }
            player.pause()
        }
    }

    static func aspectFit(_ content: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / content.width, container.height / content.height)
        let w = content.width * scale, h = content.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
