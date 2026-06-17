# AlarmKit Patterns

## Authorization

```swift
// Info.plist required
// NSAlarmKitUsageDescription: "We'll schedule alerts for alarms you create."

// Request
func requestAuth() async -> Bool {
    do {
        let state = try await AlarmManager.shared.requestAuthorization()
        return state == .authorized
    } catch {
        return false
    }
}

// Check current state — use authorizationState, NOT authorizationStatus
let status = await AlarmManager.shared.authorizationState
switch status {
case .authorized: break
case .denied: break       // Show settings prompt
case .notDetermined: break // Request auth
@unknown default: break
}

// Observe changes
for await state in AlarmManager.shared.authorizationUpdates {
    // Update UI based on state
}
```

---

## Snooze Mechanism

Snooze is built from two pieces working together:
- `CountdownDuration.postAlert` — the snooze duration in seconds
- `.snoozeButton` + `.secondaryButtonBehavior: .countdown` — triggers the post-alert countdown when tapped

```swift
// 9-minute snooze: postAlert provides the duration, snoozeButton triggers it
let countdown = Alarm.CountdownDuration(preAlert: nil, postAlert: 9 * 60)
let alert = AlarmPresentation.Alert(
    title: "Alarm",
    stopButton: .stopButton,
    secondaryButton: .snoozeButton,
    secondaryButtonBehavior: .countdown  // Starts the postAlert countdown
)
```

---

## Creating Alarms

### One-Time Alarm

```swift
let id = UUID()
let time = Alarm.Schedule.Relative.Time(hour: 7, minute: 30)
let schedule = Alarm.Schedule.relative(.init(time: time, repeats: .never))

let alert = AlarmPresentation.Alert(
    title: "Wake Up",
    stopButton: .stopButton,
    secondaryButton: .snoozeButton,
    secondaryButtonBehavior: .countdown
)

let presentation = AlarmPresentation(alert: alert)

struct EmptyMetadata: AlarmMetadata {}
let attributes = AlarmAttributes(
    presentation: presentation,
    metadata: EmptyMetadata(),
    tintColor: .blue
)

let config = AlarmManager.AlarmConfiguration(
    countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: 9 * 60), // 9-min snooze
    schedule: schedule,
    attributes: attributes,
    sound: .default
)

let alarm = try await AlarmManager.shared.schedule(id: id, configuration: config)
```

### Repeating Alarm

```swift
let time = Alarm.Schedule.Relative.Time(hour: 6, minute: 0)
let schedule = Alarm.Schedule.relative(.init(
    time: time,
    repeats: .weekly([.monday, .tuesday, .wednesday, .thursday, .friday])
))
// Rest same as one-time
```

### Countdown Timer

```swift
let id = UUID()

let countdownDuration = Alarm.CountdownDuration(
    preAlert: 300,  // 5 minutes countdown
    postAlert: 10   // 10 seconds post-alert for repeat
)

let alert = AlarmPresentation.Alert(
    title: "Timer Complete",
    stopButton: .stopButton,
    secondaryButton: .repeatButton,
    secondaryButtonBehavior: .countdown
)

let countdown = AlarmPresentation.Countdown(
    title: "Timer Running",
    pauseButton: .pauseButton
)

let paused = AlarmPresentation.Paused(
    title: "Timer Paused",
    resumeButton: .resumeButton
)

let presentation = AlarmPresentation(
    alert: alert,
    countdown: countdown,
    paused: paused
)

struct TimerMetadata: AlarmMetadata {
    let purpose: String
}

let attributes = AlarmAttributes(
    presentation: presentation,
    metadata: TimerMetadata(purpose: "Cooking"),
    tintColor: .orange
)

let config = AlarmManager.AlarmConfiguration(
    countdownDuration: countdownDuration,
    schedule: nil,  // No schedule for timers
    attributes: attributes,
    sound: .default
)

let alarm = try await AlarmManager.shared.schedule(id: id, configuration: config)
```

---

## Alarm Presentation

### Alert Buttons

```swift
// Built-in buttons
AlarmPresentation.Alert.stopButton
AlarmPresentation.Alert.snoozeButton
AlarmPresentation.Alert.openAppButton
AlarmPresentation.Alert.repeatButton

// Custom label
AlarmButton(label: "Taken")  // e.g. medication reminder
```

### Secondary Button Behavior

| Behavior | Effect |
|---|---|
| `.countdown` | Starts post-alert countdown (snooze/repeat) |
| `.custom` | Custom action (e.g. open app) |

### Full Presentation States

```swift
let presentation = AlarmPresentation(
    alert: AlarmPresentation.Alert(
        title: "Alarm Title",
        stopButton: .stopButton,
        secondaryButton: .snoozeButton,
        secondaryButtonBehavior: .countdown
    ),
    countdown: AlarmPresentation.Countdown(     // For timer countdown state
        title: "Counting Down",
        pauseButton: .pauseButton
    ),
    paused: AlarmPresentation.Paused(           // For paused timer state
        title: "Paused",
        resumeButton: .resumeButton
    )
)
```

---

## Custom Metadata

```swift
struct RecipeMetadata: AlarmMetadata {
    let recipeName: String
    let cookingStep: String
}

let attributes = AlarmAttributes(
    presentation: presentation,
    metadata: RecipeMetadata(recipeName: "Cake", cookingStep: "Remove from oven"),
    tintColor: .brown
)
```

---

## Managing Alarms

```swift
// Schedule
let alarm = try await AlarmManager.shared.schedule(id: id, configuration: config)

// Retrieve all
let alarms = try AlarmManager.shared.alarms

// Pause / Resume
try await AlarmManager.shared.pause(id: alarmID)
try await AlarmManager.shared.resume(id: alarmID)

// Cancel
try await AlarmManager.shared.cancel(id: alarmID)
```

---

## Observing Changes

```swift
// Alarm state changes
Task {
    for await alarms in AlarmManager.shared.alarmUpdates {
        // Refresh UI — alarms not in array are no longer scheduled
        self.alarms = alarms
    }
}

// Authorization changes
Task {
    for await state in AlarmManager.shared.authorizationUpdates {
        self.isAuthorized = (state == .authorized)
    }
}
```

---

## Live Activities Integration

Widget extension required for countdown presentations:

```swift
## SwiftUI Integration

### ViewModel Pattern

```swift
import AlarmKit

@Observable
class AlarmViewModel {
    var alarms: [Alarm] = []
    private let manager = AlarmManager.shared

    func requestAuthorization() async throws -> Bool {
        let state = try await manager.requestAuthorization()
        return state == .authorized
    }

    func loadAndObserve() async {
        alarms = (try? manager.alarms) ?? []
        for await updated in manager.alarmUpdates {
            alarms = updated
        }
    }

    func scheduleAlarm(
        hour: Int, minute: Int,
        weekdays: Set<Locale.Weekday> = [],
        snoozeDuration: TimeInterval = 9 * 60
    ) async throws {
        let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let schedule = Alarm.Schedule.relative(.init(
            time: time,
            repeats: weekdays.isEmpty ? .never : .weekly(Array(weekdays))
        ))

        let alert = AlarmPresentation.Alert(
            title: "Alarm",
            stopButton: .stopButton,
            secondaryButton: .snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        struct EmptyMetadata: AlarmMetadata {}
        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(
                preAlert: nil, postAlert: snoozeDuration
            ),
            schedule: schedule,
            attributes: AlarmAttributes(
                presentation: AlarmPresentation(alert: alert),
                metadata: EmptyMetadata(),
                tintColor: .blue
            ),
            sound: .default
        )

        _ = try await manager.schedule(id: UUID(), configuration: config)
    }

    func cancel(id: UUID) async throws {
        try await manager.cancel(id: id)
    }

    func togglePause(id: UUID, isPaused: Bool) async throws {
        if isPaused {
            try await manager.resume(id: id)
        } else {
            try await manager.pause(id: id)
        }
    }
}
```

---

## Live Activities Integration

Widget extension required for countdown presentations:

```swift
struct AlarmWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<YourMetadata>.self) { context in
            // Lock Screen UI
            VStack {
                Text(context.attributes.presentation.alert.title)
                if context.state.mode == .countdown {
                    Text(timerInterval: context.state.countdownEndDate...Date.now,
                         countsDown: true)
                        .bold()
                }
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.presentation.alert.title)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Timer display
                }
            } compactLeading: {
                Image(systemName: "alarm")
            } compactTrailing: {
                // Compact timer
            } minimal: {
                Image(systemName: "alarm")
            }
        }
    }
}
```

---

## References

- **WWDC25-230** — AlarmKit introduction session
- **Docs:** `/alarmkit`, `/alarmkit/alarmmanager`, `/alarmkit/alarm`, `/alarmkit/alarmpresentation`, `/alarmkit/alarmattributes`
