# Haptics -- Patterns & API Reference

Complete API reference for all three haptic tiers: SwiftUI `.sensoryFeedback()`, UIKit `UIFeedbackGenerator`, and Core Haptics. Examples target iOS 17+ minimum.

---

## Tier 1: SwiftUI .sensoryFeedback() (iOS 17+)

Declarative haptic feedback attached directly to views. No engine lifecycle, no prepare calls, no cleanup.

### Basic Usage

```swift
// Fire on value change
Button("Complete") { completeTask() }
    .sensoryFeedback(.success, trigger: completionCount)

// Fire when condition becomes true
MyView()
    .sensoryFeedback(.error, trigger: hasError) { oldValue, newValue in
        newValue == true
    }
```

### All SensoryFeedback Cases

#### Notification-Level Feedback

| Case | Sensation | Use |
|---|---|---|
| `.success` | Double-tap rising pattern | Task completed, save confirmed, payment processed |
| `.warning` | Three taps with pause | Approaching limit, battery low, storage nearly full |
| `.error` | Three rapid descending taps | Validation failed, action blocked, network error |

```swift
// Success after async operation
AsyncButton("Submit") { await submit() }
    .sensoryFeedback(.success, trigger: submitCount)

// Warning on threshold
ProgressView(value: usage, total: limit)
    .sensoryFeedback(.warning, trigger: usage) { old, new in
        new > limit * 0.9 && old <= limit * 0.9
    }

// Error on validation failure
TextField("Email", text: $email)
    .sensoryFeedback(.error, trigger: validationFailed)
```

#### Selection Feedback

| Case | Sensation | Use |
|---|---|---|
| `.selection` | Light tick | Picker value changed, segment tapped, discrete step |

```swift
// Picker-style selection
Picker("Size", selection: $size) {
    ForEach(Size.allCases) { Text($0.label).tag($0) }
}
.sensoryFeedback(.selection, trigger: size)

// Custom stepper
Stepper("Count: \(count)", value: $count)
    .sensoryFeedback(.selection, trigger: count)
```

#### Directional Feedback

| Case | Sensation | Use |
|---|---|---|
| `.increase` | Light upward tap | Volume up, brightness increase, zoom in |
| `.decrease` | Light downward tap | Volume down, brightness decrease, zoom out |

```swift
HStack {
    Button("-") { quantity -= 1 }
        .sensoryFeedback(.decrease, trigger: quantity) { $0 > $1 }

    Text("\(quantity)")

    Button("+") { quantity += 1 }
        .sensoryFeedback(.increase, trigger: quantity) { $0 < $1 }
}
```

#### State Transition Feedback

| Case | Sensation | Use |
|---|---|---|
| `.start` | Medium onset tap | Recording started, timer began, workout active |
| `.stop` | Medium offset tap | Recording stopped, timer ended, workout paused |

```swift
Button(isRecording ? "Stop" : "Record") {
    isRecording.toggle()
}
.sensoryFeedback(.start, trigger: isRecording) { _, new in new }
.sensoryFeedback(.stop, trigger: isRecording) { _, new in !new }
```

#### Spatial Feedback

| Case | Sensation | Use |
|---|---|---|
| `.alignment` | Rigid snap | Snap to grid, guide alignment, magnetic dock |
| `.levelChange` | Medium shift | Crossed threshold, changed floor, zoom level jumped |
| `.impact` | Medium thud | General collision, tap confirmation, physical contact |

```swift
// Snap-to-grid in a drag gesture
DraggableView()
    .sensoryFeedback(.alignment, trigger: snappedToGrid)

// Level transition
ScrollView {
    LazyVStack { ... }
}
.sensoryFeedback(.levelChange, trigger: currentSection)

// Physical impact
GameBallView()
    .sensoryFeedback(.impact, trigger: collisionCount)
```

### Flexible Intensity and Sharpness

```swift
// Custom weight with SensoryFeedback
.sensoryFeedback(.impact(weight: .heavy, intensity: 0.8), trigger: value)
.sensoryFeedback(.impact(flexibility: .rigid, intensity: 1.0), trigger: value)
```

Available weight values: `.light`, `.medium`, `.heavy`.
Available flexibility values: `.rigid`, `.solid`, `.soft`.

---

## Tier 2: UIFeedbackGenerator (UIKit)

For UIKit views, precise `prepare()` timing, or when you need the generator instance for reuse.

### UIImpactFeedbackGenerator

Physical collision or tap sensation.

**Styles** (ordered light to heavy):

| Style | Character | Common Use |
|---|---|---|
| `.light` | Delicate tap | Toggle, checkbox, minor selection |
| `.medium` | Standard tap | Button press, confirm action |
| `.heavy` | Strong impact | Delete, drop, significant action |
| `.rigid` | Firm, precise | Snap, alignment, detent |
| `.soft` | Gentle, cushioned | Subtle confirmation, background state |

```swift
class ViewController: UIViewController {
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        let button = UIButton(primaryAction: UIAction { [weak self] _ in
            self?.impact.impactOccurred()
        })
        // Prepare on touch down for zero-latency feedback
        button.addAction(UIAction { [weak self] _ in
            self?.impact.prepare()
        }, for: .touchDown)
    }
}
```

**Intensity override** (0.0 to 1.0):

```swift
impact.impactOccurred(intensity: 0.5)  // Half strength regardless of style
```

### UISelectionFeedbackGenerator

Discrete tick for value changes.

```swift
class WheelPicker: UIControl {
    private let selection = UISelectionFeedbackGenerator()

    func valueDidChange() {
        selection.selectionChanged()
    }
}
```

### UINotificationFeedbackGenerator

Outcome-level feedback.

| Type | Pattern | Use |
|---|---|---|
| `.success` | Rising double-tap | Operation succeeded |
| `.warning` | Hesitant triple-tap | Needs attention |
| `.error` | Descending triple-tap | Operation failed |

```swift
let notification = UINotificationFeedbackGenerator()

func handleResult(_ result: Result<Data, Error>) {
    switch result {
    case .success:
        notification.notificationOccurred(.success)
    case .failure:
        notification.notificationOccurred(.error)
    }
}
```

### prepare() Timing

`prepare()` wakes the Taptic Engine and keeps it ready for approximately 1 second. Call it when you know a haptic is likely but has not fired yet.

**Best practice**: call on `touchDown`, fire on `touchUpInside`.

```swift
// UIKit button pattern
button.addAction(UIAction { [weak self] _ in
    self?.impact.prepare()
}, for: .touchDown)

button.addAction(UIAction { [weak self] _ in
    self?.impact.impactOccurred()
}, for: .touchUpInside)
```

**Timing window**: if more than ~1 second passes after `prepare()`, the engine powers down. Call `prepare()` again if needed.

**Cost of skipping**: unprepared haptics may lag 10-20ms. Usually imperceptible for notification/selection, noticeable for rapid impact sequences.

---

## Tier 3: Core Haptics

Full control over haptic waveforms, audio-haptic synchronization, looping, and dynamic parameter updates. Use only when Tier 1 and Tier 2 cannot express the pattern you need.

### CHHapticEngine Lifecycle

```swift
import CoreHaptics

final class HapticManager {
    private var engine: CHHapticEngine?

    func start() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            engine = try CHHapticEngine()

            engine?.stoppedHandler = { [weak self] reason in
                // Engine stopped by system (call, Siri, audio session change)
                self?.restart()
            }

            engine?.resetHandler = { [weak self] in
                // Engine reset -- must restart before next play
                self?.restart()
            }

            try engine?.start()
        } catch {
            engine = nil
        }
    }

    private func restart() {
        try? engine?.start()
    }
}
```

**Rules**:
- Always set `stoppedHandler` and `resetHandler` before calling `start()`
- Always check `supportsHaptics` before creating the engine
- The engine is a heavyweight object; create one per feature, not per event

### Event Types

#### Transient Events

Short, discrete tap. Defined by intensity and sharpness at a single point in time.

```swift
let tap = CHHapticEvent(
    eventType: .hapticTransient,
    parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
    ],
    relativeTime: 0.0
)
```

**Parameters**:
- `hapticIntensity` (0.0-1.0): strength of the tap
- `hapticSharpness` (0.0-1.0): 0.0 = dull thud, 1.0 = crisp snap

#### Continuous Events

Sustained vibration over a duration. Used for textures, motors, and progressive feedback.

```swift
let rumble = CHHapticEvent(
    eventType: .hapticContinuous,
    parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
    ],
    relativeTime: 0.0,
    duration: 1.5
)
```

### Creating and Playing Patterns

```swift
func playEscalatingTaps() throws {
    let events = (0..<3).map { i in
        let time = Double(i) * 0.15
        let intensity = Float(i + 1) / 3.0
        return CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: intensity)
            ],
            relativeTime: time
        )
    }

    let pattern = try CHHapticPattern(events: events, parameters: [])
    let player = try engine?.makePlayer(with: pattern)
    try player?.start(atTime: CHHapticTimeImmediate)
}
```

### CHHapticAdvancedPatternPlayer -- Looping and Dynamic Parameters

For patterns that must loop or change while playing.

```swift
func startContinuousTexture() throws {
    let event = CHHapticEvent(
        eventType: .hapticContinuous,
        parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
        ],
        relativeTime: 0.0,
        duration: 0.5
    )

    let pattern = try CHHapticPattern(events: [event], parameters: [])
    let player = try engine?.makeAdvancedPlayer(with: pattern)

    player?.loopEnabled = true
    try player?.start(atTime: CHHapticTimeImmediate)

    // Update intensity dynamically based on speed
    let param = CHHapticDynamicParameter(
        parameterID: .hapticIntensityControl,
        value: newIntensity,
        relativeTime: 0
    )
    try player?.sendParameters([param], atTime: CHHapticTimeImmediate)
}
```

**Key difference**: `CHHapticPatternPlayer` plays once. `CHHapticAdvancedPatternPlayer` supports `loopEnabled` and `sendParameters(_:atTime:)` for real-time control.

### Dynamic Parameters

Modify a running pattern without stopping it.

| Parameter ID | Controls |
|---|---|
| `.hapticIntensityControl` | Overall intensity multiplier (0.0-1.0) |
| `.hapticSharpnessControl` | Overall sharpness multiplier (0.0-1.0) |
| `.hapticAttackTimeControl` | Fade-in speed |
| `.hapticDecayTimeControl` | Fade-out speed |
| `.hapticReleaseTimeControl` | Release tail length |

---

## AHAP Files (Apple Haptic Audio Pattern)

JSON files that define haptic and audio events together. Useful for designer handoff and asset-based iteration.

### Basic AHAP Structure

```json
{
    "Version": 1.0,
    "Metadata": {
        "Project": "MyApp",
        "Created": "2026-03-20"
    },
    "Pattern": [
        {
            "Event": {
                "Time": 0.0,
                "EventType": "HapticTransient",
                "EventParameters": [
                    { "ParameterID": "HapticIntensity", "ParameterValue": 1.0 },
                    { "ParameterID": "HapticSharpness", "ParameterValue": 0.5 }
                ]
            }
        },
        {
            "Event": {
                "Time": 0.2,
                "EventType": "HapticTransient",
                "EventParameters": [
                    { "ParameterID": "HapticIntensity", "ParameterValue": 0.7 },
                    { "ParameterID": "HapticSharpness", "ParameterValue": 0.8 }
                ]
            }
        }
    ]
}
```

### AHAP with Audio

```json
{
    "Version": 1.0,
    "Pattern": [
        {
            "Event": {
                "Time": 0.0,
                "EventType": "AudioCustom",
                "EventWaveformPath": "confirm.wav",
                "EventParameters": [
                    { "ParameterID": "AudioVolume", "ParameterValue": 0.8 }
                ]
            }
        },
        {
            "Event": {
                "Time": 0.0,
                "EventType": "HapticContinuous",
                "EventDuration": 0.5,
                "EventParameters": [
                    { "ParameterID": "HapticIntensity", "ParameterValue": 0.6 },
                    { "ParameterID": "HapticSharpness", "ParameterValue": 0.3 }
                ]
            }
        }
    ]
}
```

**Audio file constraints**:
- Maximum file size: 4.2 MB
- Maximum duration: 23 seconds
- Supported formats: WAV, AIFF, CAF (uncompressed or Apple Lossless preferred)
- The `EventWaveformPath` is relative to the app bundle

### Loading and Playing AHAP

```swift
func playAHAP(named name: String) {
    guard let url = Bundle.main.url(forResource: name, withExtension: "ahap") else { return }

    do {
        let pattern = try CHHapticPattern(contentsOf: url)
        let player = try engine?.makePlayer(with: pattern)
        try player?.start(atTime: CHHapticTimeImmediate)
    } catch {
        // Fall back to UIFeedbackGenerator or skip
    }
}
```

### AHAP with Parameter Curves

Smoothly ramp intensity or sharpness over time within a pattern:

```json
{
    "Version": 1.0,
    "Pattern": [
        {
            "Event": {
                "Time": 0.0,
                "EventType": "HapticContinuous",
                "EventDuration": 1.0,
                "EventParameters": [
                    { "ParameterID": "HapticIntensity", "ParameterValue": 0.3 },
                    { "ParameterID": "HapticSharpness", "ParameterValue": 0.2 }
                ]
            }
        },
        {
            "ParameterCurve": {
                "ParameterID": "HapticIntensityControl",
                "Time": 0.0,
                "ParameterCurveControlPoints": [
                    { "Time": 0.0, "ParameterValue": 0.3 },
                    { "Time": 0.5, "ParameterValue": 1.0 },
                    { "Time": 1.0, "ParameterValue": 0.0 }
                ]
            }
        }
    ]
}
```

---

## Audio-Haptic Synchronization

### Coordinated Playback

Fire haptic and visual animation at the same instant:

```swift
func performTransformation() {
    // Haptic and animation start together
    playAHAP(named: "transform")

    withAnimation(.easeInOut(duration: 0.5)) {
        scale = 1.2
        opacity = 0.8
    }
}
```

### Design Workflow

1. Build the visual animation first (define timing and keyframes)
2. Design audio to match the energy (rising = gaining, falling = releasing)
3. Design haptic to match the physical sensation (sharp for impact, continuous for sustained)
4. Test all three together on device -- do they feel like one event?
5. Iterate AHAP assets until coherent; swap files without code changes

---

## Common Patterns

### SwiftUI Toggle with Feedback

```swift
Toggle("Notifications", isOn: $enabled)
    .sensoryFeedback(.selection, trigger: enabled)
```

### SwiftUI Delete Confirmation

```swift
Button("Delete", role: .destructive) { delete() }
    .sensoryFeedback(.warning, trigger: deleteCount)
```

### UIKit Pull-to-Refresh Threshold

```swift
class RefreshController: UIViewController, UIScrollViewDelegate {
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private var didFire = false

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y <= -100 && !didFire {
            impact.impactOccurred()
            didFire = true
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        didFire = false
    }
}
```

### UIKit Slider with Detent Ticks

```swift
class DetentSlider: UISlider {
    private let selection = UISelectionFeedbackGenerator()
    private var lastDetent: Float = 0
    private let detentSpacing: Float = 0.25

    @objc func valueChanged() {
        let nearestDetent = (value / detentSpacing).rounded() * detentSpacing
        if nearestDetent != lastDetent {
            selection.selectionChanged()
            lastDetent = nearestDetent
        }
    }
}
```

---

## Troubleshooting

### Engine fails to start

Check in order:
1. Device supports Core Haptics (`CHHapticEngine.capabilitiesForHardware().supportsHaptics`)
2. Device is iPhone 8 or newer
3. System Haptics is enabled in Settings
4. Low Power Mode is not active

Fall back to `UIFeedbackGenerator` if the engine cannot start.

### Haptics not felt on device

1. Settings -> Sounds & Haptics -> System Haptics must be ON
2. Low Power Mode must be OFF
3. Intensity values below 0.3 may be too subtle to feel
4. Verify with a known-working `UINotificationFeedbackGenerator().notificationOccurred(.success)` to isolate whether the issue is Core Haptics or system-wide

### Audio out of sync with haptics

1. Call `prepare()` before the haptic to eliminate engine wake latency
2. Start audio and haptic from the same call site, not across async boundaries
3. Avoid heavy main-thread work between the start calls
4. Use AHAP files for tightly coupled audio-haptic patterns -- the engine handles sync internally
