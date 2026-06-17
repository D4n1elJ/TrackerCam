# GRDB

Write, review, and govern GRDB code for correctness, performance, concurrency safety, and migration integrity. Report only genuine problems — do not nitpick or invent issues.

## Responsibility

**Owns:**

- Record protocol conformances (FetchableRecord, PersistableRecord, MutablePersistableRecord, TableRecord)
- Query Interface — filtering, sorting, aggregation, CTEs, subqueries
- Associations — BelongsTo, HasOne, HasMany, HasManyThrough, eager loading, association aggregates
- DatabaseMigrator — forward-only migrations, table creation/alteration/recreation, FK handling
- ValueObservation — tracking, scheduling, async sequences, shared observations
- Concurrency — DatabaseQueue vs DatabasePool, read/write blocks, WAL mode, non-reentrancy
- SQL interpolation and injection prevention
- JSON columns and Codable encoding
- Full-text search (FTS3/4/5)
- Transaction and savepoint management

**Does NOT own:**

- UI binding in SwiftUI views (SwiftUI skill)
- Background threading and actor design beyond database access (Swift Concurrency skill)
- SwiftData or Core Data (separate skills)
- Network sync or CloudKit integration

## Core Principles

1. **One connection per database file.** Open a single DatabaseQueue or DatabasePool and keep it alive for the app's lifetime. Multiple connections cause SQLITE_BUSY errors and break observation.
2. **Mind your transactions.** Group related operations in write blocks. Partial writes corrupt user data.
3. **Migrations are forward-only and immutable.** Never modify a shipped migration. Add new ones.
4. **Use string literals in migrations, not Swift types.** Migrations describe past schemas — coupling them to current code breaks when code evolves.
5. **Schema is king.** The SQLite database on a user's device is more important than the Swift code. Define robust constraints in the schema.
6. **Data fetched is immediately stale.** Values from read/write blocks are snapshots. Use ValueObservation for live UI updates.
7. **Non-reentrancy is enforced.** Nesting `dbQueue.write` inside `dbQueue.write` is a fatal error. Structure code to avoid this.

## Review Process

1. Check record types and conformances using `references/records-and-queries.md`.
2. Check association correctness using `references/associations.md`.
3. For any migration work, check patterns and constraints using `references/migrations.md`.
4. For observation or reactive UI, check patterns using `references/observation.md`.
5. For concurrency or threading concerns, check rules using `references/concurrency.md`.
6. For full-text search, check setup and patterns using `references/fts.md`.
7. For query performance, batch operations, or indexing, check `references/performance.md`.

If doing partial work, load only the relevant reference files.

## Quick Reference: Record Protocol Hierarchy

```
TableRecord          — maps type to table name
FetchableRecord      — decodes rows (read)
EncodableRecord      — encodes for persistence (write)
MutablePersistableRecord = TableRecord + EncodableRecord + didInsert callback (mutating)
PersistableRecord    = MutablePersistableRecord (non-mutating didInsert)
```

**Recommended pattern** — Codable struct with PersistableRecord:

```swift
struct Player: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64
    var name: String
    var score: Int
}
```

Use `MutablePersistableRecord` only when you need auto-incremented ID population:

```swift
struct Player: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

## Quick Reference: Column References

```swift
// Preferred: CodingKeys-based (type-safe, refactor-friendly)
extension Player {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let score = Column(CodingKeys.score)
    }
}

// Usage in queries
Player.filter(Player.Columns.score > 500)
Player.order(Player.Columns.name)
```

## Quick Reference: Read/Write Blocks

```swift
// Read (wrapped in transaction, stable snapshot)
let players = try dbQueue.read { db in
    try Player.fetchAll(db)
}

// Write (wrapped in transaction, serialized)
let count = try dbQueue.write { db in
    try Player(name: "Arthur").insert(db)
    return try Player.fetchCount(db)
}

// Async variants
let players = try await dbQueue.read { db in try Player.fetchAll(db) }
let count = try await dbQueue.write { db in
    try Player(name: "Arthur").insert(db)
    return try Player.fetchCount(db)
}
```

## Quick Reference: ValueObservation

```swift
// Create observation
let observation = ValueObservation.tracking { db in
    try Player.fetchAll(db)
}

// Async sequence (preferred for modern Swift)
for try await players in observation.values(in: dbQueue) {
    updateUI(with: players)
}

// Callback-based (stores cancellable)
let cancellable = observation.start(in: dbQueue) { error in
    handle(error)
} onChange: { (players: [Player]) in
    updateUI(with: players)
}
```

## Codable + GRDB Interaction

GRDB records use Codable for automatic column mapping. This creates interactions worth knowing:

**CodingKeys control column names.** If your record has `CodingKeys`, GRDB uses those keys as column names — not the Swift property names. This applies to both reading and writing.

```swift
struct Player: Codable, FetchableRecord, PersistableRecord {
    var id: Int64
    var fullName: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"  // column is "full_name", not "fullName"
    }
}
```

**Prefer `databaseColumnDecodingStrategy` over CodingKeys for snake_case.** If all columns follow snake_case convention, use the strategy instead of writing CodingKeys for every type.

**JSON columns vs Codable conformance.** Any non-primitive Codable property is stored as JSON text automatically. This means:
- Adding `Codable` to a type that's used as a property makes it a JSON column
- Changing a property from a primitive to a Codable struct changes the column type
- Both are schema changes that require migrations

**Export/import pattern.** When a GRDB record also needs JSON serialization for export:

```swift
struct Player: Codable, FetchableRecord, PersistableRecord {
    var id: Int64
    var name: String
    var score: Int
}

// Same Codable conformance works for both GRDB and JSON export
let jsonData = try JSONEncoder().encode(player)
```

**Caveat:** If the GRDB column names differ from your desired JSON keys (e.g., snake_case columns but camelCase JSON), you need separate CodingKeys or a DTO layer. GRDB and JSONEncoder share the same `encode(to:)`.

**Custom JSON coders for embedded objects.** Override `databaseJSONDecoder(for:)` / `databaseJSONEncoder(for:)` when JSON columns need different date strategies or key strategies than your external API.

## Common Pitfalls

1. **Multiple database connections** — opening more than one DatabaseQueue/Pool for the same file causes SQLITE_BUSY and breaks observation.
2. **Reentrant access** — calling `dbQueue.write` inside a `dbQueue.write` closure is a fatal error. Pass the `db` handle through instead.
3. **Cursors escaping scope** — cursors from `fetchCursor` cannot leave the database access closure. Use `fetchAll` if you need results outside.
4. **Row nil-coalescing** — `row["a"] ?? row["b"]` does not work as expected. The `??` operator resolves against the Optional wrapper, not the column value.
5. **Referencing Swift types in migrations** — using `Author.databaseTableName` or `CodingKeys` in migrations couples them to current code. Use string literals.
6. **Floating-point money** — never use Double for currency. Store integer cents, convert to Decimal in Swift.
7. **Identifiable with optional auto-increment IDs** — `id: Int64?` breaks Identifiable's contract. Either use a non-optional ID or don't conform to Identifiable until after insert.
8. **Missing `removeDuplicates()`** — ValueObservation may emit duplicate values. Add `.removeDuplicates()` when equality checks are cheap.
9. **Forgetting initial value** — ValueObservation always delivers an initial value before any change notification. Design your handler accordingly.
10. **Association key mismatch** — when decoding with associations, the Decodable property name must match the association key (defaults to table name, singularised/pluralised as appropriate).
11. **Missing indexes on filtered/sorted columns** — queries on columns without indexes cause full table scans. See `references/performance.md` for EXPLAIN QUERY PLAN, indexing strategies, and batch write patterns.

## Migration Decision Quick Reference

A new migration is required whenever:

1. Adding or removing a table
2. Adding, removing, renaming, or retyping a column
3. Changing primary key, uniqueness, or foreign key constraints
4. Changing NOT NULL constraints on existing columns (requires table recreation)
5. Changing default values on existing columns (requires table recreation)
6. Adding or removing indexes

**Simple alterations** (SQLite ALTER TABLE supports):
- Adding a column
- Renaming a column (SQLite 3.25.0+)
- Dropping a column (SQLite 3.35.0+)
- Renaming a table

**Everything else requires table recreation** — create new table, copy data, drop old, rename new.

## Output Format

If the user asks for a review, organise findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritised summary.

If the user asks you to write or improve code, follow the same rules above but make the changes directly.
