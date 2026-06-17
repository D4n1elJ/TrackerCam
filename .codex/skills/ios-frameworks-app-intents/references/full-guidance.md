# App Intents Quick Reference

## Purpose

Opinionated guide for exposing app actions to Siri, Shortcuts, Spotlight, and system surfaces. Covers AppIntent, AppEntity, AppShortcutsProvider, and the decision framework for choosing the right integration point. iOS 26+ only -- no `@available` checks needed.

## How to Use

1. **Decide what to expose** using the decision tree below
2. **Pick the pattern** from the integration table
3. **Check anti-patterns** before shipping
4. **For full API details**, read `references/intent-patterns.md`

## Decision Tree

```
What are you exposing?
|
+-- An ACTION (verb) the user can trigger?
|   |
|   +-- Should it work instantly after install?
|   |   +-- YES -> AppShortcutsProvider + AppIntent
|   |   +-- NO  -> AppIntent alone (user finds in Shortcuts app)
|   |
|   +-- Does it need dynamic parameters?
|       +-- YES -> AppEntity + EntityQuery
|       +-- NO  -> AppEnum for fixed choices, or raw types
|
+-- APP CONTENT the user can search or reference?
|   |
|   +-- Want automatic "Find X where..." in Shortcuts?
|   |   +-- YES -> IndexedEntity + @Property with indexingKey
|   |
|   +-- Want content in Spotlight search?
|   |   +-- YES -> CSSearchableItem (batch) + NSUserActivity (current screen)
|   |
|   +-- Need entity as an intent parameter?
|       +-- YES -> AppEntity + EntityQuery
|
+-- A SYSTEM INTEGRATION?
    |
    +-- Interactive widget button     -> AppIntent with WidgetKit
    +-- Control Center control        -> AppIntent with ControlWidget
    +-- Focus filter                  -> SetFocusFilterIntent
    +-- Lock Screen / Action Button   -> AppShortcutsProvider
```

## Integration Surface Table

| Surface | Requires | Availability |
|---|---|---|
| Siri voice | AppShortcutsProvider with phrases | Instant after install |
| Spotlight actions | AppShortcutsProvider | Instant after install |
| Shortcuts app | AppIntent (discoverable) | User finds manually |
| Action Button | AppShortcutsProvider | User assigns in Settings |
| Control Center | AppIntent + ControlWidget | User adds control |
| Interactive widgets | AppIntent as button action | Widget configuration |
| Focus filters | SetFocusFilterIntent | System Settings |
| Apple Pencil Pro squeeze | AppShortcutsProvider | User assigns |
| Visual Intelligence | IntentValueQuery | Camera circle gesture |

## The Three Building Blocks

**AppIntent** -- An executable action with parameters and a `perform()` method.

```swift
struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Weight"
    static var description: IntentDescription = "Records a body weight measurement"

    @Parameter(title: "Weight")
    var weight: Measurement<UnitMass>

    static var parameterSummary: some ParameterSummary {
        Summary("Log weight of \(\.$weight)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await WeightService.shared.log(weight)
        return .result(dialog: "Logged \(weight.formatted())")
    }
}
```

**AppEntity** -- An object users can pick as an intent parameter. Always separate from your data model.

```swift
struct WorkoutEntity: AppEntity {
    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workout"
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    static var defaultQuery = WorkoutQuery()
}
```

**AppEnum** -- A fixed set of choices for intent parameters.

```swift
enum MealType: String, AppEnum {
    case breakfast, lunch, dinner, snack

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static var caseDisplayRepresentations: [MealType: DisplayRepresentation] = [
        .breakfast: "Breakfast",
        .lunch: "Lunch",
        .dinner: "Dinner",
        .snack: "Snack",
    ]
}
```

## AppShortcutsProvider -- Instant Availability

One type per app. Makes intents available in Siri, Spotlight, and Action Button with zero user setup.

```swift
struct MyAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Log weight in \(.applicationName)",
                "Record weight with \(.applicationName)",
            ],
            shortTitle: "Log Weight",
            systemImageName: "scalemass.fill"
        )
    }
}
```

**Rules for phrases:**
- 3-6 words ideal
- Start with a verb (Log, Start, Get, Show, Open)
- Always include `\(.applicationName)` for disambiguation
- Provide 2-3 natural variations per shortcut
- Limit to 3-5 shortcuts total -- quality over quantity

## Anti-Patterns

### Intent Design

| Mistake | Fix |
|---|---|
| Generic title ("Do Thing", "Process") | Verb-noun title ("Log Weight", "Start Workout") |
| Technical error messages | User-friendly: "Sorry, that item is unavailable" |
| `suggestedEntities()` returns thousands | Limit to 10-20 recent/relevant items |
| MainActor access in background intent | Use `await MainActor.run { }` or set `openAppWhenRun = true` |
| Making data model conform to AppEntity | Create a separate entity type with `init(from:)` |
| Parameter summary with technical phrasing | Natural language: "Send \(\.$message) to \(\.$contact)" |
| Forgetting `defaultQuery` on AppEntity | Always provide -- intent resolution depends on it |

### App Shortcuts

| Mistake | Fix |
|---|---|
| 20+ shortcuts | Focus on 3-5 core actions |
| Long phrases ("I would like to...") | Short phrases ("Order coffee in...") |
| Missing `\(.applicationName)` in phrases | Always include for Siri disambiguation |
| Parameterizing every variant | Generic shortcut + 2-3 common specific cases |
| Verbose shortTitle | Concise -- app name already shown by system |

## Promoting Shortcuts in Your App

```swift
// Show after a completed action to teach the shortcut
SiriTipView(intent: ReorderIntent(), isVisible: $showTip)
    .siriTipViewStyle(.automatic)

// Link to all shortcuts in settings
ShortcutsLink()
```

## Common Patterns

### Background Action (No App Launch)

```swift
struct ToggleDarkModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Dark Mode"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let newValue = await SettingsService.shared.toggleDarkMode()
        return .result(dialog: "Dark mode \(newValue ? "on" : "off")")
    }
}
```

### Foreground Action with Navigation

```swift
struct OpenWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Workout"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Workout")
    var workout: WorkoutEntity

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NavigationCoordinator.shared.show(workoutID: workout.id)
        }
        return .result()
    }
}
```

### Confirmation Before Destructive Action

```swift
func perform() async throws -> some IntentResult {
    try await requestConfirmation(
        result: .result(dialog: "Delete '\(item.title)'?"),
        confirmationActionName: .init(stringLiteral: "Delete")
    )
    try await service.delete(item)
    return .result(dialog: "Deleted")
}
```

## Execution Modes

Use `supportedModes` for granular control over foreground/background:

| Mode | Behavior |
|---|---|
| `.background` | Runs entirely in background |
| `.foreground(.immediate)` | App foregrounded before `perform()` |
| `.foreground(.dynamic)` | Can request foreground mid-execution |
| `.foreground(.deferred)` | Background first, foreground before completion |

```swift
struct SmartIntent: AppIntent {
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await computeResult()

        if systemContext.currentMode.canContinueInForeground {
            try? await continueInForeground(alwaysConfirm: false)
            await navigator.show(result)
        }

        return .result(dialog: "Done: \(result.summary)")
    }
}
```

## Error Handling

Conform errors to `CustomLocalizedStringResourceConvertible` so Siri speaks user-friendly messages:

```swift
enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notFound
    case unauthorized

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound: "That item could not be found"
        case .unauthorized: "Please open the app and sign in first"
        }
    }
}
```

## Full Reference

For the complete API -- EntityQuery variants, IndexedEntity, Spotlight integration, Focus filters, interactive widgets, Control Center controls, assistant schemas, Visual Intelligence, and AppIntentsPackage for modular projects -- read `references/intent-patterns.md`.

## Global Rules

| Rule | Value |
|---|---|
| Max App Shortcuts | 3-5 core actions |
| Phrase length | 3-6 words + `\(.applicationName)` |
| Entity suggestions | 10-20 items max |
| Default shortcut tile color | Match your app brand |
| Separate entities from models | Always -- never conform data model to AppEntity |
| Deployment target | iOS 26+ only -- no `@available` checks |
