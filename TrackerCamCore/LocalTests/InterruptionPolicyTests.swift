// Capture interruption → action mapping. Plan §14 Interruption Policy.
func runInterruptionPolicyTests() {
    let p = InterruptionPolicy()

    // Revoked camera access always stops & finalizes, regardless of reason.
    expectEqual(p.action(reason: .audioInUse, isRecording: true, cameraAccessRevoked: true),
                InterruptionAction.stopAndFinalize, "access revoked → stop")

    // Not recording → nothing to protect; keep the session.
    expectEqual(p.action(reason: .backgrounded, isRecording: false, cameraAccessRevoked: false),
                InterruptionAction.keepRecording, "not recording → keep")

    // Phone call / audio taken: video can continue → keep recording (audio gap).
    expectEqual(p.action(reason: .audioInUse, isRecording: true, cameraAccessRevoked: false),
                InterruptionAction.keepRecording, "audio-only interruption → keep")

    // Backgrounding: recording is foreground-only → finalize & continue on resume.
    expectEqual(p.action(reason: .backgrounded, isRecording: true, cameraAccessRevoked: false),
                InterruptionAction.finalizeAndContinue, "backgrounded → finalize+continue")

    // Camera taken by another app → finalize & continue.
    expectEqual(p.action(reason: .videoInUse, isRecording: true, cameraAccessRevoked: false),
                InterruptionAction.finalizeAndContinue, "video-in-use → finalize+continue")

    // System pressure (thermal) → preserve the segment, continue when it eases.
    expectEqual(p.action(reason: .systemPressure, isRecording: true, cameraAccessRevoked: false),
                InterruptionAction.finalizeAndContinue, "system pressure → finalize+continue")

    // Media-services reset invalidates the stack → finalize & continue (rebuild session).
    expectEqual(p.action(reason: .mediaServicesReset, isRecording: true, cameraAccessRevoked: false),
                InterruptionAction.finalizeAndContinue, "media reset → finalize+continue")
}
