import Foundation
import Observation
import TrackerCamCore

/// Persists `TrackerSettings` (plan §13). Codable JSON in UserDefaults keeps the framework-free
/// core type as the single source of truth instead of scattering @AppStorage keys.
@Observable
@MainActor
final class SettingsStore {
    private let defaultsKey = "trackercam.settings.v1"

    var settings: TrackerSettings {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(TrackerSettings.self, from: data) {
            settings = decoded.clamped()
        } else {
            settings = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings.clamped()) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func resetToDefaults() { settings = .default }
}
