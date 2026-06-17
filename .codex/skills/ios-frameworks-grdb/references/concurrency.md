# Concurrency

## The Two Rules

### Rule 1: One Connection Per Database File

Open a single `DatabaseQueue` or `DatabasePool` for the entire lifetime of the app. Share it everywhere via dependency injection.

**Violations cause:**
- `SQLITE_BUSY` (5) errors
- Broken database observation (ValueObservation misses changes)
- Potential data corruption with concurrent writers

### Rule 2: Mind Your Transactions

Group related operations inside `read` or `write` blocks. Each block runs in a single transaction, ensuring atomicity and isolation.

## DatabaseQueue vs DatabasePool

| Feature | DatabaseQueue | DatabasePool |
|---|---|---|
| Connections | Single | One writer + reader pool |
| Concurrent reads | No — serialised | Yes (WAL mode) |
| In-memory databases | Yes | No |
| Setup | `DatabaseQueue(path:)` | `DatabasePool(path:)` |
| API surface | Identical | Identical |

**Choose DatabasePool** for production apps with concurrent read/write needs (most apps).
**Choose DatabaseQueue** for testing, in-memory databases, or simple single-threaded use.

Both conform to `DatabaseWriter` (and `DatabaseReader`), so code can be generic:

```swift
func setup(database: some DatabaseWriter) { ... }
```

## Read/Write Blocks

### Read

```swift
// Synchronous — blocks calling thread
let count = try dbPool.read { db in
    try Player.fetchCount(db)
}

// Async — suspends, never blocks
let count = try await dbPool.read { db in
    try Player.fetchCount(db)
}
```

Guarantees:
- Wrapped in a DEFERRED transaction
- Stable, immutable snapshot for the duration
- Writes inside a read closure throw an error

### Write

```swift
// Synchronous
try dbPool.write { db in
    try Player(name: "Arthur").insert(db)
}

// Async
try await dbPool.write { db in
    try Player(name: "Arthur").insert(db)
}
```

Guarantees:
- Wrapped in an IMMEDIATE transaction
- Serialised — no concurrent writes
- Automatic rollback on thrown error
- Automatic commit on success

### Write Without Transaction

```swift
try dbPool.writeWithoutTransaction { db in
    // Manual transaction control
    try db.beginTransaction()
    try doWork(db)
    try db.commit()
}
```

Use when you need savepoints, multiple transactions, or concurrent reads mid-write (DatabasePool only).

### Barrier Write

```swift
try dbPool.barrierWriteWithoutTransaction { db in
    // All pending reads complete before this executes
    // No new reads start until this finishes
}
```

Use for operations that must see/modify the entire database state without concurrent readers.

## Non-Reentrancy

**Nesting database access is a fatal error:**

```swift
// FATAL ERROR — deadlock
try dbQueue.write { db in
    try dbQueue.write { db in  // crashes here
        ...
    }
}
```

**Fix:** Pass the `db: Database` handle through function calls instead of re-entering the queue:

```swift
// Wrong
func updateScore(for playerId: Int64) throws {
    try dbQueue.write { db in
        let player = try Player.fetchOne(db, id: playerId)
        try recalculate(playerId: playerId)  // if this calls dbQueue.write → crash
    }
}

// Right
func updateScore(for playerId: Int64) throws {
    try dbQueue.write { db in
        let player = try Player.fetchOne(db, id: playerId)
        try recalculate(db: db, playerId: playerId)  // pass db through
    }
}
```

## Unsafe Access

```swift
// No transaction guarantee — may see partial writes
try dbPool.unsafeRead { db in ... }

// No serialisation — concurrent writes possible
try dbPool.unsafeReentrantRead { db in ... }
try dbPool.unsafeReentrantWrite { db in ... }
```

Unsafe methods exist for rare edge cases (debugging, legacy interop). Avoid in production code.

## Task Cancellation

Async access methods honour Swift concurrency task cancellation:

```swift
let task = Task {
    try await dbPool.write { db in
        for player in players {
            try player.insert(db)  // may throw CancellationError
        }
    }
}
task.cancel()  // transaction will roll back
```

## Stale Data

Any value extracted from a `read` or `write` block is immediately stale:

```swift
let count = try dbPool.read { db in try Player.fetchCount(db) }
// count is already stale — another write may have changed it
```

For live UI updates, use `ValueObservation` instead of polling reads.

## DatabaseSnapshot

A frozen, read-only view of the database at a point in time:

```swift
let snapshot = try dbPool.makeSnapshot()
let count = try snapshot.read { db in try Player.fetchCount(db) }
// Always returns the same count, regardless of later writes
```

Use for long-running read operations that must see a consistent state without blocking writers.

## Swift Concurrency Integration

### Sendable

- `DatabaseQueue` and `DatabasePool` are `Sendable`.
- Record structs composed of `Sendable` properties are naturally `Sendable`.
- Record classes need `@unchecked Sendable` with manual thread-safety verification.

### Common Swift 6 Issues

**1. Shorthand closure warnings.** Enable `InferSendableFromCaptures`:
- Xcode: `SWIFT_UPCOMING_FEATURE_INFER_SENDABLE_FROM_CAPTURES = YES`
- SwiftPM: `.enableUpcomingFeature("InferSendableFromCaptures")`

**2. Non-Sendable static properties.** Convert stored to computed:

```swift
// Triggers Sendable warning
static let databaseSelection: [any SQLSelectable] = [Column("id"), Column("name")]

// Fix
static var databaseSelection: [any SQLSelectable] {
    [Column("id"), Column("name")]
}
```

**3. Prefer structs over classes for records.** Structs are automatically Sendable when all properties are Sendable. Classes require explicit annotation and thread-safety audit.

## Concurrent Read During Write (DatabasePool)

DatabasePool supports concurrent reads while a write is in progress:

```swift
try dbPool.writeWithoutTransaction { db in
    try db.inTransaction {
        try Player(name: "New").insert(db)
        return .commit
    }

    // After commit, fire off a concurrent read
    dbPool.asyncConcurrentRead { dbResult in
        let db = try dbResult.get()
        let count = try Player.fetchCount(db)
        // This sees the committed write
    }
}
```

## Performance Profiling

See `references/performance.md` for EXPLAIN QUERY PLAN, SQL tracing, batch operations, indexing strategies, N+1 detection, and prepared statements.

## Pitfalls

- **Multiple connections** to the same file — the most common GRDB bug. Audit your app for accidental double-opens.
- **Reentrancy crashes** — pass `db` through function signatures instead of re-entering the queue.
- **Long-running writes block reads** (DatabaseQueue) — move to DatabasePool if read latency matters.
- **Stale data in UI** — never cache a read result and assume it's current. Use ValueObservation.
- **Sync access on main thread** — `dbQueue.read` on the main thread blocks UI. Use `await dbQueue.read` or move to background.
- **Forgetting to store cancellables** — observation stops immediately when the cancellable is deallocated.
- **Protected data on locked device** — iOS throws `SQLITE_IOERR` (10) or `SQLITE_AUTH` (23) when accessing a protected database on a locked device. Handle this in your error path.
