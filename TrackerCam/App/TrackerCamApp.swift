import SwiftUI

@main
struct TrackerCamApp: App {
    @State private var settingsStore = SettingsStore()

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
