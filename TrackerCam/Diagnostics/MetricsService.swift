import Foundation
import os
#if canImport(MetricKit)
import MetricKit
#endif

/// On-device performance & diagnostics telemetry via MetricKit (improvements2 B4).
///
/// Local-first: payloads are written to the unified log (subsystem `com.trackercam.metrics`) and
/// never leave the device — consistent with the app's no-cloud privacy posture (see
/// `APP_STORE_NOTES.md`). Surfaces crash/hang diagnostics, CPU/GPU, thermal, disk writes, and
/// launch/exit metrics so field issues (thermal throttling, hangs, memory growth) are observable.
///
/// MetricKit delivers aggregated metrics roughly once per day and diagnostics shortly after the
/// event. Register once at launch (`start()`) and keep the singleton alive for the app's lifetime.
final class MetricsService: NSObject, @unchecked Sendable {
    static let shared = MetricsService()
    private let log = Logger(subsystem: "com.trackercam.metrics", category: "metrickit")

    /// Register the MetricKit subscriber. No-op where MetricKit is unavailable (e.g. macOS unit hosts).
    func start() {
        #if canImport(MetricKit) && os(iOS)
        MXMetricManager.shared.add(self)
        log.notice("MetricKit subscriber registered")
        #endif
    }
}

#if canImport(MetricKit) && os(iOS)
extension MetricsService: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let json = String(decoding: payload.jsonRepresentation(), as: UTF8.self)
            log.notice("metric payload: \(json, privacy: .public)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let json = String(decoding: payload.jsonRepresentation(), as: UTF8.self)
            log.error("diagnostic payload: \(json, privacy: .public)")
        }
    }
}
#endif
