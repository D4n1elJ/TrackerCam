# Timeline Patterns

## TimelineProvider Protocol

Three required methods, each with a distinct purpose:

```swift
struct Provider: TimelineProvider {
    // Shown while widget loads for the first time. Must return synchronously.
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: "—")
    }

    // Shown in widget gallery preview. Should return representative data fast.
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), data: loadCachedData())
        completion(entry)
    }

    // Actual timeline the system archives and displays over time.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let data = loadFromSharedStorage()
        var entries: [SimpleEntry] = []

        for offset in 0..<8 {
            let date = Calendar.current.date(byAdding: .minute, value: offset * 15, to: Date())!
            entries.append(SimpleEntry(date: date, data: data))
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}
```

**placeholder** — Synchronous, redacted layout. No real data.
**getSnapshot** — Fast, representative. System calls this for gallery and transitions. If `context.isPreview` is true, return sample data immediately.
**getTimeline** — The real work. Generates entries with future dates for the system to display at each time.

## Refresh Budget

System grants 40-70 timeline reloads per day. Budget varies by user engagement and system load.

**Budget-exempt reloads** (do not count against limit):
- User adds or removes widget
- App returns to foreground
- System reboot
- Explicit `WidgetCenter.shared.reloadTimelines(ofKind:)` from app (limited)

### Practical Budget Math

| Strategy | Reloads/Hour | Daily Use | Battery |
|---|---|---|---|
| Every 15 min, `.atEnd` | 4 | ~48/day, may exhaust by evening | Moderate |
| Every 30 min, `.atEnd` | 2 | ~24/day, safe all day | Low |
| Every 60 min, `.atEnd` | 1 | ~12/day, minimal impact | Minimal |
| On-demand only (`.never` + manual) | varies | 5-10/day | Minimal |

**Recommendation:** Start with 30-minute intervals. Tighten only if the data genuinely changes more often.

```swift
// 8 entries at 30-minute intervals = 4 hours of coverage per reload
let entries = (0..<8).map { offset in
    let date = Calendar.current.date(byAdding: .minute, value: offset * 30, to: Date())!
    return SimpleEntry(date: date, data: currentData)
}
let timeline = Timeline(entries: entries, policy: .atEnd)
```

### Timeline Reload Policies

- **`.atEnd`** — System requests new timeline after last entry's date. Most common.
- **`.after(date)`** — System requests new timeline at a specific date. Use when you know the next meaningful update time.
- **`.never`** — No automatic reload. Widget only updates via `WidgetCenter.shared.reloadTimelines(ofKind:)`.

### Manual Reload from Main App

```swift
import WidgetKit

// After writing new data to shared storage:
WidgetCenter.shared.reloadAllTimelines()

// Or target a specific widget kind:
WidgetCenter.shared.reloadTimelines(ofKind: "MyWidget")
```

Call this when your app writes data that the widget should reflect. Do not call it speculatively.

## Network Requests in TimelineProvider

Network calls ARE allowed in `getTimeline()`, but with constraints:

```swift
func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
    Task {
        do {
            let data = try await fetchFromAPI()
            let entry = SimpleEntry(date: Date(), data: data)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
        } catch {
            // Fallback to cached data on failure
            let cached = loadFromSharedStorage()
            let entry = SimpleEntry(date: Date(), data: cached)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
        }
    }
}
```

**Constraints:**
- **30-second timeout** — System kills the extension if `getTimeline()` does not complete
- **No background sessions** — Cannot download large files
- **Unreliable on poor connections** — Always have a cached fallback

**Best practice:** Prefetch in the main app (faster, more reliable). Use TimelineProvider network as fallback only.

## Configurable Widgets (iOS 17+)

### AppIntentConfiguration

Replace `StaticConfiguration` with `AppIntentConfiguration` to let users pick what data the widget shows.

```swift
struct MyConfigurableWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "ProjectWidget",
            intent: SelectProjectIntent.self,
            provider: ProjectProvider()
        ) { entry in
            ProjectWidgetView(entry: entry)
        }
        .configurationDisplayName("Project Status")
        .description("Shows your selected project")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

### WidgetConfigurationIntent

```swift
struct SelectProjectIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Project"
    static var description = IntentDescription("Choose which project to display")

    @Parameter(title: "Project")
    var project: ProjectEntity?
}
```

### AppIntentTimelineProvider

```swift
struct ProjectProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProjectEntry {
        ProjectEntry(date: Date(), project: .placeholder)
    }

    func snapshot(for configuration: SelectProjectIntent, in context: Context) async -> ProjectEntry {
        let project = await loadProject(configuration.project?.id)
        return ProjectEntry(date: Date(), project: project)
    }

    func timeline(for configuration: SelectProjectIntent, in context: Context) async -> Timeline<ProjectEntry> {
        let project = await loadProject(configuration.project?.id)
        let entry = ProjectEntry(date: Date(), project: project)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800)))
    }
}
```

### EntityQuery for Dynamic Options

```swift
struct ProjectEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Project")
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = ProjectQuery()
}

struct ProjectQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        await ProjectStore.shared.projects(withIDs: identifiers)
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        await ProjectStore.shared.allProjects()
    }
}
```

## Widget Families Quick Reference

### System Families (Home Screen)
- **`systemSmall`** (~170x170pt) — Single piece of info
- **`systemMedium`** (~360x170pt) — Multiple data points
- **`systemLarge`** (~360x380pt) — Detailed view, list
- **`systemExtraLarge`** (~720x380pt, iPad only)

### Accessory Families (Lock Screen, iOS 16+)
- **`accessoryCircular`** (~48x48pt) — Icon or gauge
- **`accessoryRectangular`** (~160x72pt) — Text + icon
- **`accessoryInline`** (single line) — Text only, above date

### Adapting Layout Per Family

```swift
@Environment(\.widgetFamily) var family

var body: some View {
    switch family {
    case .systemSmall:
        CompactView(entry: entry)
    case .systemMedium:
        MediumView(entry: entry)
    case .accessoryCircular:
        CircularView(entry: entry)
    default:
        Text(entry.title)
    }
}
```
