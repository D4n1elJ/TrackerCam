# Core Data

Write, review, and govern Core Data code for correctness, thread safety, migration safety, and performance. Report only genuine problems -- do not nitpick or invent issues.

## Responsibility

**Owns:**

- NSPersistentContainer / NSPersistentCloudKitContainer stack setup
- NSManagedObject subclasses, relationships, delete rules, fetch requests
- Thread-confinement rules, context concurrency types, `perform` / `performAndWait`
- NSManagedObjectID as the Sendable cross-context reference
- Schema versioning with .xcdatamodel versions and mapping models
- Lightweight and custom migration (NSEntityMigrationPolicy, NSMigrationManager)
- Batch operations (NSBatchInsertRequest, NSBatchUpdateRequest, NSBatchDeleteRequest)
- CloudKit-specific Core Data constraints (NSPersistentCloudKitContainer, history tracking)
- Merge policies, faulting, prefetching, and fetch performance

**Does NOT own:**

- SwiftUI `@FetchRequest` binding details (SwiftUI skill)
- Actor design and Swift Concurrency patterns beyond Core Data integration (Swift Concurrency skill)
- SwiftData models, `@Model`, `#Predicate`, `FetchDescriptor` (SwiftData skill)
- General SQLite, GRDB, or Realm

## Core Principles

1. NSManagedObject instances are thread-confined. Never pass them across threads or actor boundaries.
2. Pass `NSManagedObjectID` (which is `Sendable`) to transfer references between contexts.
3. All context access must happen inside `perform` or `performAndWait` (or the async `perform` variant).
4. Persisted schema changes are product changes. Default to migration.
5. No silent destructive fallback outside `DEBUG`.
6. Store failures fail loudly and diagnostically.
7. Simulator deletes the database on rebuild. Always test migrations on a real device or with a production database copy.
8. Issue severity ranking: data loss > crash > incorrect behaviour > performance.

## Decision Tree: Core Data vs SwiftData

```
Which persistence framework?

+-- Targeting iOS 17+ only?
|   +-- Simple data model, no legacy Core Data? --> SwiftData
|   +-- Need public CloudKit database? --> Core Data (SwiftData is private-only)
|   +-- Need custom migration logic beyond lightweight? --> Core Data
|   +-- Need batch insert/update/delete? --> Core Data
|   +-- Need NSFetchedResultsController? --> Core Data
|   +-- Existing Core Data codebase? --> Keep Core Data or migrate gradually
|
+-- Targeting iOS 16 or earlier?
|   +-- Core Data (SwiftData unavailable)
|
+-- Need both?
    +-- Advanced: use Core Data with SwiftData coexistence (separate entities, never both on same store)
```

## Review Process

1. Check concurrency patterns using `references/concurrency-patterns.md`.
2. If the project has schema changes, check migration strategy using `references/migration-patterns.md`.
3. Verify relationships have explicit delete rules.
4. Check fetch requests for N+1 patterns (missing `relationshipKeyPathsForPrefetching`).
5. Verify merge policy is set on contexts that receive remote changes.
6. For any store deletion code, verify it is `DEBUG`-only.

If doing partial work, load only the relevant reference files.

## Core Instructions

- Target Swift 6.2 or later, using modern Swift concurrency with Core Data's `perform` API.
- Use `NSPersistentContainer` (iOS 10+) as the standard stack. Do not build raw coordinator stacks.
- Always set `automaticallyMergesChangesFromParent = true` on the view context.
- Always set a merge policy on contexts that may receive concurrent changes.
- Use `newBackgroundContext()` or `performBackgroundTask` for writes and imports. Never write on the view context for heavy operations.
- Specify explicit delete rules on all relationships. The default `.nullify` can orphan objects or crash on non-optional properties.
- Use `fetchBatchSize` on fetch requests that may return large result sets.
- Use `relationshipKeyPathsForPrefetching` when relationships will be accessed in a loop.
- Do not introduce third-party frameworks without asking first.

## Anti-Patterns

### 1. Passing NSManagedObject across threads

```swift
// WRONG
let user = viewContext.fetch(...)
Task.detached {
    print(user.name)  // CRASH: wrong thread
}

// CORRECT
let userID = user.objectID
Task.detached {
    let bgContext = container.newBackgroundContext()
    let user = bgContext.object(with: userID) as! User
    await bgContext.perform { print(user.name) }
}
```

### 2. Singleton context for all operations

```swift
// WRONG -- using main context on background thread
class DataManager {
    let context = stack.viewContext
    func importInBackground() {
        for item in largeDataset {
            let entity = Entity(context: context)  // Main-thread context off main thread
        }
    }
}

// CORRECT -- background context for background work
func importInBackground() {
    let bgContext = container.newBackgroundContext()
    bgContext.perform {
        for item in largeDataset {
            let entity = Entity(context: bgContext)
        }
        try? bgContext.save()
    }
}
```

### 3. Fetching in SwiftUI view body

```swift
// WRONG -- fetch on every render
var body: some View {
    let users = try? context.fetch(User.fetchRequest())
    List(users ?? []) { ... }
}

// CORRECT -- use @FetchRequest
@FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \User.name, ascending: true)])
var users: FetchedResults<User>

var body: some View {
    List(users) { ... }
}
```

### 4. No merge policy

```swift
// WRONG -- conflicts crash with default error policy
let context = container.viewContext

// CORRECT
context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
context.automaticallyMergesChangesFromParent = true
```

### 5. Force lightweight migration without testing

```swift
// WRONG -- crashes on real devices with changed schema
let description = NSPersistentStoreDescription()
// No migration options, no testing

// CORRECT
description.shouldMigrateStoreAutomatically = true
description.shouldInferMappingModelAutomatically = true
// Plus: test on real device with old database
```

## Performance Tips

1. Set `fetchBatchSize` (e.g. 20-100) for large result sets.
2. Prefetch relationships with `relationshipKeyPathsForPrefetching` before loops.
3. Use background contexts for imports and exports.
4. Batch save -- do not save after each insert.
5. Use `fetchLimit` when only the first N results are needed.
6. Profile with `-com.apple.CoreData.SQLDebug 1` launch argument.
7. Use `NSBatchInsertRequest` for bulk imports (bypasses validation and change tracking for speed).

## Output Format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary.

If the user asks you to write or improve code, follow the same rules above but make the changes directly.

## Key Warnings

- `NSManagedObject` is not `Sendable`. Never send instances across actor boundaries.
- `NSManagedObjectID` IS `Sendable` -- use it as the cross-context handle.
- `@FetchRequest` only works inside SwiftUI views. Using it elsewhere produces incorrect behaviour.
- Simulator deletes the database on rebuild, hiding schema mismatch crashes. Real devices keep persistent data.
- Do not access the same SQLite store from both Core Data and SwiftData simultaneously.
- `performBackgroundTask` creates AND executes on a throwaway context. `newBackgroundContext` creates a reusable context you manage yourself.

## References

- `references/concurrency-patterns.md` -- NSManagedObject sendability, DAO pattern, custom actor executor, background contexts, batch operations.
- `references/migration-patterns.md` -- Lightweight migration, custom migration with NSMigrationManager, model versioning, CloudKit constraints, testing migrations.
