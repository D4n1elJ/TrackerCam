import CoreMedia
import TrackerCamCore

/// Per-frame output of the analysis pipeline: who/where (boxes) + how (skeletons + angles).
/// All rects/points are in the analysis image's pixel space (see `ClipAnalyzer.analysisSize`).
struct FrameAnalysis: Sendable {
    var time: CMTime
    var horseBox: TCRect?
    var riderBox: TCRect?
    var riderSkeleton: TCSkeleton?
    var horseSkeleton: TCSkeleton?       // nil until a horse-keypoint model is bundled
    var riderAngles: RiderAngles?
}

/// Whole-clip result: every analyzed frame plus simple aggregate stats for a coaching summary.
struct ClipAnalysis: Sendable {
    var sourceURL: URL
    var imageSize: TCSize
    var frames: [FrameAnalysis]
    /// URL of the rendered annotated video, once `ClipAnnotator` has written it.
    var annotatedURL: URL?

    var frameCount: Int { frames.count }
    var riderDetectionRate: Double {
        guard !frames.isEmpty else { return 0 }
        return Double(frames.filter { $0.riderSkeleton != nil }.count) / Double(frames.count)
    }
    var horseDetectionRate: Double {
        guard !frames.isEmpty else { return 0 }
        return Double(frames.filter { $0.horseBox != nil }.count) / Double(frames.count)
    }
    var riderMeanJointConfidence: Double? {
        meanSkeletonMetric { $0.meanConfidence }
    }
    var riderJointCompleteness: Double? {
        let required = TCRiderJoint.allCases.map(\.rawValue)
        return meanSkeletonMetric { $0.completeness(requiredJoints: required) }
    }
    var riderAngleCoverage: Double {
        guard !frames.isEmpty else { return 0 }
        return Double(frames.filter { $0.riderAngles?.hasAnyMeasurement == true }.count) / Double(frames.count)
    }
    var riderMeasuredAngleMean: Double? {
        let vals = frames.compactMap { $0.riderAngles?.measuredCount }
        guard !vals.isEmpty else { return nil }
        return Double(vals.reduce(0, +)) / Double(vals.count)
    }

    /// Mean of a rider angle across frames where it is present (e.g. average knee bend).
    func meanRiderAngle(_ key: KeyPath<RiderAngles, Double?>) -> Double? {
        let vals = frames.compactMap { $0.riderAngles?[keyPath: key] }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func meanSkeletonMetric(_ metric: (TCSkeleton) -> Double) -> Double? {
        let vals = frames.compactMap { $0.riderSkeleton.map(metric) }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
}

/// Progress callback payload for the UI.
struct AnalysisProgress: Sendable {
    var processed: Int
    var total: Int
    var fraction: Double { total > 0 ? Double(processed) / Double(total) : 0 }
}
