# Migration Patterns

> Canonical strategy for SwiftData schema evolution, migration implementation, and migration testing.

## Unified Schema Version Chain

The app ships one migration chain — not per-feature version chains.

Rules:

- One app-wide schema version chain.
- `PersistenceSchema.schema` must always point at the latest `VersionedSchema`.
- `SchemaMigrationPlan.schemas` must contain every shipped schema version in order.
- `SchemaMigrationPlan.stages` must contain every adjacent version transition in order.
- Historical schema membership must be explicit.
- Historical schemas must never be derived from current model registries (`allModels`, `stableModels`, etc.).

That last rule matters. Using current model registries inside old `VersionedSchema` definitions is a migration bug. Future model additions or shape changes will silently mutate old schemas and make migration tests lie.

## Historical Schema Structure

The latest schema uses current `@Model` types and may point at `allModels`. Historical schemas must freeze old shapes.

Required structure:

1. **Latest schema** — uses current `@Model` types; the only schema allowed to reference current model registries.
2. **Historical schemas** — use explicit model arrays; use frozen snapshot types for any model that changed after that version shipped; must not be edited in place.

Practical rule: if `UserPreferencesModel` changes in `SchemaV5`, then `SchemaV4` must stop referencing the live type and instead use a frozen `SchemaV4.UserPreferencesModel` snapshot.

Do not rely on "it still compiles." Compilation does not prove historical schemas are still historically correct.

## Initialiser Defaults Are Not Migration Defaults

If a new non-optional field needs a default for migrated rows, put the default on the stored property itself:

```swift
// Wrong — initialiser default is not used during migration
@Model
final class UserPreferencesModel {
    var showTransportInTimeline: Bool

    init(showTransportInTimeline: Bool = true) {
        self.showTransportInTimeline = showTransportInTimeline
    }
}

// Correct — stored-property default is used during migration
@Model
final class UserPreferencesModel {
    var showTransportInTimeline: Bool = true
}
```

Always prove the default with a migration test.

## Lightweight vs Custom Migration

### Lightweight

Use lightweight migration only when SwiftData can safely carry old rows forward without data transformation.

Typical lightweight changes:

- Add an optional property.
- Rename a property using `@Attribute(originalName:)`.
- Add a new model with no required data copied from old rows.
- Add a non-optional property only when the stored-property default is explicit and tested.

### Custom

Use a custom migration stage when existing rows need transformation or repair.

Typical custom cases:

- Change stored type.
- Split or merge models.
- Remove required data that needs fallback handling.
- Backfill required fields from old columns.
- Semantic changes that need deterministic transformation.

Rule: lightweight is only acceptable when the old row can open safely and mean the right thing after migration. If semantics need deliberate repair, use a custom stage.

## How to Add a New Schema Version

When adding `SchemaV5`:

1. Add `SchemaV5: VersionedSchema`.
2. Point `PersistenceSchema.schema` at `SchemaV5`.
3. Append `SchemaV5.self` to `SchemaMigrationPlan.schemas`.
4. Append exactly one `MigrationStage` for `SchemaV4 -> SchemaV5`.
5. Freeze any `SchemaV4` model definitions that would otherwise keep pointing at changed live model types.
6. Add or update migration tests for `V4 -> V5`.
7. Update persistence docs and any affected feature specs.

Do not:

- Edit old shipped schema snapshots in place to match new production models.
- Skip version numbers.
- Add a new schema without tests.
- Rely on a reset flow as the migration plan.

## Example: Lightweight Version Bump

```swift
nonisolated enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        PersistenceSchema.allModels
    }
}

nonisolated enum PersistenceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            MigrationStage.lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            MigrationStage.lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self)
        ]
    }
}
```

## Example: Custom Backfill

```swift
static let migrateV4toV5 = MigrationStage.custom(
    fromVersion: SchemaV4.self,
    toVersion: SchemaV5.self,
    willMigrate: { context in
        // fetch old rows, transform, save deterministically
        try context.save()
    },
    didMigrate: nil
)
```

## Guard Tests

Migration smoke tests without guard tests are not enough. Guard tests catch structural mistakes before a specific migration fixture is even written:

- Latest schema in `PersistenceSchema.schema` matches the tail of `SchemaMigrationPlan.schemas`.
- Migration plan stage count matches adjacent version transitions.
- Historical schemas use frozen snapshot types for changed models instead of live mutable current types.

## Migration Testing Contract

Every adjacent migration stage must be tested with a real on-disk store created from the old schema.

Minimum required coverage:

1. Create a store using the old `VersionedSchema`.
2. Seed representative old rows.
3. Close that container.
4. Re-open through the real container and the real migration plan.
5. Verify the current models after migration.
6. Verify untouched models still survive the version step.
7. Verify defaults, backfills, identifiers, and important invariants.

## Backfill vs Runtime Repair

Use migration/backfill when:

- The store must open correctly.
- Required persisted fields need values.
- Meaning of stored data changed.
- Future queries would be wrong unless data is transformed immediately.

Use runtime repair only when ALL of these are true:

- The store already opens safely.
- The data is recoverable or derived.
- The repair is idempotent.
- The app can tolerate the old value until the repair runs.
- The repair is documented as runtime repair, not migration.

## Backwards Compatibility

- Support forward migration from every shipped schema in the version chain.
- No backward migration support.
- Migration failure must be loud and diagnosable.
- Outside explicit developer-only flows, never silently destroy the store to recover.

## Breaking Changes During Active Development

Allowed reset-first cases:

- Isolated spike work.
- Non-shared experiments.
- No approved spec.
- No UI-visible retained data.
- Not on `main`.

Not allowed:

- Shared mainline features.
- Durable developer/test/demo stores.
- Any persisted model already referenced by specs, tests, or visible UI.

If you are arguing that a durable model should avoid migration because "this is still early," the default assumption is that you are wrong.

## willMigrate / didMigrate Limitation

**Critical:** In a custom `MigrationStage`, `willMigrate` runs before the schema change and `didMigrate` runs after — but neither callback can access both the old and new model shapes simultaneously.

- `willMigrate` sees the old schema. You can read old columns, transform data, and write intermediate values — but the new columns don't exist yet.
- `didMigrate` sees the new schema. You can read new columns and backfill — but old columns that were removed are gone.

This means **type changes** (e.g., changing a column from `String` to `Int`, or from a flat property to a relationship) cannot be done in a single migration stage.

### Two-Stage Migration Pattern

When the old and new shapes are incompatible, use an intermediate schema version:

```
SchemaV3 (old shape) → SchemaV3_1 (both old + new columns) → SchemaV4 (new shape only)
```

**Stage 1:** Add the new column alongside the old one. In `didMigrate`, copy/transform data from old to new.

**Stage 2:** Remove the old column (via table recreation if needed).

```swift
// V3 → V3.1: Add new column, keep old
static let migrateV3toV3_1 = MigrationStage.custom(
    fromVersion: SchemaV3.self,
    toVersion: SchemaV3_1.self,
    willMigrate: nil,
    didMigrate: { context in
        // Both old and new columns exist — transform data
        // e.g., parse String dates into Date column
        try context.save()
    }
)

// V3.1 → V4: Remove old column
static let migrateV3_1toV4 = MigrationStage.lightweight(
    fromVersion: SchemaV3_1.self,
    toVersion: SchemaV4.self
)
```

**Rule:** If you need to read old data AND write new data in the same callback, you need an intermediate version where both columns coexist.

## Common Failure Scenarios

### 1. Historical schema derived from current model registry

**Problem:** Adding a future model silently changes an old schema. Migration tests stop proving what they claim.

**Prevention:** Keep historical schema membership explicit. Add guard tests for frozen historical models.

### 2. New required field relies on initialiser default

**Problem:** Old rows migrate without a stored value. Container creation can fail or the field can be wrong.

**Prevention:** Use a stored-property default or a custom migration backfill. Add a migration test.

### 3. Old schema snapshots edited in place

**Problem:** Migration history no longer matches shipped reality.

**Prevention:** Only add the next schema version. Never "update" old historical snapshots.

### 4. Tests only cover fresh in-memory stores

**Problem:** Fresh-store behaviour passes while migrated on-disk stores fail.

**Prevention:** Migration tests must build real old-schema stores on disk and reopen them through the real container.

### 5. Runtime repair used as migration substitute

**Problem:** Store-open bugs move later into app lifecycle. Data integrity becomes timing-dependent.

**Prevention:** Put structural and semantic repair in migration stages. Reserve runtime repair for derived or recoverable data only.
