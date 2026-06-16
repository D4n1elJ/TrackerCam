import SwiftUI
import TrackerCamCore

/// Settings UI (plan §13). Presets first; advanced numeric controls available but not required.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("trackercam.showDebugHUD") private var showDebugHUD = false
    @AppStorage("trackercam.showGrid") private var showGrid = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Tracking") {
                    Picker("Acquisition", selection: $store.settings.acquisitionMode) {
                        Text("Auto").tag(AcquisitionMode.auto)
                        Text("Tap").tag(AcquisitionMode.tap)
                        Text("Auto + Refocus").tag(AcquisitionMode.autoRefocus)
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
                    Toggle("Dynamic zoom", isOn: $store.settings.dynamicZoomEnabled)
                    slider("Subject height", $store.settings.targetSubjectHeight, 0.12...0.55)
                    slider("Padding", $store.settings.subjectPadding, 0.10...0.35)
                    slider("Lead", $store.settings.compositionLeadFraction, 0.0...0.20)
                    Toggle("Mini-map", isOn: $store.settings.showMiniMap)
                }

                Section("Camera") {
                    Picker("Resolution", selection: $store.settings.outputResolution) {
                        Text("1080p tracked").tag(OutputResolution.tracked1080p)
                        Text("4K full-frame").tag(OutputResolution.full4K)
                    }
                    Picker("Frame rate", selection: $store.settings.frameRate) {
                        Text("30").tag(FrameRatePreset.fps30)
                        Text("60 (preferred)").tag(FrameRatePreset.preferred60)
                        Text("100 (experimental)").tag(FrameRatePreset.experimental100)
                        Text("120 (experimental)").tag(FrameRatePreset.experimental120)
                    }
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
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}
