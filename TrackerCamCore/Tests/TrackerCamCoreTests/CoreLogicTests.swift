import Testing
@testable import TrackerCamCore

/// Single entry point that runs every core-logic suite sequentially and asserts no failures.
///
/// The suites share a global accumulator (see TestSupport.swift), so they must NOT run in parallel;
/// keeping them inside one @Test guarantees sequential execution. Individual `expect(...)` failures
/// are reported with file:line in the assertion message.
@Test func coreLogic() {
    runVisionGeometryTests()
    runKalmanTests()
    runCropMathTests()
    runTrackingStateMachineTests()
    runSettingsTests()
    runCropControllerTests()
    runCropPlannerTests()
    runGuidanceEngineTests()
    runInterruptionPolicyTests()
    runStoragePolicyTests()
    runAspectRobustnessTests()
    runCropMetadataTests()
    runEdgeCaseTests()

    let report = "core-logic checks failed (\(failures.count)/\(checksRun)):\n" + failures.joined(separator: "\n")
    #expect(failures.isEmpty, "\(report)")
}
