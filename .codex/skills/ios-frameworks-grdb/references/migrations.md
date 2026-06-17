# Migrations

## DatabaseMigrator

```swift
var migrator = DatabaseMigrator()

migrator.registerMigration("v1-create-authors") { db in
    try db.create(table: "author") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("name", .text).notNull()
        t.column("birthYear", .integer)
    }
}

migrator.registerMigration("v2-add-books") { db in
    try db.create(table: "book") { t in
        t.autoIncrementedPrimaryKey("id")
        t.belongsTo("author").notNull()  // creates authorId + FK + index
        t.column("title", .text).notNull()
    }
}

try migrator.migrate(dbQueue)
```

## Rules

1. **Migrations are forward-only.** Attempting to revert is a fatal error.
2. **Each migration runs in its own transaction.** If it throws, it rolls back. Subsequent migrations do not run.
3. **Never modify a shipped migration.** Migrations describe past database states. Add new migrations instead.
4. **Use string literals, not Swift types.** Do not reference `Author.databaseTableName` or `CodingKeys` — the code will evolve but the migration must stay frozen.
5. **Migration identifiers must be unique** and are stored in the `grdb_migrations` table.

## Table Creation

```swift
try db.create(table: "player") { t in
    // Primary keys
    t.autoIncrementedPrimaryKey("id")              // INTEGER autoincrement
    t.primaryKey("uuid", .text)                     // text PK
    t.primaryKey {                                  // composite PK
        t.column("a", .text)
        t.column("b", .integer)
    }

    // Column types
    t.column("name", .text)
    t.column("score", .integer)
    t.column("average", .double)
    t.column("isActive", .boolean)
    t.column("data", .blob)
    t.column("createdAt", .datetime)
    t.column("metadata", .jsonText)

    // Constraints
    t.column("email", .text).notNull().unique().indexed()
    t.column("name", .text).notNull().defaults(to: "Anonymous")
    t.column("name", .text).check { length($0) > 0 }
    t.column("total", .integer).generatedAs(Column("score") + Column("bonus"))

    // Foreign keys
    t.belongsTo("team", onDelete: .cascade)            // creates teamId + FK + index
    t.belongsTo("author", inTable: "person")           // FK to differently-named table
    t.foreignKey(["a", "b"], references: "parents")    // composite FK

    // Composite unique
    t.uniqueKey(["a", "b"], onConflict: .replace)
}

// Options
try db.create(table: "temp", options: .temporary) { t in ... }
try db.create(table: "maybe", options: .ifNotExists) { t in ... }
```

### Column Types

`.text`, `.integer`, `.double`, `.real`, `.numeric`, `.boolean`, `.blob`, `.date`, `.datetime`, `.any`, `.jsonText`

## Table Alteration

### Simple Alterations (SQLite supports directly)

```swift
// Rename table
try db.rename(table: "referer", to: "referrer")

// Alter columns
try db.alter(table: "player") { t in
    t.add(column: "hasBonus", .boolean)             // add column
    t.rename(column: "url", to: "homeURL")          // rename (SQLite 3.25.0+)
    t.drop(column: "score")                          // drop (SQLite 3.35.0+)
}

// Drop table
try db.drop(table: "obsolete")
```

### Indexes

```swift
try db.create(indexOn: "player", columns: ["email"])
try db.create(indexOn: "player", columns: ["email"], options: .unique)
try db.drop(indexOn: "player", columns: ["email"])
```

## Table Recreation

Required when ALTER TABLE cannot handle the change (adding NOT NULL, changing defaults, changing column types, etc.).

**Exact sequence:**

```swift
migrator.registerMigration("add-not-null-to-author-name") { db in
    // 1. Create new table with desired schema
    try db.create(table: "new_author") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("creationDate", .datetime)
        t.column("name", .text).notNull()  // now NOT NULL
    }

    // 2. Copy data
    try db.execute(sql: "INSERT INTO new_author SELECT * FROM author")

    // 3. Drop original
    try db.drop(table: "author")

    // 4. Rename new to original
    try db.rename(table: "new_author", to: "author")

    // 5. Recreate indexes, triggers, views that referenced the table
    try db.create(indexOn: "author", columns: ["name"])
}
```

**If columns differ** between old and new schema, use explicit column mapping:

```swift
try db.execute(sql: """
    INSERT INTO new_author(id, creationDate, name)
    SELECT id, creationDate, COALESCE(name, 'Unknown')
    FROM author
    """)
```

## Foreign Key Handling

### Default: Deferred Checks

By default, each migration temporarily disables FK enforcement and performs a full FK integrity check before committing. This allows table recreation sequences.

### Immediate Checks

Use when doing simple renames that preserve FK relationships:

```swift
migrator.registerMigration("rename-team-to-guild", foreignKeyChecks: .immediate) { db in
    try db.rename(table: "team", to: "guild")
    try db.alter(table: "player") { t in
        t.rename(column: "teamId", to: "guildId")
    }
}
```

**Immediate checks and table recreation are incompatible.** If you need both, split into separate migrations.

### Disabling Deferred Checks Globally

```swift
migrator = migrator.disablingDeferredForeignKeyChecks()
```

Performance optimisation for apps that don't need FK verification during migration.

### Manual FK Check

```swift
try db.checkForeignKeys()           // all tables
try db.checkForeignKeys(in: "book") // specific table
```

## Development Convenience

```swift
var migrator = DatabaseMigrator()
#if DEBUG
migrator.eraseDatabaseOnSchemaChange = true
#endif
```

Wipes and recreates the database when migration definitions change during development. **Never ship this enabled** — it destroys user data.

## Schema Version Checks

```swift
try dbQueue.read { db in
    // Is the database fully migrated?
    if try migrator.hasCompletedMigrations(db) == false {
        // database is too old — needs migration
    }

    // Was the database created by a newer app version?
    if try migrator.hasBeenSuperseded(db) {
        // database is too new — unknown migrations present
    }
}
```

## Migrate to Specific Version

```swift
try migrator.migrate(dbQueue)              // run all pending
try migrator.migrate(dbQueue, upTo: "v3")  // stop at v3
```

## Common Migration Patterns

### Adding a column with a backfill

```swift
migrator.registerMigration("add-fullName") { db in
    try db.alter(table: "player") { t in
        t.add(column: "fullName", .text)
    }
    try db.execute(sql: """
        UPDATE player SET fullName = firstName || ' ' || lastName
        """)
}
```

### Splitting a table

```swift
migrator.registerMigration("split-address-from-user") { db in
    try db.create(table: "address") { t in
        t.autoIncrementedPrimaryKey("id")
        t.belongsTo("user").notNull()
        t.column("street", .text)
        t.column("city", .text)
    }
    try db.execute(sql: """
        INSERT INTO address(userId, street, city)
        SELECT id, street, city FROM user WHERE street IS NOT NULL
        """)
    try db.alter(table: "user") { t in
        t.drop(column: "street")
        t.drop(column: "city")
    }
}
```

### Renaming an enum value in a column

```swift
migrator.registerMigration("rename-status-active-to-enabled") { db in
    try db.execute(sql: """
        UPDATE settings SET status = 'enabled' WHERE status = 'active'
        """)
}
```

## Pitfalls

- **Modifying shipped migrations** causes `eraseDatabaseOnSchemaChange` to wipe the database in DEBUG, and is meaningless in production (already-run migrations are skipped).
- **Using Swift types in migrations** (`Author.databaseTableName`, `CodingKeys`) silently couples migration to current code. When the type changes, the migration breaks.
- **Table recreation with `.immediate` FK checks** is impossible — the intermediate state violates FK constraints. Use separate migrations or default deferred checks.
- **Forgetting to recreate indexes** after table recreation silently drops all indexes on the rebuilt table.
- **Column default vs backfill:** `defaults(to:)` only applies to new rows. Existing rows need an explicit `UPDATE` to populate.
