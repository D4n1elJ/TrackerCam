/// User-facing settings. Plan §13 Settings Specification.
/// Framework-free so the core can consume it; the app persists it via @AppStorage / Codable.

public enum AcquisitionMode: String, Equatable, Sendable, Codable, CaseIterable {
    case auto, tap, autoRefocus
}

public enum AspectRatioMode: String, Equatable, Sendable, Codable, CaseIterable {
    case landscape16x9, portrait9x16, square1x1, fullFrame

    /// width / height of the output (fullFrame uses the source aspect, reported as 0 = "match source").
    public var ratio: Double {
        switch self {
        case .landscape16x9: return 16.0 / 9.0
        case .portrait9x16: return 9.0 / 16.0
        case .square1x1: return 1.0
        case .fullFrame: return 0
        }
    }
}

public enum FrameRatePreset: String, Equatable, Sendable, Codable, CaseIterable {
    case fps30, preferred60, experimental100, experimental120
}

public enum LensSelection: String, Equatable, Sendable, Codable, CaseIterable {
    case main, ultraWide
}

public enum OutputResolution: String, Equatable, Sendable, Codable, CaseIterable {
    case tracked1080p, full4K
}

public enum RecordingMode: String, Equatable, Sendable, Codable, CaseIterable {
    case trackedOnly, fullOnly, fullPlusTracked
}

public enum SaveDestination: String, Equatable, Sendable, Codable, CaseIterable {
    case app, photos, both
}

public enum DetectionModel: String, Equatable, Sendable, Codable, CaseIterable {
    case standard, equestrian
}

public struct TrackerSettings: Equatable, Sendable, Codable {
    // Tracking
    public var acquisitionMode: AcquisitionMode
    public var redetectionInterval: Double
    public var lostTrackTimeout: Double
    public var confidenceThreshold: Double
    public var smoothingStrength: Double
    // Framing
    public var aspectRatio: AspectRatioMode
    public var targetSubjectHeight: Double
    public var subjectPadding: Double
    public var compositionLeadFraction: Double
    public var verticalCompositionOffset: Double
    public var userLeadTime: Double
    public var dynamicZoomEnabled: Bool
    /// Minimum crop size as a fraction of the source frame — the "never crop into a close-up" floor.
    /// Higher = more surrounding environment always in frame (plan §10 / improvements #36).
    public var minCropFraction: Double
    public var showMiniMap: Bool
    // Camera
    public var outputResolution: OutputResolution
    public var frameRate: FrameRatePreset
    public var lens: LensSelection
    // Guidance
    public var guidanceEnabled: Bool
    public var guidanceDeadZone: Double
    public var guidanceLookahead: Double
    public var guidanceHaptics: Bool
    // Recording
    public var recordingMode: RecordingMode
    public var overlayInRecording: Bool
    public var preserveFull4KSource: Bool
    public var exportCropMetadata: Bool
    public var saveDestination: SaveDestination
    // Advanced
    public var detectionModel: DetectionModel

    private enum CodingKeys: String, CodingKey {
        case acquisitionMode
        case redetectionInterval
        case lostTrackTimeout
        case confidenceThreshold
        case smoothingStrength
        case aspectRatio
        case targetSubjectHeight
        case subjectPadding
        case compositionLeadFraction
        case verticalCompositionOffset
        case userLeadTime
        case dynamicZoomEnabled
        case minCropFraction
        case showMiniMap
        case outputResolution
        case frameRate
        case lens
        case guidanceEnabled
        case guidanceDeadZone
        case guidanceLookahead
        case guidanceHaptics
        case recordingMode
        case overlayInRecording
        case preserveFull4KSource
        case exportCropMetadata
        case saveDestination
        case detectionModel
    }

    public init(
        acquisitionMode: AcquisitionMode,
        redetectionInterval: Double,
        lostTrackTimeout: Double,
        confidenceThreshold: Double,
        smoothingStrength: Double,
        aspectRatio: AspectRatioMode,
        targetSubjectHeight: Double,
        subjectPadding: Double,
        compositionLeadFraction: Double,
        verticalCompositionOffset: Double,
        userLeadTime: Double,
        dynamicZoomEnabled: Bool,
        minCropFraction: Double = 0.45,
        showMiniMap: Bool,
        outputResolution: OutputResolution,
        frameRate: FrameRatePreset,
        lens: LensSelection,
        guidanceEnabled: Bool,
        guidanceDeadZone: Double,
        guidanceLookahead: Double,
        guidanceHaptics: Bool,
        recordingMode: RecordingMode,
        overlayInRecording: Bool,
        preserveFull4KSource: Bool,
        exportCropMetadata: Bool,
        saveDestination: SaveDestination,
        detectionModel: DetectionModel
    ) {
        self.acquisitionMode = acquisitionMode
        self.redetectionInterval = redetectionInterval
        self.lostTrackTimeout = lostTrackTimeout
        self.confidenceThreshold = confidenceThreshold
        self.smoothingStrength = smoothingStrength
        self.aspectRatio = aspectRatio
        self.targetSubjectHeight = targetSubjectHeight
        self.subjectPadding = subjectPadding
        self.compositionLeadFraction = compositionLeadFraction
        self.verticalCompositionOffset = verticalCompositionOffset
        self.userLeadTime = userLeadTime
        self.dynamicZoomEnabled = dynamicZoomEnabled
        self.minCropFraction = minCropFraction
        self.showMiniMap = showMiniMap
        self.outputResolution = outputResolution
        self.frameRate = frameRate
        self.lens = lens
        self.guidanceEnabled = guidanceEnabled
        self.guidanceDeadZone = guidanceDeadZone
        self.guidanceLookahead = guidanceLookahead
        self.guidanceHaptics = guidanceHaptics
        self.recordingMode = recordingMode
        self.overlayInRecording = overlayInRecording
        self.preserveFull4KSource = preserveFull4KSource
        self.exportCropMetadata = exportCropMetadata
        self.saveDestination = saveDestination
        self.detectionModel = detectionModel
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TrackerSettings.default
        self.init(
            acquisitionMode: try values.decodeIfPresent(AcquisitionMode.self, forKey: .acquisitionMode) ?? defaults.acquisitionMode,
            redetectionInterval: try values.decodeIfPresent(Double.self, forKey: .redetectionInterval) ?? defaults.redetectionInterval,
            lostTrackTimeout: try values.decodeIfPresent(Double.self, forKey: .lostTrackTimeout) ?? defaults.lostTrackTimeout,
            confidenceThreshold: try values.decodeIfPresent(Double.self, forKey: .confidenceThreshold) ?? defaults.confidenceThreshold,
            smoothingStrength: try values.decodeIfPresent(Double.self, forKey: .smoothingStrength) ?? defaults.smoothingStrength,
            aspectRatio: try values.decodeIfPresent(AspectRatioMode.self, forKey: .aspectRatio) ?? defaults.aspectRatio,
            targetSubjectHeight: try values.decodeIfPresent(Double.self, forKey: .targetSubjectHeight) ?? defaults.targetSubjectHeight,
            subjectPadding: try values.decodeIfPresent(Double.self, forKey: .subjectPadding) ?? defaults.subjectPadding,
            compositionLeadFraction: try values.decodeIfPresent(Double.self, forKey: .compositionLeadFraction) ?? defaults.compositionLeadFraction,
            verticalCompositionOffset: try values.decodeIfPresent(Double.self, forKey: .verticalCompositionOffset) ?? defaults.verticalCompositionOffset,
            userLeadTime: try values.decodeIfPresent(Double.self, forKey: .userLeadTime) ?? defaults.userLeadTime,
            dynamicZoomEnabled: try values.decodeIfPresent(Bool.self, forKey: .dynamicZoomEnabled) ?? defaults.dynamicZoomEnabled,
            minCropFraction: try values.decodeIfPresent(Double.self, forKey: .minCropFraction) ?? defaults.minCropFraction,
            showMiniMap: try values.decodeIfPresent(Bool.self, forKey: .showMiniMap) ?? defaults.showMiniMap,
            outputResolution: try values.decodeIfPresent(OutputResolution.self, forKey: .outputResolution) ?? defaults.outputResolution,
            frameRate: try values.decodeIfPresent(FrameRatePreset.self, forKey: .frameRate) ?? defaults.frameRate,
            lens: try values.decodeIfPresent(LensSelection.self, forKey: .lens) ?? defaults.lens,
            guidanceEnabled: try values.decodeIfPresent(Bool.self, forKey: .guidanceEnabled) ?? defaults.guidanceEnabled,
            guidanceDeadZone: try values.decodeIfPresent(Double.self, forKey: .guidanceDeadZone) ?? defaults.guidanceDeadZone,
            guidanceLookahead: try values.decodeIfPresent(Double.self, forKey: .guidanceLookahead) ?? defaults.guidanceLookahead,
            guidanceHaptics: try values.decodeIfPresent(Bool.self, forKey: .guidanceHaptics) ?? defaults.guidanceHaptics,
            recordingMode: try values.decodeIfPresent(RecordingMode.self, forKey: .recordingMode) ?? defaults.recordingMode,
            overlayInRecording: try values.decodeIfPresent(Bool.self, forKey: .overlayInRecording) ?? defaults.overlayInRecording,
            preserveFull4KSource: try values.decodeIfPresent(Bool.self, forKey: .preserveFull4KSource) ?? defaults.preserveFull4KSource,
            exportCropMetadata: try values.decodeIfPresent(Bool.self, forKey: .exportCropMetadata) ?? defaults.exportCropMetadata,
            saveDestination: try values.decodeIfPresent(SaveDestination.self, forKey: .saveDestination) ?? defaults.saveDestination,
            detectionModel: try values.decodeIfPresent(DetectionModel.self, forKey: .detectionModel) ?? defaults.detectionModel
        )
    }

    /// The `Training Review` preset — plan §13 Default Values.
    public static let `default` = TrackerSettings(
        acquisitionMode: .autoRefocus,
        redetectionInterval: 0.50,
        lostTrackTimeout: 0.33,
        confidenceThreshold: 0.50,
        smoothingStrength: 0.50,
        aspectRatio: .landscape16x9,
        targetSubjectHeight: 0.35,
        subjectPadding: 0.20,
        compositionLeadFraction: 0.08,
        verticalCompositionOffset: -0.05,
        userLeadTime: 0.10,
        dynamicZoomEnabled: true,
        minCropFraction: 0.45,
        showMiniMap: false,
        outputResolution: .tracked1080p,
        frameRate: .preferred60,
        lens: .main,
        guidanceEnabled: true,
        guidanceDeadZone: 0.08,
        guidanceLookahead: 0.30,
        guidanceHaptics: true,
        recordingMode: .trackedOnly,
        overlayInRecording: false,
        preserveFull4KSource: false,
        exportCropMetadata: false,
        saveDestination: .app,
        detectionModel: .standard
    )

    /// Clamp numeric tunables into their valid ranges (plan §9–§13).
    public func clamped() -> TrackerSettings {
        var s = self
        s.redetectionInterval = clamp(s.redetectionInterval, low: 0.1, high: 5.0)
        s.lostTrackTimeout = clamp(s.lostTrackTimeout, low: 0.1, high: 3.0)
        s.confidenceThreshold = clamp(s.confidenceThreshold, low: 0.0, high: 1.0)
        s.smoothingStrength = clamp(s.smoothingStrength, low: 0.0, high: 1.0)
        s.targetSubjectHeight = clamp(s.targetSubjectHeight, low: 0.12, high: 0.55)
        s.minCropFraction = clamp(s.minCropFraction, low: 0.25, high: 0.9)
        s.subjectPadding = clamp(s.subjectPadding, low: 0.10, high: 0.35)
        s.compositionLeadFraction = clamp(s.compositionLeadFraction, low: 0.0, high: 0.20)
        s.verticalCompositionOffset = clamp(s.verticalCompositionOffset, low: -0.15, high: 0.10)
        s.userLeadTime = clamp(s.userLeadTime, low: 0.0, high: 0.5)
        s.guidanceDeadZone = clamp(s.guidanceDeadZone, low: 0.03, high: 0.20)
        s.guidanceLookahead = clamp(s.guidanceLookahead, low: 0.0, high: 1.0)
        return s
    }

    /// Bridge to the tracking state machine config (plan §8).
    public var trackingConfig: TrackingConfig {
        TrackingConfig(
            lostTimeout: lostTrackTimeout,
            confidenceThreshold: confidenceThreshold
        )
    }
}
