# Shortcuts & Automation

Shortcuts app integration is powered entirely by the **AppIntents** framework (iOS 16+). The legacy SiriKit/Intents framework is deprecated for new development.

## How Shortcuts Work

1. You define `AppIntent` types in your app
2. System discovers them automatically (metadata extraction at build time)
3. They appear in the Shortcuts app under your app's name
4. Users combine them into multi-step shortcuts and automations
5. `AppShortcutsProvider` makes shortcuts available zero-setup (Siri, Spotlight)

## Making Intents Available in Shortcuts

Every `AppIntent` with `isDiscoverable = true` (default) appears in Shortcuts. No extra work needed.

```swift
struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Meal"
    static var description: IntentDescription = "Record a meal in the app"

    @Parameter(title: "Meal Type")
    var mealType: MealType

    @Parameter(title: "Notes")
    var notes: String?

    func perform() async throws -> some IntentResult & ReturnsValue<MealEntity> {
        let meal = try await MealService.shared.log(type: mealType, notes: notes)
        return .result(value: MealEntity(from: meal))
    }
}
```

## Parameter Flow in Shortcuts

Parameters create the "fill in the blanks" experience in Shortcuts:

```swift
// Required parameter — user must provide
@Parameter(title: "Recipe")
var recipe: RecipeEntity

// Optional parameter — user can skip
@Parameter(title: "Serving Size")
var servingSize: Int?

// Default value — pre-filled but changeable
@Parameter(title: "Quantity")
var quantity: Int = 1

// Dynamic options
@Parameter(title: "Category")
var category: CategoryEntity  // Uses EntityQuery.suggestedEntities()
```

### Parameter Summary (Shortcuts UI Sentence)

```swift
static var parameterSummary: some ParameterSummary {
    Summary("Log \(\.$mealType) meal") {
        \.$notes
        \.$quantity
    }
}
```

## Return Values for Chaining

Shortcuts users chain intents — output from one feeds into the next.

```swift
// Return a value that the next shortcut step can use
func perform() async throws -> some IntentResult & ReturnsValue<RecipeEntity> {
    return .result(value: recipe)
}

// Return with dialog (Siri speaks, Shortcuts shows)
func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
    return .result(value: stepCount, dialog: "You've taken \(stepCount) steps today.")
}
```

## Zero-Setup Shortcuts (AppShortcutsProvider)

Pre-built shortcuts that appear immediately in Siri, Spotlight, and Shortcuts without user setup:

```swift
struct MyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log meal in \(.applicationName)",
                "Record food with \(.applicationName)",
            ],
            shortTitle: "Log Meal",
            systemImageName: "fork.knife"
        )
    }
}
```

## Personal Automations

Users can trigger your intents automatically based on:
- Time of day
- Location arrival/departure
- App open/close
- NFC tag tap
- Focus mode changes
- Workout start/end
- CarPlay connect/disconnect

Your intents appear as actions in these automations automatically.

## Shortcuts URL Scheme

Open the Shortcuts app programmatically:

```swift
// Open Shortcuts app
UIApplication.shared.open(URL(string: "shortcuts://")!)

// Open specific shortcut
UIApplication.shared.open(URL(string: "shortcuts://shortcuts/SHORTCUT_ID")!)

// Run a shortcut by name
UIApplication.shared.open(URL(string: "shortcuts://run-shortcut?name=My%20Shortcut")!)

// Create new shortcut (pre-filled)
UIApplication.shared.open(URL(string: "shortcuts://create-shortcut")!)
```

## SiriKit Migration

If you have legacy `INIntent` subclasses, migrate to AppIntents:

```swift
// Old (deprecated)
class OrderCoffeeIntent: INIntent { ... }

// New
struct OrderCoffeeIntent: AppIntent {
    static var title: LocalizedStringResource = "Order Coffee"
    // Migrate parameters, perform logic
}
```

Migration path: `AppIntents` → SiriKit intent migration guide. The system can discover both during transition.

## Debugging Shortcuts Integration

1. **Build & run** your app to register intents with the system
2. **Open Shortcuts app** → search for your app
3. **Verify all intents appear** with correct parameters
4. **Test parameter resolution** — fill in values, run the shortcut
5. **Check Siri** — say your AppShortcut phrases
6. **Console log** — filter by `AppIntents` to see registration and execution logs

## Best Practices

- Use clear, verb-noun `title` values — they become the action name in Shortcuts
- Provide `description` so users understand what the action does
- Return values from `perform()` so users can chain actions
- Use `@Parameter` with `requestValueDialog` for good Siri prompts
- Keep `parameterSummary` as a natural sentence
- Test with Shortcuts app — not just Siri
- Use `NegativeAppShortcutPhrase` to prevent false Siri triggers
