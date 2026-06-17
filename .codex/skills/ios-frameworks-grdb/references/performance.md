# Performance

## EXPLAIN QUERY PLAN

Check whether queries use indexes or fall back to full table scans:

```swift
try dbQueue.read { db in
    let plan = try String.fetchAll(db, sql: """
        EXPLAIN QUERY PLAN SELECT * FROM player WHERE score > 500
        """)
    for line in plan { print(line) }
}
```

Key terms in output:
- **SEARCH** — uses an index (good)
- **SCAN** — full table scan (check if an index is needed)

Run this during development for any query on tables with more than a few hundred rows.

## SQL Statement Logging

```swift
#if DEBUG
dbQueue.trace { print("SQL: \($0)") }
#endif
```

Enables logging of every executed SQL statement. Use during development to spot N+1 queries and unexpected queries.

## Index Strategies

### When to Index

| Scenario | Example |
|---|---|
| WHERE clause filtering | `WHERE artist = ?` |
| JOIN columns | `ON tracks.albumId = albums.id` |
| ORDER BY on large tables | `ORDER BY createdAt DESC` |
| Foreign keys | `authorId`, `teamId` |

### When NOT to Index

- Boolean or low-cardinality columns (few distinct values)
- Small tables (<1000 rows) — scan is fast enough
- Columns only used in INSERT, never in queries

### Compound Indexes

Column order matters. A compound index on `(genre, artist)` supports:
- `WHERE genre = ?` (uses first column)
- `WHERE genre = ? AND artist = ?` (uses both)
- Does NOT support `WHERE artist = ?` alone (skips first column)

```swift
try db.create(indexOn: "tracks", columns: ["genre", "artist"])
```

## Batch Write Operations

### Wrong: Many Transactions

```swift
// Each iteration opens and commits a separate transaction — slow
for player in players {
    try dbQueue.write { db in try player.insert(db) }
}
```

### Right: Single Transaction

```swift
// One transaction for all inserts — much faster
try dbQueue.write { db in
    for player in players { try player.insert(db) }
}
```

### Prepared Statements for Bulk Inserts

Pre-compile the SQL once, execute many times. Faster than repeated `insert(db)` for large batches because it avoids re-encoding through Codable for each row:

```swift
try dbQueue.write { db in
    let stmt = try db.makeStatement(sql: """
        INSERT INTO player (id, name, score) VALUES (?, ?, ?)
        """)
    for player in players {
        try stmt.execute(arguments: [player.id, player.name, player.score])
    }
}
```

Use prepared statements when inserting 1000+ rows. For smaller batches, `insert(db)` is fine.

### Cached Statements for Hot-Path Queries

Avoid repeated SQL parsing for queries called frequently:

```swift
let stmt = try db.cachedStatement(sql: "SELECT * FROM player WHERE teamId = ?")
```

`cachedStatement` reuses the compiled statement across calls within the same database access block.

## N+1 Query Detection

### Wrong: Fetch-Then-Loop

```swift
let authors = try Author.fetchAll(db)
for author in authors {
    let books = try Book.filter(Column("authorId") == author.id).fetchAll(db)  // N queries
}
```

### Right: Use Associations or JOIN

```swift
// Association-based (preferred)
let authorInfos = try Author
    .including(all: Author.books)
    .asRequest(of: AuthorInfo.self)
    .fetchAll(db)

// Raw JOIN when needed
let sql = """
    SELECT author.*, book.title as bookTitle
    FROM author JOIN book ON book.authorId = author.id
    """
```

## Large Dataset Streaming

Load rows one at a time instead of all into memory:

```swift
try dbQueue.read { db in
    let cursor = try Player.fetchCursor(db)
    while let player = try cursor.next() {
        process(player)
    }
}
```

Cursors cannot escape the database access closure. Use `fetchAll` if you need results outside.

## Main Thread Safety

### Wrong: Blocking the Main Thread

```swift
// Synchronous read blocks UI until query completes
let players = try dbQueue.read { db in try Player.fetchAll(db) }
```

### Right: Async Access

```swift
let players = try await dbQueue.read { db in try Player.fetchAll(db) }
```

For heavy observation fetches, use `.scheduling(.async(onQueue:))` to offload work. See `observation.md` for details.

## Profiling Checklist

1. Enable `trace` logging in DEBUG builds
2. Run `EXPLAIN QUERY PLAN` on queries touching large tables
3. Look for SCAN — add indexes where needed
4. Wrap batch writes in a single transaction
5. Check for N+1 patterns (fetch-then-loop)
6. Use `await` for database access from the main thread
7. Stream large results with `fetchCursor` instead of `fetchAll`

## Pitfalls

- **Over-indexing** adds write overhead. Every INSERT/UPDATE/DELETE must update all indexes on the table. Only index columns that appear in queries.
- **Index on expression vs column** — an index on `Column("name")` does not help `WHERE LOWER(name) = ?`. Index the expression if needed: `try db.create(indexOn: "player", expressions: [Column("name").collating(.nocase)])`.
- **Prepared statement scope** — `makeStatement` returns a statement tied to the current `Database` handle. Do not store it beyond the access closure.
- **Transaction size** — extremely large single transactions (100k+ rows) hold a write lock for the entire duration. For massive imports, consider chunked transactions (e.g., 5000 rows per transaction).
