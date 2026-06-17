import SwiftUI
import TrackerCamCore

/// Developer overlay: fps, tracking state, confidence, thermal, effective config (plan §12 Advanced).
struct DebugHUDView: View {
    let fps: Double
    let state: TrackingState
    let confidence: Double
    let thermal: String
    let config: String
    let visionFailures: Int
    let visionError: String?
    let detectionMs: Double
    let detectionInterval: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("fps", String(format: "%.0f", fps))
            row("state", state.rawValue)
            row("conf", String(format: "%.2f", confidence))
            row("thermal", thermal)
            row("fmt", config)
            row("detect", String(format: "%.0fms / %.1fs", detectionMs, detectionInterval))
            if visionFailures > 0 {
                row("vision", "\(visionFailures) failures")
            }
            if let visionError {
                row("v.err", visionError)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(.green)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).foregroundStyle(.green.opacity(0.6))
            Text(v)
        }
    }
}
