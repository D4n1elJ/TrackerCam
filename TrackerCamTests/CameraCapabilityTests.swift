import Testing
@testable import TrackerCam
import TrackerCamCore

/// App-layer tests (improvements2 B3). `CameraService.CapabilityReport` is pure value logic — the
/// device probe builds it, but its preset selection / support mapping is testable without hardware.
struct CameraCapabilityTests {

    private func report(name: String = "Back",
                        max: Double = 60,
                        c30: Bool = true, c60: Bool = true,
                        c100: Bool = false, c120: Bool = false) -> CameraService.CapabilityReport {
        CameraService.CapabilityReport(cameraName: name, max4KFrameRate: max,
                                       supports4K30: c30, supports4K60: c60,
                                       supports4K100: c100, supports4K120: c120)
    }

    @Test func bestPresetPicksHighestSupported() {
        #expect(report(c100: true, c120: true).bestAvailablePreset == .experimental120)
        #expect(report(c100: true, c120: false).bestAvailablePreset == .experimental100)
        #expect(report(c60: true, c100: false, c120: false).bestAvailablePreset == .preferred60)
        #expect(report(c30: true, c60: false).bestAvailablePreset == .fps30)
    }

    @Test func supportsMapsEachPresetToItsFlag() {
        let r = report(c30: true, c60: true, c100: false, c120: false)
        #expect(r.supports(.fps30))
        #expect(r.supports(.preferred60))
        #expect(!r.supports(.experimental100))
        #expect(!r.supports(.experimental120))
    }

    @Test func summaryReflectsMvpReadiness() {
        #expect(report(max: 60, c60: true).summary.contains("MVP ready"))
        #expect(report(max: 30, c60: false).summary.contains("below MVP target"))
        #expect(report(max: 0, c30: false, c60: false).summary.contains("No back 4K camera"))
    }
}
