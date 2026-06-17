# Full-Text Search (FTS)

## FTS Engine Comparison

| Feature | FTS3/FTS4 | FTS5 |
|---|---|---|
| Availability | All SQLite builds | Requires SQLITE_ENABLE_FTS5 |
| Ranking | Manual | Built-in `rank` column |
| Custom tokenizers | Limited | Full API |
| Performance | Good | Better for large datasets |
| Prefix search | Yes | Yes + phrase prefixes |
| GRDB recommendation | Legacy | Preferred for new work |

## Creating FTS Tables

### FTS4

```swift
try db.create(virtualTable: "book", using: FTS4()) { t in
    t.tokenizer = .unicode61()
    t.column("author")
    t.column("title")
    t.column("body")
}
```

### FTS5

```swift
try db.create(virtualTable: "document", using: FTS5()) { t in
    t.tokenizer = .porter(.unicode61(diacritics: .keep))
    t.column("content")
    t.column("uuid").notIndexed()   // stored but not searchable
    t.prefixes = [2, 4]             // optimise prefix queries
    t.columnSize = 0                // save space if not using xColumnSize
    t.detail = "column"             // per-column position info
}
```

## Tokenizers

| Engine | Tokenizer | Behaviour |
|---|---|---|
| FTS3/4 | `.simple` | ASCII case folding only |
| FTS3/4 | `.porter` | English stemming |
| FTS3/4 | `.unicode61(diacritics:)` | Unicode case + optional diacritics |
| FTS5 | `.ascii()` | ASCII case folding |
| FTS5 | `.unicode61(diacritics:)` | Unicode case + optional diacritics |
| FTS5 | `.porter(wrapping)` | Stemming + wrapped tokenizer |

**Chain tokenizers in FTS5** for best results:

```swift
t.tokenizer = .porter(.unicode61(diacritics: .keep))
// Stemming + Unicode case folding + diacritics preserved
```

## Search Patterns

All pattern constructors return `nil` for empty or invalid input:

| Pattern | FTS3 | FTS5 | Matches |
|---|---|---|---|
| `matchingAnyTokenIn:` | Yes | Yes | OR search — any token |
| `matchingAllTokensIn:` | Yes | Yes | AND search — all tokens |
| `matchingAllPrefixesIn:` | Yes | Yes | Prefix AND — all token prefixes |
| `matchingPhrase:` | Yes | Yes | Exact phrase |
| `matchingPrefixPhrase:` | No | Yes | Phrase + last token as prefix |

```swift
// "contains both 'swift' and 'database'"
let pattern = FTS5Pattern(matchingAllTokensIn: "swift database")

// "starts with 'swi' and 'dat'"
let pattern = FTS5Pattern(matchingAllPrefixesIn: "swi dat")
```

### Raw Patterns

```swift
// FTS3: raw syntax (NOT validated)
let pattern = try FTS3Pattern(rawPattern: "swift OR database")

// FTS5: validated against a table
let pattern = try db.makeFTS5Pattern(rawPattern: "swift OR database", forTable: "document")
```

## Searching

```swift
// Simple match
let books = try Book.matching(pattern).fetchAll(db)

// FTS5 with ranking (lower rank = better match)
let docs = try Document
    .matching(pattern)
    .order(Column.rank)
    .fetchAll(db)

// Check if pattern is nil (empty search)
if let pattern = FTS5Pattern(matchingAllTokensIn: searchText) {
    return try Document.matching(pattern).order(Column.rank).fetchAll(db)
} else {
    return try Document.fetchAll(db)  // no search, return all
}
```

## External Content Tables (Synchronized FTS)

Keep an FTS index in sync with a regular table using triggers:

```swift
// Regular table
try db.create(table: "book") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("author", .text)
    t.column("title", .text)
    t.column("content", .text)
}

// FTS4 with synchronisation triggers (auto-created)
try db.create(virtualTable: "book_ft", using: FTS4()) { t in
    t.synchronize(withTable: "book")
    t.column("author")
    t.column("title")
    t.column("content")
}

// FTS5 with synchronisation triggers
try db.create(virtualTable: "book_ft", using: FTS5()) { t in
    t.synchronize(withTable: "book")
    t.column("author")
    t.column("title")
    t.column("content")
}
```

### Querying Synchronised Tables

Join FTS results back to the main table for full record data:

```swift
let sql = """
    SELECT book.* FROM book
    JOIN book_ft ON book_ft.rowid = book.rowid
    WHERE book_ft MATCH ?
    ORDER BY book_ft.rank
    """
let books = try Book.fetchAll(db, sql: sql, arguments: [pattern])
```

### Cleanup

```swift
try db.dropFTS4SynchronizationTriggers(forTable: "book_ft")
try db.dropFTS5SynchronizationTriggers(forTable: "book_ft")
```

## FTS in Migrations

```swift
migrator.registerMigration("add-book-search") { db in
    try db.create(virtualTable: "book_ft", using: FTS5()) { t in
        t.synchronize(withTable: "book")
        t.tokenizer = .porter(.unicode61())
        t.column("title")
        t.column("content")
    }
}
```

To rebuild an FTS index in a migration:

```swift
migrator.registerMigration("rebuild-search-index") { db in
    try db.execute(sql: "INSERT INTO book_ft(book_ft) VALUES('rebuild')")
}
```

## Unicode Normalisation

SQLite FTS does not normalise Unicode forms. "cafe\u{0301}" (decomposed) and "caf\u{00e9}" (precomposed) are different tokens.

**Fix:** Normalise to NFC before storing and querying:

```swift
let normalised = text.precomposedStringWithCanonicalMapping
```

## Pitfalls

- **FTS5 requires compilation flag.** The system SQLite on iOS includes FTS5 since iOS 11, but custom builds must enable `SQLITE_ENABLE_FTS5`.
- **Empty search patterns are nil.** Always handle the nil case — don't force-unwrap pattern constructors.
- **FTS columns are all text.** There are no typed columns in FTS tables. The `notIndexed()` modifier stores but doesn't search.
- **Ranking is FTS5 only.** FTS3/4 requires manual rank computation via auxiliary functions.
- **External content sync has overhead.** Each insert/update/delete on the source table fires triggers to update the FTS index. For bulk imports, consider deferring sync.
- **Raw patterns can crash.** FTS3 raw patterns are not validated. FTS5 patterns validated via `makeFTS5Pattern` are safe.
- **Unicode normalisation** must be handled at the application level — SQLite does not normalise forms.
