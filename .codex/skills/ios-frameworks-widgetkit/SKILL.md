---
name: ios-frameworks-widgetkit
description: Use when implementing or debugging WidgetKit timelines, widgets, Live Activities, Control Center controls, or extension lifecycle limits.
---

# Widgets

Review and write iOS widget, Live Activity, and Control Center control code for correctness, budget efficiency, and production reliability.

## Responsibility

**Owns:** WidgetKit timelines, TimelineProvider, widget families, interactive widgets, Live Activities (ActivityKit), Dynamic Island, Control Center controls (ControlWidget), App Groups data sharing, widget refresh budgets, extension memory limits, Liquid Glass widget styling, visionOS spatial widgets.

**Does NOT own:** App Intents definition syntax (see ios-architecture), SwiftUI layout (see swiftui-patterns), push notification server setup (see networking), general SwiftUI performance (see swiftui-patterns).

## Core Principles

1. **Widgets are archived snapshots, not live views.** Your widget renders, gets archived, and the system displays the snapshot. It does not run continuously.
2. **Never network in widget views.** Fetch data in `TimelineProvider.getTimeline()` or prefetch in the main app and read from shared storage. Widget views may not execute network calls.
3. **Respect the refresh budget.** System allows 40-70 timeline reloads per day. Exceeding this silently stops updates. Use 15-60 minute intervals for most widgets.
4. **App Groups for all data sharing.** App and extension have separate containers. Use `UserDefaults(suiteName:)` or shared container files. `UserDefaults.standard` returns nil in extensions.
5. **ActivityAttributes + ContentState must stay under 4KB.** Store IDs and references, not full objects. Use asset catalogs for images. Measure size before shipping.
6. **End Live Activities explicitly.** Every activity must call `.end()` with a dismissal policy. Zombie activities generate negative reviews.
7. **Optimistic UI for controls.** Update cached state immediately in `perform()`, then sync the real device in the background. Users expect instant feedback.

## Decision Tree

```
What type of extension?
|
+-- Static widget (no user config)
|   +-- StaticConfiguration + TimelineProvider
|   +-- supportedFamilies() required or widget won't appear in gallery
|
+-- Configurable widget (user picks data source)
|   +-- AppIntentConfiguration + WidgetConfigurationIntent
|   +-- EntityQuery for dynamic options from app data
|
+-- Interactive widget (buttons/toggles, iOS 17+)
|   +-- Button(intent:) or Toggle with AppIntent
|   +-- perform() updates App Group storage + reloads timelines
|
+-- Live Activity (ongoing event on Lock Screen)
|   +-- ActivityConfiguration + ActivityAttributes
|   +-- Local updates first (no entitlement needed)
|   +-- Push updates after entitlement approval (3-7 days)
|   +-- Dynamic Island: compact, expanded, minimal layouts
|
+-- Control Center control (iOS 18+)
|   +-- ControlWidget + StaticControlConfiguration
|   +-- ControlValueProvider for async state
|   +-- previewValue for instant fallback
|
+-- visionOS spatial widget
    +-- mountingStyles: .elevated (tables), .recessed (walls)
    +-- widgetTexture: .glass or .paper
    +-- levelOfDetail for proximity-aware layout
```

## Red Flags

| Anti-Pattern | Debug Time | Fix |
|---|---|---|
| Network call in widget view body | 2-4 hours | Fetch in `getTimeline()` or prefetch in main app, read from shared storage |
| `UserDefaults.standard` in extension | 1-2 hours | Use `UserDefaults(suiteName: "group.com.myapp")` in both targets |
| Timeline entries every 1 minute | 1-2 hours | Use 15-60 minute intervals, 8-12 entries per timeline. Widget stops updating after budget exhaustion |
| Missing `supportedFamilies()` | 30 minutes | Add `.supportedFamilies([...])` to widget configuration |
| Widget not in gallery | 30-60 minutes | Check WidgetBundle registration, Skip Install = NO, extension embedded, clean build. See debugging guide |
| No `.end()` on Live Activity | User complaints | Always call `activity.end(_:dismissalPolicy:)` when event completes |
| Image Data in ActivityAttributes | 1-2 hours | Use asset catalog names (String), not raw Data. Silent start failure, hard to debug |
| Blocking call in ControlWidget view | 30 minutes | Use `ControlValueProvider` with async `currentValue()` |
| `AsyncImage` in widget | 30 minutes | Use asset catalog images or SF Symbols. `AsyncImage` does not work in widgets |
| Writing to SwiftData/GRDB from widget | 2-4 hours | Widget reads only. Main app writes and calls `reloadAllTimelines()`. Data corruption is hard to diagnose |

## Memory and Size Limits

| Resource | Limit | Consequence |
|---|---|---|
| Standard widget memory | ~30 MB | System terminates extension |
| Live Activity memory | ~50 MB | System terminates extension |
| ActivityAttributes + ContentState | 4 KB (4096 bytes) | `Activity.request()` throws, activity never appears |
| Timeline generation time | 30 seconds | System kills extension process |
| `getTimeline()` target completion | < 5 seconds | Slow timelines degrade user experience |
| Timeline entries per reload | 10-20 recommended | More wastes budget, fewer causes gaps |
| Daily timeline reload budget | 40-70 | Exhausted budget = no more updates that day |

## Pre-Ship Checklist

- [ ] App Groups entitlement in BOTH app and extension targets with matching identifier
- [ ] No `UserDefaults.standard` in widget code
- [ ] No network calls in widget view body
- [ ] Timeline intervals >= 15 minutes for standard widgets
- [ ] All supported families tested and layout correct
- [ ] Widget appears in widget gallery with name and description
- [ ] ActivityAttributes + ContentState < 2 KB (safe margin) or < 4 KB (hard limit)
- [ ] Live Activities call `.end()` with dismissal policy
- [ ] Control Center controls use `ControlValueProvider` with `previewValue`
- [ ] Tested on real device (simulator skips budget limits, push, and memory enforcement)
- [ ] Handles missing/nil data gracefully (no crashes on empty shared storage)

## References

- `references/timeline-patterns.md` — TimelineProvider, refresh budgets, configurable widgets, snapshot vs timeline
- `references/live-activities.md` — ActivityAttributes, Dynamic Island, push updates, phased shipping, zombie activities
- `references/controls-and-platforms.md` — Control Center, interactive widgets, visionOS, watchOS, SwiftData/GRDB sharing, Liquid Glass, widget relevance
- `references/debugging-guide.md` — Troubleshooting decision tree, per-category debugging checklists, widget gallery issues
