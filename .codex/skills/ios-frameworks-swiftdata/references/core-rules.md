# Core Rules

## Autosaving and Explicit Saves

- SwiftData autosaving is unpredictable. Add explicit calls to `save()` when correctness matters.
- There is no need to check `modelContext.hasChanges` before saving; just call `save()` directly.

## Actor Safety

- `ModelContext` and model instances must never cross actor boundaries.
- Model containers and persistent identifiers are sendable.
- If you need a model instance transferred across actors, send its persistent identifier and re-fetch in the destination context.

## Relationships

- When using `@Relationship`, place the macro on one side of the relationship only. Both sides causes a circular reference.
- SwiftData frequently gets inverse relationships wrong — always be explicit with `@Relationship` by specifying the exact inverse relationship.
- It is nearly always a good idea to have an explicit delete rule. The default `.nullify` can leave orphaned objects or crash if the property is non-optional. Most commonly use `@Relationship(deleteRule: .cascade)`.

## Persistent Identifiers

- Persistent identifiers are temporary before the first save. Temporary IDs start with a lowercase "t".
- A model gets a new permanent ID after its first save. You must save before relying on a model's ID.

## Property Restrictions

- Do not use the property name `description` in any `@Model` class; it is explicitly disallowed.
- Do not add property observers to `@Model` classes; they will be quietly ignored.
- Enum properties stored in a model must conform to `Codable`. Enums with associated values are supported.

## Attributes

- `@Attribute(.externalStorage)` is a suggestion, not a requirement, and only applies to `Data` properties.
- `@Transient` properties are not persisted and must have a default value. They reset to the default on fetch. Consider using a computed property instead unless the value is expensive to produce.

## Uniqueness

- Do not write `#Unique` more than once per model. If you need multiple uniqueness constraints, pass them as separate key path arrays in a single `#Unique`, e.g. `#Unique<Foo>([\.email], [\.username])`.

## @Query

- `@Query` only works inside SwiftUI views. It will not operate correctly outside views.

```swift
// Wrong
class DestinationStore {
    @Query var destinations: [Destination]
}

// Right
class DestinationStore {
    var modelContext: ModelContext

    func fetchDestinations() throws -> [Destination] {
        try modelContext.fetch(FetchDescriptor<Destination>())
    }
}
```

## FetchDescriptor Optimisation

- If you only need the count, use `ModelContext.fetchCount()` with a fetch descriptor. Note: this does not live-update unless something else triggers a refresh.
- Set `relationshipKeyPathsForPrefetching` when you know certain relationships will be used — it is more efficient to fetch them upfront.
- Set `propertiesToFetch` to limit fetched properties when not all are needed (all properties are fetched by default).

## Migrations

- It is nearly always a good idea to have a specific migration schema in place, even if the project only uses lightweight migrations.
