# Concurrency Patterns

> Thread-confinement, Sendable boundaries, background contexts, and batch operations for Core Data under Swift 6 strict concurrency.

## The Golden Rule

NSManagedObject instances are confined to the NSManagedObjectContext that created them. Accessing a managed object from any other thread or context is undefined behaviour -- it may crash immediately, corrupt data silently, or appear to work until load increases.

## NSManagedObject Is Not Sendable

`NSManagedObject` does not and cannot conform to `Sendable`. Under Swift 6 strict concurrency, passing a managed object across an isolation boundary is a compiler error.

The fix: pass `NSManagedObjectID` instead. It is `Sendable`, stable after the first save, and can be resolved to a concrete object on any context.

```swift
// Extract ID on one context
let userID: NSManagedObjectID = user.objectID

// Resolve on another context
let bgContext = container.newBackgroundContext()
try await bgContext.perform {
    let user = try bgContext.existingObject(with: userID) as! User
    user.lastSyncDate = .now
    try bgContext.save()
}
```

**Temporary IDs**: Before the first save, `objectID` returns a temporary ID. If you need to reference an object across contexts, save first so the ID becomes permanent. Check with `objectID.isTemporaryID`.

## The DAO Pattern

When you need to pass Core Data values across actor boundaries, project managed objects into plain Sendable value types (Data Access Objects):

```swift
struct UserDAO: Sendable {
    let objectID: NSManagedObjectID
    let name: String
    let email: String
    let createdAt: Date
}

extension User {
    var dao: UserDAO {
        UserDAO(
            objectID: objectID,
            name: name ?? "",
            email: email ?? "",
            createdAt: createdAt ?? .distantPast
        )
    }
}
```

Fetch inside `perform`, project to DAOs, return the value types:

```swift
func fetchActiveUsers() async throws -> [UserDAO] {
    let context = container.newBackgroundContext()
    return try await context.perform {
        let request = User.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let results = try context.fetch(request)
        return results.map(\.dao)
    }
}
```

## Custom Actor Executor for Core Data (CoreDataStore)

Wrap a persistent container in an actor to serialize all data access. The actor provides the isolation boundary; all context work happens inside `perform`:

```swift
actor CoreDataStore {
    private let container: NSPersistentContainer

    init(name: String) {
        container = NSPersistentContainer(name: name)
        container.loadPersistentStores { _, error in
            if let error { fatalError("Store load failed: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Read on a background context, project to Sendable values.
    func fetch<T: Sendable>(
        _ work: @Sendable @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = container.newBackgroundContext()
        return try await context.perform { try work(context) }
    }

    /// Write on a background context.
    func write(
        _ work: @Sendable @escaping (NSManagedObjectContext) throws -> Void
    ) async throws {
        let context = container.newBackgroundContext()
        try await context.perform {
            try work(context)
            if context.hasChanges { try context.save() }
        }
    }
}
```

Usage:

```swift
let store = CoreDataStore(name: "Model")

let users = try await store.fetch { context in
    let request = User.fetchRequest()
    return try context.fetch(request).map(\.dao)
}

try await store.write { context in
    let user = User(context: context)
    user.name = "Ada"
}
```

## Background Context Creation

Two approaches, different lifetimes:

### newBackgroundContext()

Creates a reusable private-queue context tied to the persistent store coordinator. Suitable when you need a long-lived background context (e.g. a sync engine that runs multiple operations).

```swift
let bgContext = container.newBackgroundContext()
bgContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

// Use repeatedly
try await bgContext.perform {
    // fetch, mutate, save
}
```

### performBackgroundTask

Creates a throwaway private-queue context, executes the block, and discards the context. Suitable for one-shot operations.

```swift
container.performBackgroundTask { context in
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    let request = User.fetchRequest()
    let users = try? context.fetch(request)
    // ... mutate ...
    try? context.save()
    // context is discarded after this block
}
```

**Async variant (iOS 15+):**

```swift
try await container.performBackgroundTask { context in
    // async-safe, runs on private queue
    let users = try context.fetch(User.fetchRequest())
    // ...
    try context.save()
}
```

### Which to use

| Scenario | Use |
|---|---|
| One-shot import or sync | `performBackgroundTask` |
| Repeated operations on same context | `newBackgroundContext()` |
| Actor-wrapped store | `newBackgroundContext()` inside the actor |
| SwiftUI write from a button tap | `performBackgroundTask` |

## Default MainActor Isolation Conflicts

Swift 6.2 with "main actor by default" means new types are implicitly `@MainActor`. Core Data contexts with `privateQueueConcurrencyType` expect their work to run on their own serial queue, not the main actor.

Symptoms:
- Compiler warns that `context.perform { }` crosses isolation boundaries.
- `@MainActor`-isolated closures passed to `perform` deadlock or produce warnings.

Fixes:
- Mark Core Data store/repository types as `nonisolated` or wrap them in a custom actor (see CoreDataStore pattern above).
- Use `@Sendable` closures with `perform` and project results to Sendable types before returning.
- Do not annotate Core Data helper classes with `@MainActor` unless they exclusively use the view context.

```swift
// Mark explicitly nonisolated to opt out of main-actor default
nonisolated final class UserRepository {
    private let container: NSPersistentContainer

    func fetchAll() async throws -> [UserDAO] {
        let context = container.newBackgroundContext()
        return try await context.perform {
            try context.fetch(User.fetchRequest()).map(\.dao)
        }
    }
}
```

## Batch Operations

Batch operations bypass the managed object context, executing directly against the persistent store. They do not trigger validation, change tracking, or merge notifications by default.

### NSBatchInsertRequest (iOS 13+)

Insert thousands of rows without loading them into memory:

```swift
try await bgContext.perform {
    let request = NSBatchInsertRequest(
        entity: User.entity(),
        managedObjectHandler: { object in
            guard let user = object as? User else { return true }
            // Return true to stop, false to continue
            user.name = nextRecord.name
            user.email = nextRecord.email
            return false
        }
    )
    request.resultType = .count
    let result = try bgContext.execute(request) as? NSBatchInsertResult
    print("Inserted \(result?.result as? Int ?? 0) rows")
}
```

Or with dictionaries (no managed object overhead):

```swift
let dictionaries: [[String: Any]] = records.map {
    ["name": $0.name, "email": $0.email, "createdAt": Date()]
}
let request = NSBatchInsertRequest(entityName: "User", objects: dictionaries)
request.resultType = .objectIDs
let result = try bgContext.execute(request) as? NSBatchInsertResult
```

### NSBatchUpdateRequest

Update rows without fetching:

```swift
let request = NSBatchUpdateRequest(entityName: "User")
request.predicate = NSPredicate(format: "lastLoginDate < %@", cutoffDate as NSDate)
request.propertiesToUpdate = ["isActive": false]
request.resultType = .updatedObjectIDsResultType
let result = try bgContext.execute(request) as? NSBatchUpdateResult
```

### NSBatchDeleteRequest

Delete rows without fetching:

```swift
let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "LogEntry")
fetchRequest.predicate = NSPredicate(format: "timestamp < %@", expiryDate as NSDate)
let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
deleteRequest.resultType = .resultTypeObjectIDs
let result = try bgContext.execute(deleteRequest) as? NSBatchDeleteResult
```

### Merging Batch Changes into Contexts

Batch operations bypass the context, so in-memory objects become stale. Merge the changes manually:

```swift
if let objectIDs = result?.result as? [NSManagedObjectID] {
    let changes: [AnyHashable: Any] = [
        NSDeletedObjectIDsKey: objectIDs  // or NSUpdatedObjectIDsKey / NSInsertedObjectIDsKey
    ]
    NSManagedObjectContext.mergeChanges(
        fromRemoteContextSave: changes,
        into: [container.viewContext]
    )
}
```

Without this step, `@FetchRequest` and `NSFetchedResultsController` will not reflect batch changes until the next fetch.

## Async/Await with perform (iOS 15+)

The async `perform` overload lets you use structured concurrency with Core Data:

```swift
let users = try await context.perform {
    try context.fetch(User.fetchRequest())
}
```

The closure runs on the context's queue. The result is returned to the caller's isolation domain. If the result type is not `Sendable`, the compiler will warn under strict concurrency -- project to DAOs first.

## Prefetching Relationships to Avoid N+1

```swift
let request = User.fetchRequest()
request.relationshipKeyPathsForPrefetching = ["posts", "comments"]
request.fetchBatchSize = 50

let users = try context.fetch(request)
for user in users {
    // posts and comments already in memory -- no extra SQL
    print(user.posts?.count ?? 0)
}
```

Without prefetching, accessing `user.posts` inside the loop fires a separate SQL query per user (N+1 pattern).

## Context Hierarchy vs Peer Contexts

### Peer contexts (recommended)

Both the view context and background contexts connect to the same persistent store coordinator. Changes saved to one context merge into the other via `automaticallyMergesChangesFromParent`.

```
NSPersistentContainer
    +-- viewContext (main queue)
    +-- newBackgroundContext() (private queue)
    +-- newBackgroundContext() (private queue)
```

### Parent-child contexts (use sparingly)

A child context pushes unsaved changes to its parent on save, not to the store. Useful for "scratch pad" editing that can be discarded:

```swift
let childContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
childContext.parent = container.viewContext

// Edit in child
// Save child -> pushes to parent (viewContext)
// Save parent -> pushes to store
```

Downsides: two saves needed to persist, temporary IDs until the parent saves, and more complex error handling.
