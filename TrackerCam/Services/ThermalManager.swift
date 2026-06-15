import Foundation
import Observation

/// Monitors `ProcessInfo.thermalState` and exposes the degradation level (plan §15 Thermal Ladder).
@Observable
@MainActor
final class ThermalManager {
    enum Level {
        case nominal, fair, serious, critical
    }

    private(set) var level: Level = .nominal

    private var observer: NSObjectProtocol?

    init() {
        update()
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Hop to the main actor explicitly (notification closure is nonisolated).
            Task { @MainActor in self?.update() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func update() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: level = .nominal
        case .fair: level = .fair
        case .serious: level = .serious
        case .critical: level = .critical
        @unknown default: level = .serious
        }
    }

    /// Detector interval multiplier under thermal pressure (plan §15: .fair doubles it).
    var redetectionIntervalMultiplier: Double {
        switch level {
        case .nominal: return 1.0
        case .fair: return 2.0
        case .serious, .critical: return 2.0
        }
    }

    /// Whether capture must stop & finalize now (plan §15 critical / decision D19).
    var mustStopRecording: Bool { level == .critical }
}
