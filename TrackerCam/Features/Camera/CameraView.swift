import SwiftUI
import UIKit
import TrackerCamCore

/// Main recording screen (plan §12 UX). Controls optimized for a right-hand landscape grip.
struct CameraView: View {
    @State var viewModel: CameraViewModel
    @State private var showSettings = false
    @State private var showRecordings = false
    @AppStorage("trackercam.hasOnboarded") private var hasOnboarded = false
    @AppStorage("trackercam.showDebugHUD") private var showDebugHUD = false
    @AppStorage("trackercam.showGrid") private var showGrid = false
    @AppStorage("trackercam.previewAspectFill") private var previewAspectFill = true
    private let detectorAvailable = DetectionService.isBundledModelAvailable

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if viewModel.permissionDenied {
                    PermissionDeniedView()
                } else {
                    MetalPreviewView(viewModel: viewModel, aspectFill: previewAspectFill)
                        .ignoresSafeArea()
                        .accessibilityLabel("Camera preview")
                        .accessibilityValue(viewModel.trackingState.label)
                        .accessibilityAction(named: Text("Refocus tracking")) {
                            viewModel.refocus()
                        }
                        .accessibilityAction(named: Text("Release target")) {
                            viewModel.clearTarget()
                        }

                    if showGrid { GridOverlayView() }

                    OverlayView(state: viewModel.trackingState,
                                subjectRect: viewModel.subjectViewRect,
                                hint: viewModel.guidanceHint,
                                confidence: viewModel.confidence,
                                viewSize: geo.size)

                    previewTapLayer(size: geo.size)

                    controls
                }
            }
            .overlay(alignment: .top) {
                if let cd = viewModel.storageCountdown {
                    Text("Storage full — stopping in \(cd)s")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 90)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showDebugHUD && !viewModel.permissionDenied {
                    DebugHUDView(fps: viewModel.fps, state: viewModel.trackingState,
                                 confidence: viewModel.confidence, thermal: viewModel.thermalLevelText,
                                 config: viewModel.effectiveConfigSummary,
                                 visionFailures: viewModel.visionFailureCount,
                                 visionError: viewModel.lastVisionErrorDescription,
                                 detectionMs: viewModel.detectionMs,
                                 detectionInterval: viewModel.effectiveDetectionInterval)
                        .padding(.top, 56).padding(.trailing, 12)
                }
            }
            .overlay(alignment: .leading) {
                // Live dynamic-crop control: drag up to zoom in (tighter), down to widen.
                if !viewModel.permissionDenied && viewModel.settingsStore.settings.dynamicZoomEnabled {
                    VStack {
                        Spacer(minLength: 120)
                        ZoomSlider(value: zoomBinding, range: 0.12...0.55)
                        Spacer(minLength: 120)
                    }
                    .padding(.leading, 12)
                }
            }
        }
        .task(id: hasOnboarded) { if hasOnboarded { await viewModel.onAppear() } }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showRecordings) { RecordingsView() }
        // Hardware Camera Control / volume buttons start-stop recording (plan §14). Device-only.
        .onCameraCaptureEvent { event in
            if event.phase == .ended { viewModel.toggleRecording() }
        }
        .sheet(isPresented: .constant(!hasOnboarded)) {
            OnboardingView { hasOnboarded = true }
                .interactiveDismissDisabled()
        }
    }

    private func previewTapLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .gesture(
                SpatialTapGesture(count: 2, coordinateSpace: .local)
                    .onEnded { _ in viewModel.clearTarget() },
                including: .gesture
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 1, coordinateSpace: .local)
                    .onEnded { value in
                        guard size.width > 0, size.height > 0 else { return }
                        viewModel.refocus(atNormalizedPoint: CGPoint(
                            x: value.location.x / size.width,
                            y: value.location.y / size.height))
                    },
                including: .gesture
            )
            .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack {
            HStack {
                statusBadge
                Spacer()
                if viewModel.batteryLow {
                    Label("Low battery", systemImage: "battery.25")
                        .font(.caption2.bold()).foregroundStyle(.orange)
                }
                Text(effectiveConfigLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .padding()

            if viewModel.settingsStore.settings.showMiniMap {
                HStack {
                    MiniMapView(cropFraction: viewModel.cropInSourceRect, aspect: miniMapAspect)
                    Spacer()
                }
                .padding(.horizontal)
            }

            Spacer()

            // Right-hand grip: primary controls hug the trailing edge (plan §12).
            HStack {
                VStack(spacing: 16) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill").font(.title2)
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityLabel("Settings")
                    Button { showRecordings = true } label: {
                        Image(systemName: "film.stack").font(.title2)
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityLabel("Recordings")
                }
                .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 20) {
                    Button { viewModel.refocus() } label: {
                        Image(systemName: "scope").font(.title2)
                    }
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white)
                    .accessibilityLabel("Refocus tracking")
                    .accessibilityHint("Re-acquire the subject")

                    RecordButton(isRecording: viewModel.isRecording, elapsed: viewModel.elapsed) {
                        viewModel.toggleRecording()
                    }
                    .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(24)
            .padding(.leading, viewModel.settingsStore.settings.dynamicZoomEnabled ? 84 : 0)
        }
    }

    /// Two-way binding into the persisted dynamic-crop tightness (subject height fraction).
    private var zoomBinding: Binding<Double> {
        Binding(
            get: { viewModel.settingsStore.settings.targetSubjectHeight },
            set: { viewModel.settingsStore.settings.targetSubjectHeight = $0 }
        )
    }

    private var miniMapAspect: CGFloat {
        let r = viewModel.settingsStore.settings.aspectRatio.ratio
        return r > 0 ? CGFloat(r) : 16.0 / 9.0
    }

    private var effectiveConfigLabel: String {
        viewModel.effectiveConfigSummary == "Camera config failed: noCamera"
            ? "No camera"
            : viewModel.effectiveConfigSummary
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusLabel).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var statusLabel: String {
        if viewModel.trackingState == .idle {
            guard detectorAvailable else { return "Tap to track" }
            switch viewModel.settingsStore.settings.acquisitionMode {
            case .tap: return "Tap to track"
            case .auto: return "Auto acquire"
            case .autoRefocus: return "Auto/refocus"
            }
        }
        return viewModel.trackingState.label
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

/// Vertical zoom slider for the live viewfinder. Bound to the dynamic-crop subject-height
/// fraction: rotating the slider puts the max (tightest) value at the top, so dragging up zooms in.
private struct ZoomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.magnifyingglass")
            Slider(value: $value, in: range)
                .frame(width: 160)
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 160)
            Image(systemName: "minus.magnifyingglass")
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
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
                    .accessibilityAddTraits(.updatesFrequently)
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
            Text("Camera access required")
                .multilineTextAlignment(.center)
            Text("Enable access in Settings to use TrackerCam.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
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
