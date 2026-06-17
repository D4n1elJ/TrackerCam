import SwiftUI
import TrackerCamCore

/// Settings UI (plan §13). Presets first; advanced numeric controls available but not required.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trackercam.showDebugHUD") private var showDebugHUD = false
    @AppStorage("trackercam.showGrid") private var showGrid = false
    @AppStorage("trackercam.previewAspectFill") private var previewAspectFill = true
    private let cameraCapabilities = CameraService.discoverCapabilities()
    private let detectorAvailable = DetectionService.isBundledModelAvailable

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Tracking") {
                    Picker("Acquisition", selection: $store.settings.acquisitionMode) {
                        acquisitionOption("Auto", .auto)
                        Text("Tap").tag(AcquisitionMode.tap)
                        acquisitionOption("Auto + Refocus", .autoRefocus)
                    }
                    if !detectorAvailable {
                        Text("Auto acquisition requires the bundled horse detection model. Tap-to-track remains available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    slider("Re-detection (s)", $store.settings.redetectionInterval, 0.1...5.0)
                    slider("Lost timeout (s)", $store.settings.lostTrackTimeout, 0.1...3.0)
                    slider("Confidence", $store.settings.confidenceThreshold, 0.0...1.0)
                    slider("Smoothing", $store.settings.smoothingStrength, 0.0...1.0)
                }

                Section("Framing") {
                    Toggle("Rule-of-thirds grid", isOn: $showGrid)
                    Picker("Aspect", selection: $store.settings.aspectRatio) {
                        Text("16:9").tag(AspectRatioMode.landscape16x9)
                        Text("9:16").tag(AspectRatioMode.portrait9x16)
                        Text("1:1").tag(AspectRatioMode.square1x1)
                        Text("Full").tag(AspectRatioMode.fullFrame)
                    }
                    Toggle("Fill screen (crop edges)", isOn: $previewAspectFill)
                    Toggle("Dynamic zoom", isOn: $store.settings.dynamicZoomEnabled)
                    slider("Subject height", $store.settings.targetSubjectHeight, 0.12...0.55)
                    slider("Padding", $store.settings.subjectPadding, 0.10...0.35)
                    slider("Minimum scene", $store.settings.minCropFraction, 0.25...0.90)
                    slider("Lead", $store.settings.compositionLeadFraction, 0.0...0.20)
                    Toggle("Mini-map", isOn: $store.settings.showMiniMap)
                }

                Section("Camera") {
                    Picker("Resolution", selection: $store.settings.outputResolution) {
                        Text("1080p tracked").tag(OutputResolution.tracked1080p)
                        Text("4K full-frame").tag(OutputResolution.full4K)
                    }
                    Picker("Frame rate", selection: $store.settings.frameRate) {
                        frameRateOption("30", .fps30)
                        frameRateOption("60 (preferred)", .preferred60)
                        frameRateOption("100 (experimental)", .experimental100)
                        frameRateOption("120 (experimental)", .experimental120)
                    }
                    Text(cameraCapabilities.summary)
                        .font(.caption)
                        .foregroundStyle(cameraCapabilities.supports4K60 ? Color.secondary : Color.orange)
                }

                Section("Guidance") {
                    Toggle("Arrows", isOn: $store.settings.guidanceEnabled)
                    slider("Dead zone", $store.settings.guidanceDeadZone, 0.03...0.20)
                    slider("Lookahead (s)", $store.settings.guidanceLookahead, 0.0...1.0)
                    Toggle("Haptics", isOn: $store.settings.guidanceHaptics)
                }

                Section("Recording") {
                    Picker("Mode", selection: $store.settings.recordingMode) {
                        Text("Tracked only").tag(RecordingMode.trackedOnly)
                        Text("Full only").tag(RecordingMode.fullOnly)
                    }
                    Picker("Save to", selection: $store.settings.saveDestination) {
                        Text("App").tag(SaveDestination.app)
                        Text("Photos").tag(SaveDestination.photos)
                        Text("Both").tag(SaveDestination.both)
                    }
                    Toggle("Overlay in recording", isOn: $store.settings.overlayInRecording)
                    Toggle("Export crop metadata (.ndjson)", isOn: $store.settings.exportCropMetadata)
                }

                Section("Advanced") {
                    Picker("Detection model", selection: $store.settings.detectionModel) {
                        Text("Standard").tag(DetectionModel.standard)
                        Text("Equestrian").tag(DetectionModel.equestrian)
                    }
                    Toggle("Show debug HUD", isOn: $showDebugHUD)
                }

                Section {
                    Button("Reset to defaults", role: .destructive) { store.resetToDefaults() }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                clampUnsupportedAcquisitionMode(store: store)
                clampUnsupportedFrameRate(store: store)
            }
            .onChange(of: store.settings.acquisitionMode) { _, _ in
                clampUnsupportedAcquisitionMode(store: store)
            }
            .onChange(of: store.settings.frameRate) { _, newValue in
                if !cameraCapabilities.supports(newValue) {
                    store.settings.frameRate = cameraCapabilities.bestAvailablePreset
                }
            }
        }
    }

    private func acquisitionOption(_ title: String, _ mode: AcquisitionMode) -> some View {
        Text(detectorAvailable ? title : "\(title) unavailable")
            .tag(mode)
            .disabled(!detectorAvailable)
    }

    private func clampUnsupportedAcquisitionMode(store: SettingsStore) {
        if !detectorAvailable, store.settings.acquisitionMode != .tap {
            store.settings.acquisitionMode = .tap
        }
    }

    private func frameRateOption(_ title: String, _ preset: FrameRatePreset) -> some View {
        Text(cameraCapabilities.supports(preset) ? title : "\(title) unavailable")
            .tag(preset)
            .disabled(!cameraCapabilities.supports(preset))
    }

    private func clampUnsupportedFrameRate(store: SettingsStore) {
        if !cameraCapabilities.supports(store.settings.frameRate) {
            store.settings.frameRate = cameraCapabilities.bestAvailablePreset
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}
