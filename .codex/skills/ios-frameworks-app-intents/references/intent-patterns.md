# App Intents -- Patterns & API Reference

Complete API reference for App Intents, App Shortcuts, entity queries, Spotlight integration, widgets, Control Center, Focus filters, and system integrations. All examples target iOS 26+ in SwiftUI.

---

## AppIntent Protocol

### Required Members

```swift
struct MyIntent: AppIntent {
    // REQUIRED: Short verb-noun phrase
    static var title: LocalizedStringResource = "Start Timer"

    // REQUIRED: The action
    func perform() async throws -> some IntentResult { .result() }
}
```

### Optional Members

```swift
struct MyIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Timer"

    // Purpose explanation -- shown in Shortcuts app
    static var description: IntentDescription = "Starts a countdown timer"

    // Whether it appears in Shortcuts app search (default: true)
    static var isDiscoverable: Bool = true

    // Whether to launch the app (default: false)
    static var openAppWhenRun: Bool = false

    // Authentication requirement
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult { .result() }
}
```

### Authentication Policies

| Policy | When |
|---|---|
| `.alwaysAllowed` | No sensitive data (default) |
| `.requiresAuthentication` | User must be logged in |
| `.requiresLocalDeviceAuthentication` | Requires Face ID / Touch ID / passcode |

---

## @Parameter Property Wrapper

### Basic Types

```swift
@Parameter(title: "Name")
var name: String

@Parameter(title: "Count")
var count: Int

@Parameter(title: "Date")
var date: Date?

@Parameter(title: "Weight")
var weight: Measurement<UnitMass>

@Parameter(title: "Content")
var content: AttributedString  // Preserves rich text from Apple Intelligence
```

### With Options

```swift
// Default value
@Parameter(title: "Duration")
var duration: Int = 60

// Request dialog when value needed
@Parameter(title: "Location",
           requestValueDialog: "Which location?")
var location: LocationEntity

// Control display in Siri
@Parameter(title: "Amount",
           requestValueDialog: "How much would you like to transfer?")
var amount: Decimal
```

### Parameter Summary

Defines how Siri displays the intent as a sentence. All required parameters without defaults must appear.

```swift
static var parameterSummary: some ParameterSummary {
    Summary("Send \(\.$message) to \(\.$contact)") {
        \.$urgency   // Additional parameters shown below
    }
}
```

**Spotlight rule**: If a required parameter without a default is missing from the summary, the intent will not appear in Spotlight on Mac.

---

## AppEntity Protocol

### Full Implementation

```swift
struct RecipeEntity: AppEntity {
    // REQUIRED: Stable, persistent identifier
    var id: UUID

    // App data
    var name: String
    var cuisine: String
    var prepTimeMinutes: Int

    // REQUIRED: Type-level display name
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Recipe"

    // REQUIRED: Instance display
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(cuisine) -- \(prepTimeMinutes) min",
            image: .init(systemName: "fork.knife")
        )
    }

    // REQUIRED: How the system resolves this entity
    static var defaultQuery = RecipeQuery()
}
```

### Separating Entities from Models

```swift
// Your core model -- untouched
struct Recipe: Identifiable {
    var id: UUID
    var name: String
    var cuisine: String
    var prepTimeMinutes: Int
    var internalNotes: String  // Not exposed to intents
}

// Dedicated entity -- only exposes what intents need
struct RecipeEntity: AppEntity {
    var id: UUID
    var name: String
    var cuisine: String
    var prepTimeMinutes: Int

    init(from recipe: Recipe) {
        self.id = recipe.id
        self.name = recipe.name
        self.cuisine = recipe.cuisine
        self.prepTimeMinutes = recipe.prepTimeMinutes
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Recipe"
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(cuisine)")
    }
    static var defaultQuery = RecipeQuery()
}
```

### Exposed Properties

Properties marked with `@Property` are visible to the system for filtering, sorting, and Apple Intelligence reasoning.

```swift
struct TaskEntity: AppEntity {
    var id: UUID

    @Property(title: "Title")
    var title: String

    @Property(title: "Due Date")
    var dueDate: Date?

    @Property(title: "Priority")
    var priority: TaskPriority

    @Property(title: "Completed")
    var isCompleted: Bool

    // ...
}
```

### Computed and Deferred Properties

```swift
struct SettingsEntity: UniqueAppEntity {
    // Reads live from source of truth, never stored
    @ComputedProperty
    var defaultPlace: PlaceDescriptor {
        UserDefaults.standard.defaultPlace
    }
}

struct LandmarkEntity: IndexedEntity {
    // Only fetched when explicitly requested -- expensive
    @DeferredProperty
    var crowdStatus: Int {
        get async throws {
            await modelData.getCrowdStatus(self)
        }
    }
}
```

---

## AppEnum Protocol

Fixed set of choices for parameters.

```swift
enum Priority: String, AppEnum {
    case low, medium, high, critical

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"
    static var caseDisplayRepresentations: [Priority: DisplayRepresentation] = [
        .low: "Low",
        .medium: "Medium",
        .high: "High",
        .critical: "Critical",
    ]
}
```

---

## EntityQuery

### Basic Query

```swift
struct RecipeQuery: EntityQuery {
    // REQUIRED: Resolve entities by ID
    func entities(for identifiers: [UUID]) async throws -> [RecipeEntity] {
        try await RecipeService.shared.fetch(ids: identifiers)
    }

    // Provide suggestions when user is picking
    func suggestedEntities() async throws -> [RecipeEntity] {
        try await RecipeService.shared.favorites(limit: 10)
    }
}
```

### String Search

```swift
extension RecipeQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [RecipeEntity] {
        try await RecipeService.shared.search(query: string)
    }
}
```

### Enumerable Query (Small, Bounded Lists)

```swift
struct TimezoneQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [TimezoneEntity] {
        TimezoneEntity.allTimezones  // Small list -- provide all
    }

    func entities(for identifiers: [String]) async throws -> [TimezoneEntity] {
        identifiers.compactMap { id in TimezoneEntity.allTimezones.first { $0.id == id } }
    }
}
```

**Use `suggestedEntities()`** when the list is large or unbounded.
**Use `EnumerableEntityQuery`** when the list is small and bounded.

---

## Intent Modes

Control foreground/background execution granularity:

```swift
struct GetStatusIntent: AppIntent {
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    func perform() async throws -> some ReturnsValue<Int> & ProvidesDialog {
        guard await modelData.isOpen(landmark) else {
            return .result(value: 0, dialog: "Currently closed.")
        }

        if systemContext.currentMode.canContinueInForeground {
            do {
                try await continueInForeground(alwaysConfirm: false)
                await navigator.navigateToStatus(landmark)
            } catch { /* foreground denied */ }
        }

        let status = await modelData.getStatus(landmark)
        return .result(value: status, dialog: "Status: \(status)")
    }
}
```

### Mode Options

| Mode | Behavior |
|---|---|
| `.background` | Entirely in background |
| `.foreground(.immediate)` | App foregrounded before `perform()` |
| `.foreground(.dynamic)` | Background by default, can request foreground during execution |
| `.foreground(.deferred)` | Background initially, guaranteed foreground when requested |

### Mode Combinations

- `[.background, .foreground]` — Foreground by default, background as fallback
- `[.background, .foreground(.dynamic)]` — Background by default, can request foreground
- `[.background, .foreground(.deferred)]` — Background initially, guaranteed foreground later

### Continuing in Foreground

```swift
// Request foreground
try await continueInForeground(alwaysConfirm: false)

// Or throw to request foreground after error
throw needsToContinueInForegroundError(
    IntentDialog("Need to open app to complete this action"),
    alwaysConfirm: true
)
```

---

## Intent Results

### Result Types

```swift
// Simple completion
return .result()

// With dialog (Siri speaks this)
return .result(dialog: "Timer started for 5 minutes")

// With return value
return .result(value: createdEntity)

// With dialog and value
return .result(value: order, dialog: "Order placed")

// With snippet view
return .result(value: order, view: OrderConfirmationSnippet(order: order))

// With follow-up intent (opens app after background work)
return .result(
    value: event,
    opensIntent: OpenEventIntent(event: event)
)
```

### SnippetIntent -- Interactive Result Views

```swift
struct RecipeSnippetIntent: SnippetIntent {
    @Parameter var recipe: RecipeEntity

    var snippet: some View {
        VStack {
            Text(recipe.name).font(.headline)
            Text("\(recipe.prepTimeMinutes) minutes").font(.subheadline)
            HStack {
                Button("Save") { /* action */ }
                Button("Share") { /* action */ }
            }
        }
        .padding()
    }
}
```

---

## Confirmation Dialogs

### Before Destructive Actions

```swift
func perform() async throws -> some IntentResult {
    try await requestConfirmation(
        result: .result(dialog: "Delete '\(task.title)'?"),
        confirmationActionName: .init(stringLiteral: "Delete")
    )
    try await TaskService.shared.delete(task)
    return .result(dialog: "Task deleted")
}
```

### Multiple Choice

```swift
let options = [
    IntentChoiceOption(title: "Option A", subtitle: "Description"),
    IntentChoiceOption(title: "Option B", subtitle: "Description"),
    IntentChoiceOption.cancel(title: "Not now"),
]

let choice = try await requestChoice(
    between: options,
    dialog: IntentDialog("Which option?")
)
```

---

## AppShortcutsProvider

### Complete Implementation

```swift
struct MyAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // Generic (asks for parameters)
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Log meal in \(.applicationName)",
                "Record food with \(.applicationName)",
            ],
            shortTitle: "Log Meal",
            systemImageName: "fork.knife"
        )

        // Specific (skips parameter step)
        AppShortcut(
            intent: LogMealIntent(mealType: .breakfast),
            phrases: ["Log breakfast in \(.applicationName)"],
            shortTitle: "Log Breakfast",
            systemImageName: "sunrise.fill"
        )

        // Background action
        AppShortcut(
            intent: QuickLogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Drink water with \(.applicationName)",
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )
    }

    // Prevent false Siri triggers
    static var negativePhrases: [NegativeAppShortcutPhrase] {
        NegativeAppShortcutPhrases {
            "Delete meal"
            "Remove food log"
        }
    }
}
```

### Dynamic Updates

Call when parameter options change (e.g., user adds a favorite):

```swift
func markAsFavorite(_ recipe: Recipe) {
    favorites.append(recipe)
    MyAppShortcuts.updateAppShortcutParameters()
}
```

### ShortcutTileColor Options

`.blue`, `.grape`, `.grayBlue`, `.grayBrown`, `.grayGreen`, `.lightBlue`, `.lime`, `.navy`, `.orange`, `.pink`, `.purple`, `.red`, `.tangerine`, `.teal`, `.yellow`

---

## NegativeAppShortcutPhrase

Train the system to NOT invoke your app for certain phrases:

```swift
static var negativePhrases: [NegativeAppShortcutPhrase] {
    NegativeAppShortcutPhrases {
        "Stop timer"
        "Cancel workout"
        "Delete recording"
    }
}
```

Use when phrases sound similar to your shortcuts but mean the opposite or belong to a different app.

---

## Spotlight Integration

### CSSearchableItem -- Batch Content Indexing

```swift
import CoreSpotlight

func indexRecipes(_ recipes: [Recipe]) {
    let items = recipes.map { recipe -> CSSearchableItem in
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = recipe.name
        attributes.contentDescription = "\(recipe.cuisine) -- \(recipe.prepTimeMinutes) min"
        attributes.keywords = [recipe.cuisine, "recipe", recipe.name]

        return CSSearchableItem(
            uniqueIdentifier: recipe.id.uuidString,
            domainIdentifier: "recipes",
            attributeSet: attributes
        )
    }

    CSSearchableIndex.default().indexSearchableItems(items)
}
```

**Batch size**: 100-500 items per call. Index in background, not at launch.

### Deletion

```swift
// By ID
CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString])

// By domain (all recipes)
CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["recipes"])

// Everything
CSSearchableIndex.default().deleteAllSearchableItems()
```

### NSUserActivity -- Current Screen

```swift
struct RecipeDetailView: View {
    let recipe: Recipe

    var body: some View {
        ScrollView { /* content */ }
            .userActivity("com.myapp.viewRecipe") { activity in
                activity.title = recipe.name
                activity.isEligibleForSearch = true
                activity.isEligibleForPrediction = true
                activity.persistentIdentifier = recipe.id.uuidString
                activity.appEntityIdentifier = recipe.id.uuidString

                let attributes = CSSearchableItemAttributeSet(contentType: .item)
                attributes.title = recipe.name
                attributes.contentDescription = recipe.summary
                activity.contentAttributeSet = attributes
            }
    }
}
```

**Rules for NSUserActivity:**
- Only mark screens users would want to return to (content, not settings)
- Always set `persistentIdentifier` for deletion support
- Connect to App Intents with `appEntityIdentifier`
- Maintain a strong reference (UIKit: store in property)

### Handling Spotlight Taps

```swift
// SwiftUI
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onContinueUserActivity("com.myapp.viewRecipe") { activity in
                    guard let id = activity.persistentIdentifier else { return }
                    navigator.show(recipeID: id)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    navigator.show(recipeID: id)
                }
        }
    }
}
```

---

## IndexedEntity -- Automatic Find Actions

Adopt `IndexedEntity` to auto-generate "Find X where..." actions in Shortcuts from your Spotlight index.

```swift
struct EventEntity: AppEntity, IndexedEntity {
    var id: UUID

    @Property(title: "Title", indexingKey: \.eventTitle)
    var title: String

    @Property(title: "Start Date", indexingKey: \.startDate)
    var startDate: Date

    @Property(title: "Location", indexingKey: \.eventLocation)
    var location: String?

    @Property(title: "Notes", customIndexingKey: "eventNotes")
    var notes: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Event"
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(startDate.formatted())")
    }
}
```

This gives you a free "Find Events" action in Shortcuts:
```
Find Events where:
  - Title contains "Team"
  - Start Date is today
  - Location is "San Francisco"
```

### Explicit Spotlight Indexing for IndexedEntity

```swift
func indexEvents() async {
    let events = await fetchEvents()
    try await CSSearchableIndex.default().indexAppEntities(events, priority: .normal)
}

func deleteEvent(_ event: EventEntity) async {
    try await CSSearchableIndex.default().deleteAppEntities(
        identifiedBy: [event.id],
        ofType: EventEntity.self
    )
}
```

---

## Interactive Widgets with AppIntent

Use AppIntent as the action for widget buttons and toggles.

```swift
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Task"

    @Parameter(title: "Task ID")
    var taskID: String

    func perform() async throws -> some IntentResult {
        try await TaskService.shared.toggleComplete(id: taskID)
        return .result()
    }
}

// In your widget view
struct TaskWidgetView: View {
    let task: TaskItem

    var body: some View {
        Button(intent: ToggleTaskIntent(taskID: task.id)) {
            Label(task.title, systemImage: task.isComplete ? "checkmark.circle.fill" : "circle")
        }
    }
}
```

---

## Control Center Controls

```swift
import WidgetKit

struct CaffeineLockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.myapp.caffeine") {
            ControlWidgetButton(action: LogCaffeineIntent()) {
                Label("Log Caffeine", systemImage: "cup.and.saucer.fill")
            }
        }
        .displayName("Log Caffeine")
    }
}
```

---

## Focus Filters

```swift
struct WorkFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Work Focus"
    static var description: IntentDescription = "Shows only work-related content"

    @Parameter(title: "Show Work Tasks Only")
    var workOnly: Bool

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppState.shared.focusMode = workOnly ? .work : .all
        }
        return .result()
    }
}
```

---

## AppIntentsPackage -- Modular Projects

Include intents defined in Swift Packages:

```swift
// In your package
public struct HealthKitIntentsPackage: AppIntentsPackage { }

// In your app target
struct MyAppPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HealthKitIntentsPackage.self]
    }
}
```

---

## Assistant Schemas

Apple provides pre-built intent schemas for common app categories. Conform to them for deeper Siri integration.

Available schemas: `BooksIntents`, `BrowserIntents`, `CameraIntents`, `EmailIntents`, `PhotosIntents`, `PresentationsIntents`, `SpreadsheetsIntents`, `DocumentsIntents`

```swift
import BooksIntents

struct OpenBookIntent: BooksOpenBookIntent {
    @Parameter(title: "Book")
    var target: BookEntity

    func perform() async throws -> some IntentResult {
        await MainActor.run { BookReader.shared.open(book: target) }
        return .result()
    }
}
```

---

## Visual Intelligence

### IntentValueQuery -- Camera Circle Gesture

```swift
@UnionValue
enum VisualSearchResult {
    case landmark(LandmarkEntity)
    case collection(CollectionEntity)
}

struct LandmarkIntentValueQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [VisualSearchResult] {
        // Match visual input to app entities
    }
}
```

### On-Screen Entity Tagging

```swift
struct LandmarkDetailView: View {
    let landmark: LandmarkEntity

    var body: some View {
        ScrollView { /* content */ }
            .userActivity("com.landmarks.ViewingLandmark") { activity in
                activity.title = "Viewing \(landmark.name)"
                activity.appEntityIdentifier = EntityIdentifier(for: landmark)
            }
    }
}
```

---

## Apple Intelligence Integration

Entities passed to the "Use Model" Shortcuts action are serialized as JSON. Expose meaningful `@Property` values and clear `displayRepresentation` for best results.

Use `AttributedString` instead of `String` for text parameters when rich text matters:

```swift
@Parameter(title: "Content")
var content: AttributedString  // Preserves bold, lists, tables from model output
```

---

## PredictableIntent

Enable Spotlight suggestions based on usage patterns:

```swift
struct OrderCoffeeIntent: AppIntent, PredictableIntent {
    static var title: LocalizedStringResource = "Order Coffee"
    // ... standard implementation
}
```

Spotlight learns when and how the user runs this intent and surfaces suggestions proactively.

---

## Discovery UI Components

### SiriTipView

```swift
SiriTipView(intent: LogWeightIntent(), isVisible: $showTip)
    .siriTipViewStyle(.automatic)  // .light, .dark, .automatic
```

Show after the user completes an action to teach the voice shortcut. The intent must be used in an `AppShortcut` or SiriTipView renders empty.

### ShortcutsLink

```swift
// In settings or help screen
ShortcutsLink()  // Opens your app's page in Shortcuts app
```

---

## Error Handling

```swift
enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notFound(String)
    case unauthorized
    case networkFailure

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound(let name): "Sorry, \(name) could not be found"
        case .unauthorized: "Please open the app and sign in first"
        case .networkFailure: "Network error. Please try again"
        }
    }
}
```

---

## Requesting Missing Parameter Values

```swift
func perform() async throws -> some IntentResult {
    guard let quantity, quantity > 0, quantity < 100 else {
        throw $quantity.needsValue("How many would you like?")
    }
    // proceed
}
```

---

## Testing & Debugging

### Manual Testing Checklist

1. **Shortcuts app**: Create new shortcut, search for your app, verify intents appear
2. **Parameter resolution**: Fill in parameters, run shortcut, check Xcode console
3. **Siri**: Say your phrase, verify dialog and result
4. **Spotlight**: Search for your app or phrase, verify shortcuts appear

### Common Issues

| Symptom | Cause | Fix |
|---|---|---|
| Intent not in Shortcuts | `isDiscoverable = false` or missing | Set `isDiscoverable = true` (default) |
| Parameter won't resolve | Missing `defaultQuery` on entity | Add `static var defaultQuery` |
| Crash in background | MainActor access without isolation | Use `await MainActor.run { }` |
| Empty entity suggestions | `suggestedEntities()` not implemented | Return recent/relevant items (max 10-20) |
| Shortcut not in Spotlight | Not in `AppShortcutsProvider` | Add to `appShortcuts` array |
| SiriTipView empty | Intent not in an `AppShortcut` | Add intent to `AppShortcutsProvider` |
| Spotlight results missing | No `CSSearchableItem` indexed | Index content with Core Spotlight |
| Intent not on Spotlight (Mac) | Required param missing from summary | Include all required params in summary, or make optional |

### Debug Intent in Code

```swift
#if DEBUG
extension LogWeightIntent {
    static func testIntent() async throws {
        var intent = LogWeightIntent()
        intent.weight = Measurement(value: 75, unit: .kilograms)
        let result = try await intent.perform()
        print("Result: \(result)")
    }
}
#endif
```

---

## Discoverability Strategy Summary

For comprehensive system integration, implement all layers:

| Layer | API | Purpose |
|---|---|---|
| 1. Actions | AppIntent | Expose functionality |
| 2. Instant access | AppShortcutsProvider | Zero-setup availability |
| 3. Content search | CSSearchableItem | Batch index app content |
| 4. Screen context | NSUserActivity | Mark current screen for prediction |
| 5. Auto-find | IndexedEntity | "Find X where..." in Shortcuts |
| 6. User education | SiriTipView + ShortcutsLink | Teach users about shortcuts |

The system boosts intents that users actually invoke. Good metadata + clear utility = higher ranking.
