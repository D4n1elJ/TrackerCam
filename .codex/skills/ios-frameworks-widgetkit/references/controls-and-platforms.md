# Controls and Platforms

## Control Center Controls (iOS 18+)

Controls appear in Control Center, Lock Screen, and Action Button (iPhone 15 Pro+).

### Static Control (Button)

```swift
struct TorchControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TorchControl") {
            ControlWidgetButton(action: ToggleTorchIntent()) {
                Label("Flashlight", systemImage: "flashlight.on.fill")
            }
        }
        .displayName("Flashlight")
        .description("Toggle flashlight")
    }
}
```

### Static Control (Toggle)

```swift
struct LightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "Light", provider: LightProvider()) { value in
            ControlWidgetToggle(
                isOn: value.isOn,
                action: ToggleLightIntent()
            ) { isOn in
                Label(isOn ? "On" : "Off", systemImage: "lightbulb.fill")
                    .tint(isOn ? .yellow : .gray)
            }
        }
    }
}
```

### ControlValueProvider (Async State)

Controls must not block the main thread. Use a value provider for async data loading.

```swift
struct LightProvider: ControlValueProvider {
    // Called asynchronously to fetch current state
    func currentValue() async throws -> LightValue {
        try await HomeManager.shared.fetchLightState()
    }

    // Returned immediately while currentValue() loads
    var previewValue: LightValue {
        let shared = UserDefaults(suiteName: "group.com.myapp")!
        return LightValue(isOn: shared.bool(forKey: "lastKnownLightState"))
    }
}
```

### Configurable Control

```swift
struct TimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "TimerControl",
            intent: ConfigureTimerIntent.self
        ) { configuration in
            ControlWidgetButton(action: StartTimerIntent(duration: configuration.duration)) {
                Label("\(configuration.duration)m", systemImage: "timer")
            }
        }
        .promptsForUserConfiguration()  // Shows config UI when user adds control
    }
}
```

### watchOS Controls (watchOS 11+)

Same `ControlWidget` / `StaticControlConfiguration` / `ControlWidgetButton` pattern works identically on watchOS. Controls appear in Control Center, Action Button, and Smart Stack.

## Optimistic UI Pattern for Controls

Users expect instant feedback. Update cached state before the real operation completes.

```swift
struct ToggleLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Light"

    func perform() async throws -> some IntentResult {
        let shared = UserDefaults(suiteName: "group.com.myapp")!
        let current = shared.bool(forKey: "lastKnownLightState")
        let newState = !current

        // 1. Update cache immediately (optimistic)
        shared.set(newState, forKey: "lastKnownLightState")

        // 2. Then update the real device (may take seconds)
        try await HomeManager.shared.setLight(isOn: newState)

        return .result()
    }
}
```

If the real operation fails, revert the cached state and reload the control.

## Interactive Widgets (iOS 17+)

Buttons and toggles in widget views, powered by App Intents.

```swift
// Use intent: parameter, NOT action: closure
Button(intent: IncrementIntent()) {
    Label("Add", systemImage: "plus.circle")
}
```

```swift
struct IncrementIntent: AppIntent {
    static var title: LocalizedStringResource = "Increment"

    func perform() async throws -> some IntentResult {
        let shared = UserDefaults(suiteName: "group.com.myapp")!
        let count = shared.integer(forKey: "count")
        shared.set(count + 1, forKey: "count")

        // Reload widget to reflect change
        WidgetCenter.shared.reloadTimelines(ofKind: "CounterWidget")

        return .result()
    }
}
```

### invalidatableContent

Dims content while an intent executes, providing visual feedback.

```swift
Text(entry.status)
    .invalidatableContent()  // Slightly transparent during intent execution
```

### numericText Transition

```swift
Text("\(entry.value)")
    .contentTransition(.numericText(value: Double(entry.value)))
```

Numbers count up/down smoothly instead of snapping.

## visionOS Widgets (visionOS 2+)

Widgets in visionOS are 3D objects placed in physical space.

### Mounting Styles

```swift
// Both elevated (tables) and recessed (walls) — default
.supportedMountingStyles([.elevated, .recessed])

// Wall-only widget
.supportedMountingStyles([.recessed])
```

### Widget Textures

```swift
.widgetTexture(.glass)   // Default — transparent glass appearance
.widgetTexture(.paper)   // Poster-like, effective with extra-large sizes
```

### Proximity Awareness (levelOfDetail)

System automatically adapts based on user distance. Transitions between levels are animated.

```swift
@Environment(\.levelOfDetail) var levelOfDetail

var body: some View {
    VStack {
        Text(entry.title)
            .font(levelOfDetail == .simplified ? .largeTitle : .title3)

        if levelOfDetail == .default {
            // Show details only when user is close
            Text(entry.subtitle)
                .font(.caption)
        }
    }
}
```

- `.default` — Close viewing. Show full detail.
- `.simplified` — Distant viewing. Larger text, fewer elements.

### visionOS Widget Families

Supports standard families plus spatial-specific sizes:

```swift
.supportedFamilies([
    .systemSmall, .systemMedium, .systemLarge,
    .systemExtraLarge,
    .systemExtraLargePortrait  // visionOS portrait orientation
])
```

Extra-large families pair well with `.widgetTexture(.paper)` for poster-like displays.

## Widget Relevance (iOS 18+)

Help the system promote your widgets in the Smart Stack by providing relevance signals.

```swift
.relevanceConfiguration(
    for: .systemSmall,
    score: 0.8,
    attributes: [
        .timeOfDay(DateInterval(start: morningStart, end: morningEnd)),
        .location(homeLocation),
        .activity("workout")
    ]
)
```

Relevance attributes:
- **`.location(CLLocation)`** — Widget is relevant near this location
- **`.timeOfDay(DateInterval)`** — Widget is relevant during this time window
- **`.activity(String)`** — Widget is relevant during this activity type

Higher scores (0.0-1.0) make the widget more likely to appear at the top of Smart Stack. Combine multiple attributes for context-aware ranking (e.g., a morning routine widget scored high at home between 6-9 AM).

## SwiftData in Widgets (iOS 17+)

Widget reads from the same database as the main app via App Groups.

```swift
// Widget TimelineProvider
func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
    let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.myapp"
    )!.appendingPathComponent("MyApp.store")

    let config = ModelConfiguration(url: containerURL)
    let container = try! ModelContainer(for: MyModel.self, configurations: config)
    let context = ModelContext(container)

    let items = try! context.fetch(FetchDescriptor<MyModel>(
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    ))

    let entries = [SimpleEntry(date: Date(), items: Array(items.prefix(10)))]
    completion(Timeline(entries: entries, policy: .atEnd))
}
```

**Rules:**
- Widget reads only. Never write from the widget — causes conflicts.
- Main app calls `WidgetCenter.shared.reloadAllTimelines()` after writes.
- Both targets must register the same schema models.

## GRDB/SQLite in Widgets

```swift
// Widget opens read-only connection
var config = Configuration()
config.readonly = true  // Prevent accidental writes

let dbPath = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.com.myapp"
)!.appendingPathComponent("db.sqlite").path

let dbPool = try DatabasePool(path: dbPath, configuration: config)
```

Use `DatabasePool` (not `DatabaseQueue`) for concurrent reads while the main app may be writing.

## Darwin Notification Center (Cross-Process IPC)

Simple signal mechanism between app and extension. No data payload — just a "something changed" ping.

```swift
// Main app — post notification after data change
import Darwin

let name = "com.myapp.dataDidChange" as CFString
CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    CFNotificationName(name),
    nil, nil, true
)

// Widget extension — observe and reload
CFNotificationCenterAddObserver(
    CFNotificationCenterGetDarwinNotifyCenter(),
    nil,
    { _, _, _, _, _ in
        WidgetCenter.shared.reloadAllTimelines()
    },
    "com.myapp.dataDidChange" as CFString,
    nil,
    .deliverImmediately
)
```

Use this when you need the widget to react faster than the next timeline reload. The observer triggers a manual reload which counts against the daily budget.

## Liquid Glass Widget Styling (iOS 26+)

### Accented Rendering

```swift
@Environment(\.widgetRenderingMode) var renderingMode

var body: some View {
    HStack {
        Text("Title")
            .widgetAccentable()  // Tinted separately in accented mode

        Image("icon")
            .widgetAccentedRenderingMode(.accented)  // Tinted with accent color
    }
}
```

Rendering mode options for images:
- `.accented` — Tinted with user's accent color
- `.monochrome` — Rendered as monochrome
- `.fullColor` — Keeps original colors (opt-out of tinting)

### Container Background

```swift
VStack { /* content */ }
    .containerBackground(for: .widget) {
        Color.blue.opacity(0.2)
    }
```

In accented mode, the system removes the background and replaces it with themed glass. To prevent removal (excludes widget from iPad Lock Screen, StandBy):

```swift
.containerBackgroundRemovable(false)
```

### Glass Effects

```swift
Text("Label")
    .padding()
    .glassEffect()  // Default capsule shape

Image(systemName: "star.fill")
    .frame(width: 60, height: 60)
    .glassEffect(.regular, in: .rect(cornerRadius: 12))

Button("Action") { }
    .buttonStyle(.glass)
```

Group glass elements with `GlassEffectContainer` for coordinated spatial effects:

```swift
GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        Image(systemName: "cloud")
            .frame(width: 60, height: 60)
            .glassEffect()
        Image(systemName: "sun")
            .frame(width: 60, height: 60)
            .glassEffect()
    }
}
```

### Background Detection

```swift
@Environment(\.showsWidgetContainerBackground) var showsBackground
// false when system has removed background (accented mode, StandBy)
```
