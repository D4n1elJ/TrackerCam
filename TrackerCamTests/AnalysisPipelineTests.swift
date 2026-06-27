import Testing
import Foundation
@testable import TrackerCam
import TrackerCamCore

/// End-to-end exercise of the offline skeleton-tracking pipeline (ClipAnalyzer → rider pose → angles)
/// against the repo's real horse+rider clip. This is the objective check the project favors: it reports
/// how many frames produced a rider skeleton, so we can SEE whether Vision body pose actually runs in
/// the current environment (the simulator's ANE/espresso limits killed the Core ML detectors — this
/// confirms whether `VNDetectHumanBodyPoseRequest` is on the same restricted path or not).
struct AnalysisPipelineTests {
    /// IMG_2486.MOV lives at the repo root, two levels up from this test source file.
    private var clipURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // TrackerCamTests/
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("IMG_2486.MOV")
    }

    @Test func analyzerRunsAndReportsSkeletonCoverage() async throws {
        let url = clipURL
        try #require(FileManager.default.fileExists(atPath: url.path),
                     "fixture clip missing at \(url.path)")

        let analyzer = ClipAnalyzer()
        // Subsample heavily — we only need a coverage signal, not every frame.
        let analysis = try await analyzer.analyze(url: url, frameStride: 10)

        #expect(analysis.frameCount > 0, "pipeline analyzed zero frames")

        // Objective, ground-truth-free signals, logged for the run record.
        let riderRate = analysis.riderDetectionRate
        let conf = analysis.riderMeanJointConfidence ?? 0
        let completeness = analysis.riderJointCompleteness ?? 0
        print("""
        [skeleton-tracking] frames=\(analysis.frameCount) \
        riderDetectionRate=\(String(format: "%.2f", riderRate)) \
        meanJointConfidence=\(String(format: "%.2f", conf)) \
        jointCompleteness=\(String(format: "%.2f", completeness)) \
        angleCoverage=\(String(format: "%.2f", analysis.riderAngleCoverage))
        """)

        // The pipeline must execute without throwing and produce frames; skeleton coverage is reported
        // (not asserted > 0) because it depends on rider visibility + Vision availability in the host.
    }
}
