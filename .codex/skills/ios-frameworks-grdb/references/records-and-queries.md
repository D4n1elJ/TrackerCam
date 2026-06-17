# Records and Queries

## Record Protocols

| Protocol | Purpose | Use When |
|---|---|---|
| `FetchableRecord` | Decode rows into Swift types | Read-only types, custom decoding |
| `TableRecord` | Map type to table name | Any type that represents a table |
| `EncodableRecord` | Encode for persistence | Custom encoding without full persistence |
| `PersistableRecord` | Insert/update/delete (non-mutating) | Records with pre-assigned IDs (UUID, etc.) |
| `MutablePersistableRecord` | Insert/update/delete with `didInsert` callback | Records with auto-incremented IDs |

Codable gives automatic FetchableRecord + EncodableRecord conformance. You only need to declare the protocol — no manual `init(row:)` or `encode(to:)`.

## Custom Table Name

```swift
struct User: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "application_user"
    // ...
}
```

Default: lowercased, pluralised type name. Override when the table name differs.

## DatabaseValueConvertible for Enums

```swift
enum Colour: String, Codable, DatabaseValueConvertible {
    case red, white, rose
}
```

Any `RawRepresentable` enum whose `RawValue` is already `DatabaseValueConvertible` gets automatic conformance.

## Fetching

| Method | Returns | Notes |
|---|---|---|
| `fetchOne(db)` | `T?` | Single optional |
| `fetchAll(db)` | `[T]` | Array, all in memory |
| `fetchSet(db)` | `Set<T>` | Deduplicated |
| `fetchCursor(db)` | `Cursor<T>` | Lazy, memory-efficient. **Must be consumed within the database access closure.** |
| `fetchCount(db)` | `Int` | COUNT without fetching rows |

### Fetch by Primary Key

```swift
let player = try Player.fetchOne(db, id: 42)
let players = try Player.fetchAll(db, ids: [1, 2, 3])
let exists = try Player.exists(db, id: 42)
```

## Persistence Operations

### Insert

```swift
try player.insert(db)

// Auto-increment with MutablePersistableRecord
var player = Player(id: nil, name: "Bob", score: 600)
try player.insert(db)  // player.id is now populated via didInsert

// Insert and fetch (RETURNING clause, SQLite 3.35.0+)
let full = try player.insertAndFetch(db, as: Player.self)
```

### Update

```swift
try player.update(db)
try player.update(db, columns: ["score"])  // specific columns only

// Change detection — only issues UPDATE if values differ
try player.updateChanges(db) { $0.score = 1000 }
try player.updateChanges(db, from: originalPlayer)

// Batch update
try Player.filter(Column("team") == "red")
    .updateAll(db, Column("score") += 10)
```

### Delete

```swift
try player.delete(db)
try Player.deleteOne(db, id: 1)
try Player.deleteAll(db, ids: [1, 2, 3])
try Player.filter(Column("score") < 0).deleteAll(db)
```

### Save (Insert or Update)

```swift
try player.save(db)  // inserts if new, updates if exists
```

### Upsert (ON CONFLICT, SQLite 3.35.0+)

```swift
// Simple — insert or replace all columns on conflict
try player.upsert(db)

// Custom conflict resolution
let result = try vocabulary.upsertAndFetch(
    db,
    onConflict: ["word"],
    doUpdate: { excluded in
        [
            Column("count") += 1,
            Column("kind") = excluded["kind"],
            Column("isTainted").noOverwrite  // keep existing value
        ]
    })
```

## Query Interface

### Filtering

```swift
Player.filter(Column("score") > 500)
Player.filter(id: 1)
Player.filter(ids: [1, 2, 3])
Player.filter(sql: "score > ? AND team = ?", arguments: [500, "red"])

// Negation
Player.filter(!Column("isRetired"))
```

### Sorting

```swift
Player.order(Column("score").desc)
Player.order(Column("name").asc, Column("score").desc)
Player.order(sql: "RANDOM()")
```

### Selecting Specific Columns

```swift
Player.select(Column("name"), Column("score"))
Player.select(max(Column("score")))
```

### Aggregates

```swift
let count = try Player.fetchCount(db)
let maxScore = try Player.select(max(Column("score")), as: Int.self).fetchOne(db)
```

### Group By / Having

```swift
let request = Player
    .select(Column("team"), count(distinct: Column("id")))
    .group(Column("team"))
    .having(count(distinct: Column("id")) > 5)
```

### Limit / Offset

```swift
Player.order(Column("score").desc).limit(10)
Player.order(Column("id")).limit(20, offset: 40)
```

## DerivableRequest — Reusable Query Modifiers

Build composable, reusable query scopes:

```swift
extension DerivableRequest<Player> {
    func withHighScore() -> Self {
        filter(Column("score") > 1000)
    }

    func orderedByName() -> Self {
        order(Column("name").collating(.localizedCaseInsensitiveCompare))
    }
}

// Composable
let topPlayers = try Player.all()
    .withHighScore()
    .orderedByName()
    .fetchAll(db)
```

## SQL Interpolation

Type-safe SQL that prevents injection:

```swift
// Safe — uses SQL literal interpolation
let players = try Player.fetchAll(db, sql: """
    SELECT * FROM player WHERE name = \(name) AND score > \(minScore)
    """)

// Typed request
extension Player {
    static func search(_ term: String) -> SQLRequest<Player> {
        "SELECT \(columnsOf: self) FROM \(self) WHERE \(CodingKeys.name) LIKE \('%' + term + '%')"
    }
}
```

### Interpolation Cheat Sheet

| What | Syntax |
|---|---|
| Table name from type | `\(Player.self)` |
| Column from CodingKey | `\(CodingKeys.name)` |
| All columns of type | `\(columnsOf: Player.self)` |
| Value sequence | `WHERE id IN \(ids)` |
| Subquery | `WHERE score = (\(maxScoreRequest))` |
| SQL literal fragment | `\(sql: "COALESCE(a, b)")` |

## JSON Columns

Any non-primitive Codable property is automatically stored as JSON text:

```swift
struct Address: Codable {
    var street: String
    var city: String
}

struct Player: Codable, FetchableRecord, PersistableRecord {
    var id: Int64
    var name: String
    var address: Address  // stored as JSON text column
}
```

**Column type hint:** Use `.jsonText` in table creation to signal intent:

```swift
t.column("address", .jsonText).notNull()
```

**Custom JSON coders:** Override `databaseJSONDecoder(for:)` and `databaseJSONEncoder(for:)` for custom encoding. Use `sortedKeys` on the encoder for stable output.

**Querying JSON fields (iOS 16+):**

```swift
// Index on embedded JSON field
try db.create(index: "player_on_country", on: "player",
    expressions: [JSONColumn("address")["country"]])

// Filter by JSON path
Player.filter(JSONColumn("address")["country"] == "DE")
```

**Caveat:** SQLite compares JSON as strings — whitespace and key order matter for equality.

## Codable Column Name Strategies

```swift
// Default: Swift property names become column names
// Override per-type:
struct Player: Codable, FetchableRecord, PersistableRecord {
    static let databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy = .convertFromSnakeCase
    static let databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy = .convertToSnakeCase
}
```

## Record Comparison

Detect changes between two instances of the same record:

```swift
let oldPlayer = player
player.score = 1000

if player.databaseChanges(from: oldPlayer).isEmpty == false {
    try player.updateChanges(db, from: oldPlayer)
}
```

## Persistence Callbacks

Available on PersistableRecord / MutablePersistableRecord:

- `willSave`, `aroundSave`, `didSave`
- `willInsert`, `aroundInsert`, `didInsert`
- `willUpdate`, `aroundUpdate`, `didUpdate`
- `willDelete`, `aroundDelete`, `didDelete`

Use for timestamps, validation, or audit logging. Do not use for complex side effects — keep callbacks lightweight.

## Record Timestamps

```swift
struct Player: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var createdAt: Date?
    var updatedAt: Date?

    mutating func willInsert(_ db: Database) throws {
        createdAt = createdAt ?? Date()
        updatedAt = Date()
    }

    mutating func willUpdate(_ db: Database) throws {
        updatedAt = Date()
    }
}
```

## Window Functions

Use raw SQL for window functions — the Query Interface does not support them:

```swift
struct RankedPlayer: FetchableRecord {
    var name: String
    var score: Int
    var rank: Int
    var previousScore: Int?

    init(row: Row) {
        name = row["name"]
        score = row["score"]
        rank = row["rank"]
        previousScore = row["previousScore"]
    }
}

let ranked = try dbQueue.read { db in
    try RankedPlayer.fetchAll(db, sql: """
        SELECT name, score,
            ROW_NUMBER() OVER (ORDER BY score DESC) as rank,
            LAG(score) OVER (ORDER BY score DESC) as previousScore
        FROM player
        """)
}
```

### Common Window Functions

| Function | Purpose |
|---|---|
| `ROW_NUMBER()` | Sequential numbering within partition |
| `RANK()` / `DENSE_RANK()` | Ranking with/without gaps for ties |
| `LAG(col)` / `LEAD(col)` | Access previous/next row's value |
| `SUM(col) OVER (...)` | Running total |
| `AVG(col) OVER (...)` | Moving average |

### Partitioned Windows

```swift
// Rank players within each team
let sql = """
    SELECT name, team, score,
        RANK() OVER (PARTITION BY team ORDER BY score DESC) as teamRank
    FROM player
    """
```

## Pitfalls

- **Cursor scope:** `fetchCursor` results are lazy and tied to the database connection. They cannot escape the `read`/`write` closure. Use `fetchAll` or `fetchSet` if you need results outside.
- **Row access:** Use `row[0] as Int?` not `row[0] as? Int`. The `as?` form does not work correctly with database values.
- **Nil coalescing rows:** `row["a"] ?? row["b"]` resolves against Optional, not the column. Use SQL `COALESCE` instead.
- **Identifiable + optional ID:** A record with `var id: Int64?` should not conform to `Identifiable` until after insert, since `nil` breaks the protocol's identity contract.
