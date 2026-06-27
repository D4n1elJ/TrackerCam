import SwiftUI
import AVKit
import TrackerCamCore

/// "Coach mode" — pick a recorded clip, run the on-device analysis pipeline, review angle stats and the
/// annotated video. Entirely local (no cloud). See ClipAnalyzer / ClipAnnotator for the pipeline.
struct AnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = AnalysisViewModel()
    @State private var urls: [URL] = []

    private let store = RecordingStore()

    var body: some View {
        NavigationStack {
            Group {
                if let result = model.result {
                    resultView(result)
                } else if model.isRunning {
                    progressView
                } else {
                    picker
                }
            }
            .navigationTitle("Analyze")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                if model.result != nil {
                    ToolbarItem(placement: .topBarTrailing) { Button("New") { model.reset() } }
                }
            }
        }
        .onAppear { urls = store.recordings() }
    }

    private var picker: some View {
        Group {
            if urls.isEmpty {
                ContentUnavailableView("No recordings", systemImage: "figure.equestrian.sports",
                                       description: Text("Record a clip, then analyze rider & horse here."))
            } else {
                List(urls, id: \.self) { url in
                    Button { Task { await model.run(url: url) } } label: {
                        Label(url.lastPathComponent, systemImage: "wand.and.stars")
                    }
                }
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal, 40)
            Text(model.statusText).font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultView(_ result: ClipAnalysis) -> some View {
        List {
            if let annotated = result.annotatedURL {
                Section("Annotated clip") {
                    VideoPlayer(player: AVPlayer(url: annotated)).frame(height: 220)
                    ShareLink(item: annotated) { Label("Export annotated clip", systemImage: "square.and.arrow.up") }
                }
            }
            Section("Coverage") {
                stat("Frames analyzed", "\(result.frameCount)")
                stat("Rider detected", percent(result.riderDetectionRate))
                stat("Horse detected", percent(result.horseDetectionRate))
            }
            Section("Rider skeleton quality") {
                stat("Joint confidence", result.riderMeanJointConfidence.map(percent) ?? "—")
                stat("Joint completeness", result.riderJointCompleteness.map(percent) ?? "—")
                stat("Angle coverage", percent(result.riderAngleCoverage))
                stat("Angles per frame", result.riderMeasuredAngleMean.map { String(format: "%.1f / 6", $0) } ?? "—")
            }
            Section("Average rider angles") {
                angleStat("L knee bend", result.meanRiderAngle(\.leftKnee))
                angleStat("R knee bend", result.meanRiderAngle(\.rightKnee))
                angleStat("L elbow", result.meanRiderAngle(\.leftElbow))
                angleStat("R elbow", result.meanRiderAngle(\.rightElbow))
                angleStat("Torso lean", result.meanRiderAngle(\.torsoLean))
                angleStat("Position line", result.meanRiderAngle(\.hipShoulderHeelStacked))
            }
            if result.horseDetectionRate == 0 {
                Section {
                    Label("Horse keypoints need a bundled animal-pose model (see ANALYSIS_SPEC.md). Rider analysis runs natively.",
                          systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }
    private func angleStat(_ label: String, _ value: Double?) -> some View {
        stat(label, value.map { String(format: "%.0f°", $0) } ?? "—")
    }
    private func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}

@MainActor
@Observable
final class AnalysisViewModel {
    private(set) var isRunning = false
    private(set) var progress: Double = 0
    private(set) var statusText = ""
    private(set) var result: ClipAnalysis?

    private let analyzer = ClipAnalyzer()
    private let annotator = ClipAnnotator()

    func reset() {
        result = nil
        progress = 0
        statusText = ""
    }

    func run(url: URL) async {
        isRunning = true
        statusText = "Analyzing frames…"
        progress = 0
        defer { isRunning = false }
        do {
            var analysis = try await analyzer.analyze(url: url) { [weak self] p in
                Task { @MainActor in self?.progress = p.fraction }
            }
            statusText = "Rendering annotated clip…"
            analysis.annotatedURL = try? await annotator.render(analysis)
            result = analysis
        } catch {
            statusText = "Failed: \(error.localizedDescription)"
        }
    }
}
