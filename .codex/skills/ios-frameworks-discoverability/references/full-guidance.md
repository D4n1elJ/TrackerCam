# App Discoverability

## Purpose

Strategy skill for making your app surface across iOS system experiences. Coordinates four APIs into a unified discoverability plan. iOS 26+ only.

**Core principle:** Feed the system metadata through multiple APIs. The system decides when and where to surface your app based on context and actual usage.

**This skill owns:** The strategy — which API for which content, how they connect, what to review, how to debug.

**Does NOT own:** API implementation details. For code patterns, see:
- `app-intents` — AppIntent, AppEntity, AppShortcutsProvider, execution modes
- the `app-intents` skill's `references/intent-patterns.md` — CSSearchableItem, NSUserActivity, IndexedEntity, Spotlight tap handling

## The Four Discoverability APIs

| API | What It Surfaces | Where It Appears | When to Use |
|---|---|---|---|
| **AppIntent + AppShortcutsProvider** | Actions (verbs) | Siri, Spotlight, Shortcuts, Action Button, Control Center | Every app — this is the foundation |
| **Core Spotlight (CSSearchableItem)** | Content (nouns) | Spotlight search results | Apps with searchable content (notes, orders, recipes, workouts) |
| **NSUserActivity** | Screen context | Siri suggestions, Spotlight, Handoff | High-value detail screens users revisit |
| **IndexedEntity** | Queryable entities | "Find X where..." in Shortcuts | Entities with filterable properties |

**No single API is sufficient.** A well-discoverable app uses at least AppShortcutsProvider + one content API.

## Decision Framework

```
What are you making discoverable?
|
+-- An ACTION the user triggers?
|   +-- AppIntent (always)
|   +-- AppShortcutsProvider (for instant zero-setup availability)
|
+-- CONTENT the user searches for?
|   |
|   +-- Batch indexing many items (documents, orders, history)?
|   |   +-- CSSearchableItem with domainIdentifier
|   |
|   +-- Current screen the user is viewing?
|   |   +-- NSUserActivity with isEligibleForSearch + isEligibleForPrediction
|   |
|   +-- Entity with filterable properties?
|       +-- IndexedEntity + @Property with indexingKey
|       +-- Also call CSSearchableIndex.default().indexAppEntities()
|
+-- BOTH action and content?
    +-- AppIntent for the action
    +-- NSUserActivity.appEntityIdentifier to connect screen → entity
    +-- IndexedEntity for "Find X where..." queries
```

## Strategy: Layered Implementation

### Layer 1: Actions (Required)

Define 3-5 core AppIntents for your app's most valuable actions. Wrap them in AppShortcutsProvider for instant availability.

**What "most valuable" means:** Actions users repeat. Actions that save time. Actions where voice/Spotlight is faster than opening the app.

**See:** `app-intents` for AppIntent patterns, phrase rules, and anti-patterns.

### Layer 2: Content Search (When You Have Searchable Content)

Index user-facing content in Core Spotlight. Mark detail screens with NSUserActivity.

**What to index:** Recent items, favourites, frequently accessed content. Not everything — selective indexing ranks higher and avoids quota issues.

**What NOT to index:** Settings screens, onboarding, error states, debug views, transient UI.

**See:** the `app-intents` skill's `references/intent-patterns.md` § Spotlight Integration for CSSearchableItem and NSUserActivity code.

### Layer 3: Queryable Entities (When Entities Have Filterable Properties)

Adopt IndexedEntity on AppEntity types to get automatic "Find X where..." actions in Shortcuts.

**When it's worth it:** Your entities have 2+ properties users would filter on (date, category, location, status).

**See:** the `app-intents` skill's `references/intent-patterns.md` § IndexedEntity for @Property and indexingKey patterns.

### Layer 4: User Education

Even perfect metadata is useless if users don't know shortcuts exist.

```swift
// Show after a relevant action completes
SiriTipView(intent: LogWeightIntent(), isVisible: $showTip)
    .siriTipViewStyle(.automatic)

// In settings or help screen
ShortcutsLink()
```

**Placement rules:**
- Show `SiriTipView` contextually — after the user completes the action the shortcut automates
- Don't show on first launch (too early, no context)
- Dismiss after 2-3 exposures (respect the user)

## Connecting the APIs

The APIs are strongest when linked together:

| Connection | How | Why |
|---|---|---|
| NSUserActivity → AppEntity | `activity.appEntityIdentifier = entity.id` | System links screen visits to entity, improving suggestions |
| CSSearchableItem → deep link | `uniqueIdentifier` matches your navigation ID | Spotlight tap opens the right screen |
| IndexedEntity → Spotlight | `CSSearchableIndex.default().indexAppEntities()` | Explicit indexing with priority control |
| AppShortcut → prediction | `IntentDonationManager.shared.donate(intent:)` or `.isEligibleForPrediction` | System learns usage patterns and surfaces proactively |

## Indexing Strategy

### What to Index

| Content Type | API | Index When |
|---|---|---|
| User-created content (notes, entries) | CSSearchableItem | On create/update/delete |
| Browsable catalogue (< 500 items) | CSSearchableItem batch | On first launch + incremental |
| Large catalogue (500+ items) | CSSearchableItem batch (100/batch) | Background task, not at launch |
| Currently viewed detail screen | NSUserActivity | On screen appear |
| Entities with filterable properties | IndexedEntity + indexAppEntities | On data change |

### Incremental Indexing

Index on data change, not on every launch. Use `domainIdentifier` to group related content for efficient bulk operations.

```swift
// Delete all items in a domain, then re-index current set
CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["workouts"])
CSSearchableIndex.default().indexSearchableItems(currentWorkoutItems)
```

### Deletion Hygiene

**Every index operation needs a corresponding delete.** When content is removed from your app, remove it from Spotlight. Stale results that open to empty screens damage trust.

## Anti-Patterns

| Pattern | Problem | Fix |
|---|---|---|
| AppIntents without AppShortcutsProvider | Users must manually configure shortcuts | Always add AppShortcutsProvider for core actions |
| Index everything | Quota issues, poor ranking, slow launch | Index selectively: recent, favourites, frequently accessed |
| Generic titles ("Action", "Item") | Users can't understand what the intent does in Spotlight | Verb-noun titles: "Log Weight", "Start Workout" |
| Mark every screen for prediction | System can't distinguish important from trivial | Only content screens users revisit |
| NSUserActivity without appEntityIdentifier | Missed connection between screen visits and entities | Always link when the screen shows an entity |
| No deletion when content removed | Stale Spotlight results open empty screens | Delete from index when deleting from app |
| Index at launch | Blocks app startup, poor UX | Index in background or on data change |
| No user education | Users never discover shortcuts exist | SiriTipView after relevant actions, ShortcutsLink in settings |
| Spotlight-only without App Intents | Content found but no actions available | Pair content indexing with actionable intents |

## Code Review Checklist

### App Intents Layer
- [ ] 3-5 core actions defined as AppIntents
- [ ] AppShortcutsProvider implemented with suggested phrases
- [ ] Phrases include `\(.applicationName)`, are 3-6 words, start with verb
- [ ] Parameter summaries use natural language
- [ ] ShortcutTileColor matches app brand

### Content Indexing Layer
- [ ] Only user-valuable content is indexed (not settings, debug, transient UI)
- [ ] Unique identifiers are stable and persistent (UUID or database primary key)
- [ ] Domain identifiers group related content for bulk deletion
- [ ] Attributes include title, description, and keywords
- [ ] Deletion logic exists — removing content also removes from index
- [ ] Batch indexing happens in background, not at launch

### NSUserActivity Layer
- [ ] Only high-value detail screens marked eligible
- [ ] `isEligibleForSearch` and `isEligibleForPrediction` set appropriately
- [ ] `persistentIdentifier` set for deletion support
- [ ] `appEntityIdentifier` connects to AppEntity when applicable
- [ ] `contentAttributeSet` provides title + description

### IndexedEntity Layer
- [ ] @Property with indexingKey on filterable properties
- [ ] Explicit `indexAppEntities()` called on data changes
- [ ] Entity deletion calls `deleteAppEntities()`

### User Education Layer
- [ ] SiriTipView shown contextually after relevant actions
- [ ] ShortcutsLink available in settings or help
- [ ] Tips dismissed after reasonable exposure count

### Deep Linking
- [ ] `.onContinueUserActivity` handles Spotlight taps
- [ ] `.onContinueUserActivity(CSSearchableItemActionType)` handles CSSearchableItem taps
- [ ] Navigation resolves the correct screen from the identifier

## Debugging Spotlight Issues

### Content Not Appearing

1. **Verify indexing succeeded** — add logging to `indexSearchableItems` completion
2. **Wait** — Spotlight can take 10-30 seconds to process new items
3. **Search exact title first** — partial keyword matching takes longer to rank
4. **Check `contentType`** — use `.item` for general content
5. **Check device settings** — Settings → Siri & Search → [Your App] → "Show in Search" must be on

### Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| Content never appears | Missing `title` on attribute set | Always set `attributeSet.title` |
| Low ranking in results | No keywords, no usage signal | Add `keywords` array; use the app to build signal |
| Stale results | Content deleted but not de-indexed | Call `deleteSearchableItems(withIdentifiers:)` |
| Duplicates in results | Unstable unique identifiers | Use persistent IDs (UUID, database PK) |
| Shortcuts not in Spotlight | Missing from `AppShortcutsProvider` | Add to `appShortcuts` array |
| Intent not on Mac Spotlight | Required param missing from summary | Include all required params or make optional |

### Programmatic Verification

```swift
import CoreSpotlight

// Search for indexed items
let query = CSSearchQuery(queryString: "title == 'My Item'*", attributes: ["title"])
query.foundItemsHandler = { items in
    print("Found \(items.count) items")
}
query.start()
```

## Global Rules

| Rule | Value |
|---|---|
| Max App Shortcuts | 3-5 core actions |
| Content indexing batch size | 100-500 items per call |
| Index timing | On data change or background task, never at launch |
| NSUserActivity eligibility | Content screens only, never settings/debug/onboarding |
| Deletion | Every index path needs a delete path |
| User education | SiriTipView contextually, not at first launch |
| Deployment target | iOS 26+ only — no `@available` |
