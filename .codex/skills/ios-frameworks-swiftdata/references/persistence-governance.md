# Persistence Governance

> Canonical policy for persisted-schema changes, migrations, store resets, and persistence-related review expectations.

## Purpose

Persistence breakage is not an acceptable routine cost of development.

Persisted model changes are product changes. They affect whether existing installs, internal builds, seeded environments, and developer stores can still open and preserve meaning. Repeatedly breaking store creation because schema changes were introduced without migration handling is an engineering failure, not a harmless inconvenience.

This policy makes the default behaviour explicit: durable persistence changes must be versioned, migration-aware, tested, and reviewed as data-integrity work.

## Core Principles

- Persisted schema changes are product changes.
- Resetting app data is a debug convenience, not a migration strategy.
- Durable product-direction changes must be migratable.
- Schema evolution must be explicit and versioned.
- No silent destructive fallback outside `DEBUG`.
- If a store cannot be opened or migrated, it must fail loudly and diagnostically.

## Schema Versioning Rules

- Persisted schema changes MUST be versioned deliberately.
- Ad hoc breaking changes to shipped or durable schemas are not acceptable.
- Schema history MUST remain explicit through `VersionedSchema` definitions and migration-plan history.
- Migration planning MUST accompany durable schema changes before they merge.
- Editing old shipped schema snapshots in place is forbidden. Add the next schema version instead.

## When Migration Is Required

Migration planning is required whenever a durable persisted change can affect existing data shape, meaning, or readability.

The following changes require an explicit migration decision and usually require a migration:

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

## Migration Decision Matrix

| Model status | Migration required? |
|---|---|
| On `main` branch | Yes |
| Referenced by an approved spec | Yes |
| User-visible or drives visible UI | Yes |
| Tests, fixtures, demos, or seeded data depend on it | Yes |
| Multiple features depend on it | Yes |
| Same breakage has already happened more than once | Yes |
| Short-lived spike or prototype | No (reset-first acceptable) |
| Isolated experiment with no retained data dependency | No (reset-first acceptable) |
| Not referenced by approved specs | No (reset-first acceptable) |
| Not depended on by other features, tests, demos, or seeded data | No (reset-first acceptable) |

**Default decision rule:** If you are unsure, choose migration unless the model is clearly throwaway.

## Experimental vs Durable Models

Reset-first development is acceptable only when the persisted model is clearly throwaway:

- short-lived spikes or prototypes
- isolated experiments with no meaningful retained data dependency yet
- models not referenced by approved specs
- models not depended on by other features, tests, demos, or seeded data

Migration becomes mandatory when any of the following is true:

- the feature or model is on `main`
- the feature is referenced by an approved spec
- the data is user-visible or drives visible UI
- tests, fixtures, demos, or seeded data depend on it
- multiple features depend on it
- the same breakage has already happened more than once

If a model has crossed out of experiment status, reset-first development is over.

## Debug Reset Policy

- Local store reset is allowed only in `DEBUG` or other explicit developer-only workflows.
- Reset actions MUST be explicit, visible, and opt-in.
- Automatic destructive fallback is forbidden in release builds.
- The app MUST NOT silently reset the store after a migration or store-open failure.
- Debug reset tooling MUST NOT be presented as the default solution for durable schema evolution.

## Store Initialisation and Failure Handling

- Store open failures MUST fail loudly and diagnostically.
- Migration failures MUST be surfaced clearly to the user or developer.
- Logs and diagnostics MUST include relevant schema and migration version information when available.
- Hidden destructive fallback is forbidden.
- Recovery UI may offer an explicit reset action, but only as a user-visible last resort.

## Environment Rules

### Spike Work

- Explicit reset-only workflows are acceptable.
- Do not pretend spike persistence is durable.
- Before merging, either remove the throwaway model or promote it to durable handling.

### Main Branch

- Durable persisted changes on `main` must carry schema versioning and migration planning.
- "Everyone can just reset" is not acceptable once the change is shared on the mainline.

### Internal, Shared, and Test Builds

- Migration is mandatory for durable schema changes.
- Store-open paths and migration behaviour must be tested before handoff.
- Seeded and demo data must continue to open or be intentionally regenerated through explicit tooling.

### Production Readiness

- Migration is mandatory.
- Migration behaviour must be tested against prior schema versions.
- Destructive reset may exist only as an explicit recovery path, never as a hidden fallback.

## Testing Requirements

Changes that touch persisted models or migration paths MUST include the right verification. At minimum:

- Test that the current store still opens successfully.
- Test migration from the relevant prior schema version or versions.
- Test preservation of critical entities, identifiers, and relationships.
- Test required defaults, backfilled values, and derived-field meaning after migration.
- Add migration smoke tests where feasible so gross incompatibilities fail fast.

When multiple features share the same unified schema, migration tests must prove that changed models migrate correctly and unchanged models still survive the version step.

## Specification and Documentation Alignment

Persistence-affecting changes must update the relevant durable docs, not just code:

- Update the relevant feature specification when persisted behaviour or contracts change.
- Update persistence system docs when persistence rules or implementation expectations change.
- Keep terminology consistent across specs, system docs, code, and PR descriptions.
- Do not leave conflicting old guidance in agent docs, lessons, or workflow docs.

## PR Expectations

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
