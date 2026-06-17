# Runtime Patterns

> How the single SwiftData container is assembled, provisioned, and used across the app.

## Single ModelContainer Per Process

- One long-lived production `ModelContainer` instance per process.
- Test and dev-view contexts use ephemeral in-memory `ModelContainer` instances.
- Features MUST NOT create their own `ModelContainer`. Allowed callers: persistence infrastructure, test targets, and dev-view debug screens only.
- If container creation fails, startup MUST fail deterministically — no silent fallback container.

## Container Creation

```swift
final class PersistenceContainer {

    let modelContainer: ModelContainer

    /// Production — persistent store in App Group container.
    init(appGroup: String = "group.com.example.app") throws {
        let configuration = ModelConfiguration(
            schema: PersistenceSchema.schema,
            groupContainer: .identifier(appGroup)
        )
        self.modelContainer = try ModelContainer(
            for: PersistenceSchema.schema,
            migrationPlan: PersistenceMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Test/dev-view — in-memory, ephemeral.
    init(inMemory: Bool) throws {
        let configuration = ModelConfiguration(
            schema: PersistenceSchema.schema,
            isStoredInMemoryOnly: inMemory
        )
        self.modelContainer = try ModelContainer(
            for: PersistenceSchema.schema,
            migrationPlan: PersistenceMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
```

## App Group Sharing

Production configuration MUST use `ModelConfiguration(groupContainer: .identifier(appGroupID))` so the main app and extensions (e.g. widgets) read the same store.

## Context Provisioning

### mainContext — for UI reads

```swift
@MainActor
var mainContext: ModelContext {
    modelContainer.mainContext
}
```

- Lives on `@MainActor`.
- Use for all read operations that feed SwiftUI views.
- MUST NOT be used for heavy writes or batch imports.

### backgroundContext() — for writes and imports

```swift
func backgroundContext() -> ModelContext {
    ModelContext(modelContainer)
}
```

- Returns a new `ModelContext` each time. Cheap to create.
- Use for writes, batch imports, data syncing.
- MUST be used off the main actor.
- Never cache or share across tasks.

### Context Injection

Features receive a `ModelContext` via constructor injection. They do not know whether it is a main or background context:

```swift
final class HabitRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [HabitModel] {
        let descriptor = FetchDescriptor<HabitModel>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
}
```

For features that need both read and write contexts, inject a context provider protocol:

```swift
protocol ModelContextProviding: Sendable {
    @MainActor var mainContext: ModelContext { get }
    func backgroundContext() -> ModelContext
}
```

`ModelContextProviding` is `Sendable` with `@MainActor` on `mainContext` only. `backgroundContext()` must remain non-isolated so callers can create contexts off the main actor. Each call returns a fresh, unshared `ModelContext`.

## Write Transaction Contract

For any mutation path (create/update/delete), execute this sequence:

1. **Obtain** a `ModelContext` — `mainContext` for lightweight UI edits, `backgroundContext()` for imports/batch writes.
2. **Mutate** — perform inserts, updates, or deletes.
3. **Save** — call `try modelContext.save()`. Skipping this means no persistence guarantee.
4. **Propagate** — surface save errors to the caller. No silent retries inside repositories.
5. **Re-fetch** — if returning read models that must reflect committed state, re-fetch before returning.

## Visibility Semantics

- Committed changes are guaranteed to appear on a subsequent `mainContext.fetch()` or re-evaluated `@Query`.
- Previously fetched arrays are not guaranteed to mutate in place.
- New fetch or re-evaluated `@Query` after save is required for deterministic reads.

## Cross-Reference Rules

- Features query their own `@Model` types directly using `FetchDescriptor`, `#Predicate`, and `modelContext.fetch()`.
- Features MUST NOT query another feature's entities.
- Link across feature boundaries by `UUID` only — never `@Relationship`.
- Never pass a `ModelContext` across actor boundaries.

| From | To | Mechanism |
|---|---|---|
| Feature -> own local data | `ModelContext` + `FetchDescriptor` | Direct SwiftData queries |
| Feature -> another feature's data | Forbidden | Store `UUID`, resolve at UI layer |
| Feature-local entity -> shared entity | Store `UUID` field | Never `@Relationship` |

## Ephemeral In-Memory for Tests

Test targets create their own in-memory `ModelContainer` instances. This gives each test a clean, isolated store without touching disk. Dev-view debug screens (`#if DEBUG`) may also create in-memory containers with only their feature's models for isolated testing.
