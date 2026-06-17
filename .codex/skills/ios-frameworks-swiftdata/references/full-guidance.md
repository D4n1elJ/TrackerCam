# SwiftData

Write, review, and govern SwiftData code for correctness, modern API usage, migration safety, and persistence policy compliance. Report only genuine problems — do not nitpick or invent issues.

## Responsibility

**Owns:**

- `@Model` definitions, relationships, property types, delete rules
- `FetchDescriptor`, `#Predicate`, sorting, filtering
- Schema versioning, `VersionedSchema`, `SchemaMigrationPlan`
- Lightweight and custom migration stages
- Persistence governance — when migration is required, debug reset policy, store failure handling
- CloudKit-specific SwiftData constraints
- Indexing (iOS 18+) and class inheritance (iOS 26+)
- Runtime persistence patterns — container lifecycle, context provisioning, write transactions

**Does NOT own:**

- UI binding / `@Query` in SwiftUI views (SwiftUI skill)
- Background threading and actor design (Swift Concurrency skill)
- Sync architecture beyond CloudKit schema constraints
- Generic SQL, GRDB, or Core Data unless SwiftData cannot solve the problem

## Core Principles

1. **Reference-first for iOS 26+ APIs.** Class inheritance and other SwiftData features introduced in iOS 26+ may post-date training data. Always consult the relevant reference file before writing or reviewing these features — never rely on model knowledge alone.
2. Persisted schema changes are product changes.
2. Default to migration — if unsure, choose migration unless the model is clearly throwaway.
3. No silent destructive fallback outside `DEBUG`.
4. Store failures fail loudly and diagnostically.
5. Historical schemas are frozen snapshots — never derived from current model registries.
6. Initialiser defaults are not migration defaults — use stored-property defaults.
7. Resetting app data is a debug convenience, not a migration strategy.
8. Schema evolution must be explicit and versioned.
9. Issue severity ranking: data loss > crash > incorrect behaviour.

## Review Process

1. Check for core SwiftData issues using `references/core-rules.md`.
2. Check that predicates are safe and supported using `references/predicates-and-queries.md`.
3. If the project uses CloudKit, check for CloudKit-specific constraints using `references/cloudkit.md`.
4. If the project targets iOS 18+, check for indexing opportunities using `references/indexing.md`.
5. If the project targets iOS 26+, check for class inheritance patterns using `references/class-inheritance.md`.
6. For any persisted schema change, check governance rules using `references/persistence-governance.md`.
7. For any migration work, check patterns and failure scenarios using `references/migration-patterns.md`.
8. For container, context, or write-path changes, check runtime contract using `references/runtime-patterns.md`.

If doing partial work, load only the relevant reference files.

## Core Instructions

- Target Swift 6.2 or later, using modern Swift concurrency.
- Prefer SwiftData across the board. Do not suggest Core Data unless the problem cannot be solved with SwiftData.
- Do not introduce third-party frameworks without asking first.
- Use a consistent project structure, with folder layout determined by app features.
- `ModelContext` and model instances must never cross actor boundaries. Send persistent identifiers and re-fetch in the destination context.
- Always specify explicit delete rules on relationships. The default `.nullify` can orphan objects or crash on non-optional properties.
- Enum properties stored in a model must conform to `Codable`. Associated values are supported.

## Migration Decision Quick Reference

Migration planning is required whenever a durable persisted change affects existing data shape, meaning, or readability. The following changes require an explicit migration decision:

1. Adding or removing an entity or model
2. Adding, removing, renaming, or retyping a persisted property
3. Changing relationships or reference semantics
4. Changing identifiers, uniqueness rules, or key composition
5. Changing the semantic meaning of a stored field
6. Splitting one entity into multiple entities
7. Consolidating multiple entities into one entity
8. Turning transient or computed-on-write data into persisted data
9. Changing the meaning of persisted derived fields or cached values

Technical lightweight migration is not a waiver. If the semantic meaning of existing data changes, treat it as migration work even when the storage engine can open the store automatically.

**Default decision rule:** If you are unsure, choose migration unless the model is clearly throwaway.

## PR Checklist for Schema Changes

Any PR touching persisted models, migration plans, or store lifecycle must answer these questions clearly:

1. Did the persisted schema change?
2. What schema version change is required?
3. Is migration required? If not, why not?
4. Were store-open and migration tests added or updated?
5. Are defaults, derived values, identifiers, and relationships preserved correctly?
6. Are any reset tools strictly `DEBUG`-only or explicitly developer-only?
7. Is destructive fallback avoided outside explicit recovery flows?
8. Were relevant specs and docs updated?

If the PR does not answer those questions, the review is incomplete.

## Output Format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules above but make the changes directly instead of returning a findings report.

Example output:

### Destination.swift

**Line 8: Add an explicit delete rule for relationships.**

```swift
// Before
var sights: [Sight]

// After
@Relationship(deleteRule: .cascade, inverse: \Sight.destination) var sights: [Sight]
```

**Line 22: Do not use `isEmpty == false` in predicates — it crashes at runtime. Use `!` instead.**

```swift
// Before
#Predicate<Destination> { $0.sights.isEmpty == false }

// After
#Predicate<Destination> { !$0.sights.isEmpty }
```

### Summary

1. **Data loss (high):** Missing delete rule on line 8 means sights will be orphaned when a destination is deleted.
2. **Crash (high):** `isEmpty == false` on line 22 will crash at runtime — use `!isEmpty` instead.

## Key Warnings

- `@Query` only works inside SwiftUI views. Using it in a class or actor produces incorrect behaviour.
- Do not use the property name `description` in `@Model` classes; it is explicitly disallowed.
- Do not add property observers to `@Model` classes; they are silently ignored.
- Persistent identifiers are temporary before first save. Save before relying on an object's ID.
- `@Transient` properties reset to their default on fetch. Consider computed properties unless the value is expensive to produce.
- Never use `isEmpty == false`, computed properties, `@Transient` properties, custom `Codable` structs, or regular expressions in predicates — they compile but crash at runtime.

## Diagnostic Intake Checklist

Before advising on a SwiftData bug or architecture question, verify these project-level facts:

| Question | Why It Matters | How to Check |
|---|---|---|
| What is the deployment target? | `#Index`, `#Unique`, `HistoryDescriptor`, class inheritance have different availability | Check Package.swift or .pbxproj for `IPHONEOS_DEPLOYMENT_TARGET` |
| Is `ModelContainer` wired correctly? | Most "data not appearing" bugs are container wiring issues | Search for `ModelContainer` and `.modelContainer` in the project |
| Are there App Groups? | Shared containers need `groupContainer` configuration | Search for `appGroupContainerID` or `group.` in entitlements |
| Is CloudKit enabled? | CloudKit imposes constraints: no unique, optional relationships only, eventual consistency | Check for `cloudKitDatabase` in container configuration |
| Does the app use Core Data alongside SwiftData? | Coexistence requires matching managed object models | Search for `NSPersistentContainer` or `.xcdatamodeld` files |
| What undo/autosave behavior is expected? | Affects context configuration and save timing | Check for `undoManager` or `autosaveEnabled` in context setup |
| Are there background write operations? | Background writes need separate `ModelContext` on a `ModelActor` | Search for `@ModelActor` or `ModelContext(container)` outside views |
| Is there multi-store setup? | Multiple stores need explicit configuration groupings | Check for multiple `Schema` or `ModelConfiguration` instances |

**Rule:** Don't propose persistence architecture changes without knowing these facts. If any are unknown, ask the developer.

## Symptom-to-Fix Triage

When debugging SwiftData issues, match the symptom to the most likely cause:

| Symptom | Most Likely Cause | First Fix to Try |
|---|---|---|
| Insert succeeds but data doesn't appear in `@Query` | Wrong container or context; `@Query` on a different store than the insert | Verify both use the same `ModelContainer` |
| Fetch always returns empty | Container not wired to the view hierarchy; model not registered | Check `.modelContainer()` is applied above the querying view |
| Duplicate rows after network refresh | Upsert logic missing; inserting instead of find-or-create | Use `FetchDescriptor` to check existence before insert, or use `#Unique` (iOS 17+) |
| App crashes on launch after model change | Missing migration; schema version mismatch | Add `VersionedSchema` and `SchemaMigrationPlan` |
| `"historyTokenExpired"` error | History tracking token is stale | Rebuild the token by re-fetching from the earliest available transaction |
| Relationship data missing or nil | Missing `inverse` parameter; missing delete rule | Add explicit `@Relationship(inverse:)` and delete rule |
| Data appears in one view but not another | Multiple `ModelContext` instances not sharing the same container | Ensure all contexts derive from the same container instance |
| Save hangs or deadlocks | Main-actor context used from background thread | Use `@ModelActor` for background work; never share `ModelContext` across actors |
| Predicate crashes at runtime | Using unsupported predicate operations (computed properties, `isEmpty == false`, regex) | Simplify predicate; see Key Warnings above for banned predicate patterns |
| CloudKit sync not working | Schema violates CloudKit constraints (unique, non-optional relationships) | Review `references/cloudkit.md` constraints |

## Pressure Defense

**"Just reset the store, it's still early"**
If the model is on `main`, in a spec, UI-visible, or used by testers, it's durable. Resetting the store means losing their data. Write a migration — it takes 30 minutes. Diagnosing a lost-data bug from a user takes days.

**"We'll add migrations later when it matters"**
Every schema version that ships without a migration stage is a version you can never migrate from. The cost of adding migrations increases with every skipped version.

**"The initialiser default will handle it"**
Initialiser defaults are NOT used during migration. Only stored-property defaults apply. If a required field needs a value for migrated rows, put the default on the property itself and prove it with a test.

## References

- `references/core-rules.md` — @Model definitions, relationships, delete rules, property types, common mistakes.
- `references/predicates-and-queries.md` — FetchDescriptor, #Predicate, sorting, filtering, dangerous patterns.
- `references/cloudkit.md` — CloudKit-specific constraints: no unique, optional relationships, eventual consistency.
- `references/indexing.md` — iOS 18+ database indexing patterns.
- `references/class-inheritance.md` — iOS 26+ model subclassing patterns.
- `references/persistence-governance.md` — Migration decision matrix, experimental vs durable models, debug reset policy, environment rules, store failure handling, testing requirements, PR expectations.
- `references/migration-patterns.md` — Unified schema version chain, historical schema structure, lightweight vs custom migration, guard tests, common failure scenarios.
- `references/runtime-patterns.md` — Single ModelContainer per process, context provisioning, write transaction contract, cross-reference rules, App Group sharing.
