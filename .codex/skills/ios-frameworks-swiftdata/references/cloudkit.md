# CloudKit Constraints

**These rules only apply if the project is configured to use SwiftData with CloudKit.**

## Uniqueness

- Never use `@Attribute(.unique)` or `#Unique` — they are not supported in CloudKit and will cause local data to fail too.

## Optionality

- All model properties must either have default values or be marked as optional.
- All relationships must be marked optional.

## Indexes and Subclasses

- Indexes and subclasses are supported in CloudKit, as long as the correct OS release is used.

## Eventual Consistency

- CloudKit is designed for eventual consistency. Any SwiftData code with CloudKit support must function correctly if data has yet to synchronise.
- Design queries and UI to handle missing or delayed data gracefully.

## Conflict Resolution

- CloudKit uses last-writer-wins for conflict resolution at the record level.
- Design data models to minimise conflicts: prefer append-only patterns and avoid frequent updates to the same record from multiple devices.
