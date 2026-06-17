import Foundation
@testable import TrackerCamCore

// Settings model + defaults. Plan §13 Settings Specification.
func runSettingsTests() {
    let d = TrackerSettings.default

    // Default values (plan §13).
    expectClose(d.redetectionInterval, 0.50, tol: 1e-9, "default redetection")
    expectClose(d.lostTrackTimeout, 0.33, tol: 1e-9, "default lost timeout")
    expectClose(d.confidenceThreshold, 0.50, tol: 1e-9, "default confidence")
    expectClose(d.smoothingStrength, 0.50, tol: 1e-9, "default smoothing")
    expectClose(d.targetSubjectHeight, 0.35, tol: 1e-9, "default subject height")
    expectClose(d.compositionLeadFraction, 0.08, tol: 1e-9, "default lead")
    expectClose(d.verticalCompositionOffset, -0.05, tol: 1e-9, "default vertical offset")
    expectClose(d.subjectPadding, 0.20, tol: 1e-9, "default padding")
    expectClose(d.guidanceDeadZone, 0.08, tol: 1e-9, "default dead zone")
    expectClose(d.guidanceLookahead, 0.30, tol: 1e-9, "default lookahead")
    expectClose(d.userLeadTime, 0.10, tol: 1e-9, "default user lead")

    expectEqual(d.acquisitionMode, .autoRefocus, "default acquisition")
    expectEqual(d.aspectRatio, .landscape16x9, "default aspect")
    expectEqual(d.frameRate, .preferred60, "default fps")
    expectEqual(d.lens, .main, "default lens")
    expectEqual(d.recordingMode, .trackedOnly, "default rec mode")
    expectEqual(d.saveDestination, .app, "default save dest")
    expectEqual(d.detectionModel, .standard, "default model")
    expect(d.guidanceEnabled, "guidance on by default")
    expect(d.guidanceHaptics, "haptics on by default")
    expect(d.dynamicZoomEnabled, "dynamic zoom on by default")
    expect(!d.overlayInRecording, "overlay off by default")
    expect(!d.preserveFull4KSource, "preserve 4K off by default")

    // Clamping above range.
    var hi = TrackerSettings.default
    hi.targetSubjectHeight = 0.90
    hi.subjectPadding = 0.50
    hi.guidanceDeadZone = 0.50
    hi.confidenceThreshold = 1.5
    hi.compositionLeadFraction = 0.40
    hi.verticalCompositionOffset = 0.40
    let hc = hi.clamped()
    expectClose(hc.targetSubjectHeight, 0.55, tol: 1e-9, "clamp height hi")
    expectClose(hc.subjectPadding, 0.35, tol: 1e-9, "clamp padding hi")
    expectClose(hc.guidanceDeadZone, 0.20, tol: 1e-9, "clamp dead zone hi")
    expectClose(hc.confidenceThreshold, 1.0, tol: 1e-9, "clamp confidence hi")
    expectClose(hc.compositionLeadFraction, 0.20, tol: 1e-9, "clamp lead hi")
    expectClose(hc.verticalCompositionOffset, 0.10, tol: 1e-9, "clamp voffset hi")

    // Clamping below range.
    var lo = TrackerSettings.default
    lo.targetSubjectHeight = 0.10
    lo.guidanceDeadZone = 0.001
    lo.confidenceThreshold = -0.5
    lo.verticalCompositionOffset = -0.40
    let lc = lo.clamped()
    expectClose(lc.targetSubjectHeight, 0.12, tol: 1e-9, "clamp height lo")
    expectClose(lc.guidanceDeadZone, 0.03, tol: 1e-9, "clamp dead zone lo")
    expectClose(lc.confidenceThreshold, 0.0, tol: 1e-9, "clamp confidence lo")
    expectClose(lc.verticalCompositionOffset, -0.15, tol: 1e-9, "clamp voffset lo")

    // Settings feed the tracking state machine config (real integration).
    let cfg = d.trackingConfig
    expectClose(cfg.lostTimeout, d.lostTrackTimeout, tol: 1e-9, "config lost timeout")
    expectClose(cfg.confidenceThreshold, d.confidenceThreshold, tol: 1e-9, "config confidence")

    // Missing fields from older persisted settings decode with defaults instead of resetting all settings.
    let oldJSON = """
    {
      "acquisitionMode": "tap",
      "redetectionInterval": 1.25,
      "lostTrackTimeout": 0.75,
      "confidenceThreshold": 0.60,
      "smoothingStrength": 0.40,
      "aspectRatio": "landscape16x9",
      "targetSubjectHeight": 0.30,
      "subjectPadding": 0.22,
      "compositionLeadFraction": 0.05,
      "verticalCompositionOffset": -0.03,
      "userLeadTime": 0.20,
      "dynamicZoomEnabled": false,
      "showMiniMap": true,
      "outputResolution": "tracked1080p",
      "frameRate": "preferred60",
      "lens": "main",
      "guidanceEnabled": false,
      "guidanceDeadZone": 0.10,
      "guidanceLookahead": 0.25,
      "guidanceHaptics": false,
      "recordingMode": "trackedOnly",
      "overlayInRecording": false,
      "preserveFull4KSource": false,
      "exportCropMetadata": true,
      "saveDestination": "app",
      "detectionModel": "standard"
    }
    """.data(using: .utf8)!
    let migrated = try! JSONDecoder().decode(TrackerSettings.self, from: oldJSON)
    expectEqual(migrated.acquisitionMode, .tap, "migration preserves existing enum")
    expectClose(migrated.redetectionInterval, 1.25, tol: 1e-9, "migration preserves numeric")
    expectClose(migrated.minCropFraction, TrackerSettings.default.minCropFraction, tol: 1e-9, "migration defaults missing crop floor")
}
