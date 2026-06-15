import SwiftUI
import TrackerCamCore

/// Main recording screen (plan §12 UX). Controls optimized for a right-hand landscape grip.
struct CameraView: View {
    @State var viewModel: CameraViewModel
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if viewModel.permissionDenied {
                    PermissionDeniedView()
                } else {
                    MetalPreviewView(viewModel: viewModel)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            viewModel.refocus(atNormalizedPoint: CGPoint(
                                x: location.x / geo.size.width,
                                y: location.y / geo.size.height))
                        }

                    OverlayView(state: viewModel.trackingState,
                                subjectRect: viewModel.subjectViewRect,
                                hint: viewModel.guidanceHint,
                                viewSize: geo.size)

                    controls
                }
            }
        }
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var controls: some View {
        VStack {
            HStack {
                statusBadge
                Spacer()
                Text(viewModel.effectiveConfigSummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()

            Spacer()

            // Right-hand grip: primary controls hug the trailing edge (plan §12).
            HStack {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.title2)
                }
                .frame(width: 52, height: 52)
                .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 20) {
                    Button { viewModel.refocus() } label: {
                        Image(systemName: "scope").font(.title2)
                    }
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white)

                    RecordButton(isRecording: viewModel.isRecording, elapsed: viewModel.elapsed) {
                        viewModel.toggleRecording()
                    }
                }
            }
            .padding(24)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(viewModel.trackingState.label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
    }

    private var statusColor: Color {
        switch viewModel.trackingState {
        case .idle: return .gray
        case .searching: return .yellow
        case .locked, .tracking: return .green
        case .lost: return .red
        }
    }
}

private struct RecordButton: View {
    let isRecording: Bool
    let elapsed: TimeInterval
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if isRecording {
                Text(timeString).font(.caption.monospacedDigit()).foregroundStyle(.white)
            }
            Button(action: action) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: isRecording ? 6 : 32)
                        .fill(.red)
                        .frame(width: isRecording ? 30 : 60, height: isRecording ? 30 : 60)
                        .animation(.easeInOut(duration: 0.2), value: isRecording)
                }
            }
            .frame(minWidth: 60, minHeight: 60)
        }
    }

    private var timeString: String {
        let s = Int(elapsed)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            Text("Camera & microphone access required")
                .multilineTextAlignment(.center)
            Text("Enable access in Settings to use TrackerCam.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

extension TrackingState {
    var label: String {
        switch self {
        case .idle: return "Tap to track"
        case .searching: return "Searching…"
        case .locked: return "Locked"
        case .tracking: return "Tracking"
        case .lost: return "Target lost"
        }
    }
}
