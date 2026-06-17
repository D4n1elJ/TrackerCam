import SwiftUI

@main
struct TrackerCamApp: App {
    @State private var settingsStore = SettingsStore()

    init() {
        // Register on-device MetricKit telemetry once at launch (local-first; see MetricsService).
        MetricsService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            CameraView(viewModel: CameraViewModel(settingsStore: settingsStore))
                .environment(settingsStore)
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
