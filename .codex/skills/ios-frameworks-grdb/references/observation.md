# Database Observation

## ValueObservation

The primary tool for keeping UI in sync with the database. Tracks changes to a database region and re-fetches when that region is modified.

### Creating

```swift
// Auto-detect region from fetch closure (most common)
let observation = ValueObservation.tracking { db in
    try Player.fetchAll(db)
}

// Explicit region (when fetch differs from tracked tables)
let observation = ValueObservation.tracking(
    region: Player.all()
) { db in
    try computeExpensiveStats(db)
}

// Constant region optimisation (region never changes)
let observation = ValueObservation.trackingConstantRegion { db in
    try Player.filter(id: 42).fetchOne(db)
}
```

### Consuming: Async Sequence (Preferred)

```swift
let observation = ValueObservation.tracking { db in
    try Player.fetchAll(db)
}

// In a Task or async context
for try await players in observation.values(in: dbQueue) {
    updateUI(with: players)
}
```

Task cancellation is respected — the observation stops when the task is cancelled.

### Consuming: Callback-Based

```swift
// MainActor delivery (default)
let cancellable = observation.start(in: dbQueue) { error in
    handleError(error)
} onChange: { (players: [Player]) in
    self.players = players
}
// Store cancellable — observation stops on deallocation
```

### Consuming: Combine Publisher

```swift
let publisher = observation.publisher(in: dbQueue)
    .receive(on: DispatchQueue.main)
    .sink(
        receiveCompletion: { _ in },
        receiveValue: { players in self.players = players }
    )
```

### Transforms

```swift
// Map — transforms off main thread, reducing contention
let observation = ValueObservation
    .tracking { db in try Player.fetchOne(db, id: 42) }
    .map { player in player?.displayName }

// Remove duplicates — suppress consecutive identical values
let observation = ValueObservation
    .tracking { db in try Player.fetchCount(db) }
    .removeDuplicates()

// Custom duplicate predicate
let observation = ValueObservation
    .tracking { db in try Player.fetchAll(db) }
    .removeDuplicates(by: { $0.map(\.id) == $1.map(\.id) })
```

### Scheduling

| Scheduler | Initial Value | Subsequent Values | Use When |
|---|---|---|---|
| `.mainActor` (default) | Async on main | Async on main | UI updates |
| `.immediate` | Synchronous on main | Async on main | Need initial value before returning |
| `.async(onQueue:)` | Async on queue | Async on queue | Background processing |
| `.task` | Cooperative pool | Cooperative pool | Async sequences (default) |

### Debugging

```swift
observation.handleEvents(
    willStart: { },
    willFetch: { },
    willTrackRegion: { region in print("Tracking: \(region)") },
    databaseDidChange: { },
    didReceiveValue: { value in print("Got: \(value)") },
    didFail: { error in print("Error: \(error)") },
    didCancel: { })

// Or simple print logging
observation.print("PlayerObservation")
```

## SharedValueObservation

Shares a single database observation across multiple subscribers. Reduces resource usage when multiple views or components need the same data.

```swift
let shared = ValueObservation
    .tracking { db in try Player.fetchAll(db) }
    .shared(in: dbQueue)

// Multiple subscribers, single database observation
let cancellable1 = shared.start { error in } onChange: { players in ... }
let cancellable2 = shared.start { error in } onChange: { players in ... }

// Async sequence
for try await players in shared.values() { ... }

// Combine publisher
let publisher = shared.publisher()
```

### Extent

- `.whileObserved` (default) — stops when all subscribers disconnect; restarts on next subscription
- `.observationLifetime` — runs until the SharedValueObservation is deallocated

## DatabaseRegionObservation

Low-level: notifies immediately after a commit that modifies a tracked region. The notification fires **before any other thread can write**, giving you a consistent view.

```swift
let observation = DatabaseRegionObservation(tracking: Player.all())

let cancellable = try observation.start(in: dbQueue) { error in
    handleError(error)
} onChange: { (db: Database) in
    // You receive the Database connection
    // Read fresh data here if needed
    let count = try Player.fetchCount(db)
    print("Players changed, count: \(count)")
}
```

Use ValueObservation instead unless you specifically need the "before anyone else writes" guarantee.

### Limitations

Cannot detect:
- Changes from external database connections
- Non-GRDB SQLite statements
- Schema modifications
- Changes to WITHOUT ROWID tables

Workaround: `try db.notifyChanges(in: .fullDatabase)` for manual notification.

## TransactionObserver (Protocol)

Foundation of all observation. Implement this protocol for fine-grained control over individual row changes, pre-commit validation, and post-commit/rollback hooks.

```swift
class MyObserver: TransactionObserver {
    // Pre-filter: only care about player table changes
    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool {
        eventKind.tableName == "player"
    }

    // Called for each row change (insert/update/delete)
    func databaseDidChange(with event: DatabaseEvent) {
        // event.tableName, event.kind (.insert/.update/.delete), event.rowID
    }

    // Can prevent commits by throwing
    func databaseWillCommit() throws {
        // Validate invariants before commit
    }

    // After successful commit
    func databaseDidCommit(_ db: Database) {
        // Notify, schedule work, etc.
    }

    // After rollback
    func databaseDidRollback(_ db: Database) {
        // Clean up
    }
}

// Register
db.add(transactionObserver: observer)
db.add(transactionObserver: observer, extent: .databaseLifetime)
```

### Observation Extents

- `.observerLifetime` (default) — weak reference, ends on deallocation
- `.nextTransaction` — strong reference until next transaction completes
- `.databaseLifetime` — retained until database connection closes

### Manual Notification

For changes GRDB cannot detect automatically:

```swift
try db.notifyChanges(in: .fullDatabase)
try db.notifyChanges(in: Player.all())
try db.notifyChanges(in: Table("sqlite_master"))
```

## Patterns for SwiftUI

### Observable Class with ValueObservation

```swift
@Observable
final class PlayerListModel {
    var players: [Player] = []
    private var cancellable: AnyDatabaseCancellable?

    func startObserving(in database: some DatabaseReader) {
        cancellable = ValueObservation
            .tracking { db in try Player.order(Column("name")).fetchAll(db) }
            .start(in: database) { [weak self] error in
                // handle error
            } onChange: { [weak self] players in
                self?.players = players
            }
    }
}
```

### Observable Class with Async Sequence

```swift
@Observable
final class PlayerListModel {
    var players: [Player] = []
    private var observationTask: Task<Void, Never>?

    func startObserving(in database: some DatabaseReader) {
        observationTask = Task { [weak self] in
            let observation = ValueObservation.tracking { db in
                try Player.order(Column("name")).fetchAll(db)
            }
            do {
                for try await players in observation.values(in: database) {
                    self?.players = players
                }
            } catch {
                // handle error
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }
}
```

### UIKit with Callback

```swift
class PlayerListViewController: UIViewController {
    private var cancellable: AnyDatabaseCancellable?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cancellable = ValueObservation
            .tracking { db in try Player.fetchAll(db) }
            .start(in: database) { [weak self] error in
                // handle
            } onChange: { [weak self] players in
                self?.updateSnapshot(with: players)
            }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellable = nil  // stop observing
    }
}
```

## Performance for Large Datasets

- **`removeDuplicates()`** — suppresses redundant UI updates when the observed value has not actually changed. Essential for high-frequency write scenarios to avoid unnecessary SwiftUI re-renders.
- **`.scheduling(.async(onQueue:))`** — offloads heavy observation fetch work to a background queue, preventing main-thread blocking. Use when the fetch closure does expensive computation or processes large result sets.

```swift
let observation = ValueObservation
    .tracking { db in try Player.fetchAll(db) }
    .removeDuplicates()

// Heavy observation on background queue
let cancellable = observation
    .start(in: dbPool, scheduling: .async(onQueue: .global())) { error in
        handleError(error)
    } onChange: { players in
        DispatchQueue.main.async { updateUI(with: players) }
    }
```

## Pitfalls

- **Initial value is always delivered.** Design handlers to expect an initial fetch before any change notifications.
- **Duplicate values are possible.** Use `.removeDuplicates()` when equality is cheap to check.
- **Consecutive changes may be consolidated.** You may not receive every intermediate state — only the latest value after a batch of writes.
- **Store the cancellable.** If the `AnyDatabaseCancellable` is deallocated, the observation stops immediately.
- **Don't observe too many things.** Each ValueObservation has overhead. Consolidate related observations into a single one that returns a struct of all needed data.
- **Heavy observations block the main thread.** Use `.scheduling(.async(onQueue:))` for observations with expensive fetch closures to avoid UI jank.
- **`requiresWriteAccess`** is rarely needed. Only set to `true` if the observation's fetch closure must write (e.g., materialising a cache).
