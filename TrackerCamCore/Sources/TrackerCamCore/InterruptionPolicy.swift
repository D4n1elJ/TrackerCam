/// Capture-interruption reasons (mirror of AVCaptureSession.InterruptionReason; kept framework-free
/// so the policy is unit-testable). The app maps the AVFoundation reason to this at the boundary.
public enum CaptureInterruptionReason: Sendable {
    case backgrounded        // video device not available in background (app left foreground)
    case audioInUse          // audio device in use by another client (e.g., phone call)
    case videoInUse          // video device in use by another client (multitasking)
    case systemPressure      // not available due to system pressure (thermal)
    case mediaServicesReset  // media services were reset; the capture/writer stack is invalid
}

/// What recording should do in response. Plan §14: a valid segment must never be discarded.
public enum InterruptionAction: Sendable, Equatable {
    case keepRecording        // transient; the writer stays active
    case finalizeAndContinue  // finalize the current segment now; start a continuation on resume
    case stopAndFinalize      // unrecoverable for this session; stop
}

/// Decides the recording response to a capture interruption. Pure. Plan §14 Interruption Policy.
public struct InterruptionPolicy: Sendable {
    public init() {}

    public func action(reason: CaptureInterruptionReason,
                       isRecording: Bool,
                       cameraAccessRevoked: Bool) -> InterruptionAction {
        if cameraAccessRevoked { return .stopAndFinalize }
        guard isRecording else { return .keepRecording }
        switch reason {
        case .audioInUse:
            return .keepRecording                  // video continues; audio just has a gap
        case .backgrounded, .videoInUse, .systemPressure, .mediaServicesReset:
            return .finalizeAndContinue            // preserve the segment; continue on resume
        }
    }
}
