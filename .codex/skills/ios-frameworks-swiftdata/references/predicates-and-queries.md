# Predicates and Queries

SwiftData predicates support only a subset of Swift functionality. Some unsupported operations fail to compile. Others compile cleanly but crash at runtime.

## String Matching

Always use `localizedStandardContains()` rather than `lowercased().contains()` or similar:

```swift
@Query(filter: #Predicate<Movie> {
    $0.name.localizedStandardContains("titanic")
}) private var movies: [Movie]
```

## Prefix Matching

`hasPrefix()` and `hasSuffix()` are not supported. Use `starts(with:)` instead:

```swift
@Query(filter: #Predicate<Website> {
    $0.type.starts(with: "https://apple.com")
}) private var appleLinks: [Website]
```

## Unsupported Predicates (Will Not Compile)

These common operations have no SwiftData equivalent:

- `String.hasSuffix()`
- `String.lowercased()`
- `Sequence.map()`
- `Sequence.reduce()`
- `Sequence.count(where:)`
- `Collection.first`

Custom operators are also not allowed.

## Dangerous Predicates (Compile But Crash at Runtime)

### `isEmpty == false`

This looks equivalent to `!isEmpty` but crashes at runtime:

```swift
// Crashes at runtime
#Predicate<Movie> { $0.cast.isEmpty == false }

// Correct
#Predicate<Movie> { !$0.cast.isEmpty }
```

### Computed Properties, @Transient Properties, Custom Codable Structs

Never use these in predicates. They compile cleanly but crash at runtime. All predicates must rely on data actually stored in the database as `@Model` classes.

### Regular Expressions

Never use regular expressions in predicates. They compile cleanly then fail at runtime:

```swift
// Do NOT use — crashes at runtime
@Query(filter: #Predicate<Movie> {
    $0.name.contains(/Titanic/)
}, sort: \Movie.name)
private var movies: [Movie]
```

## FetchDescriptor Patterns

For non-view contexts, use `FetchDescriptor` with `ModelContext.fetch()`:

```swift
let descriptor = FetchDescriptor<Destination>(
    predicate: #Predicate { $0.isActive },
    sortBy: [SortDescriptor(\.name)]
)
let results = try modelContext.fetch(descriptor)
```

Optimise with:

- `propertiesToFetch` — limit fetched properties when not all are needed.
- `relationshipKeyPathsForPrefetching` — prefetch relationships you know will be accessed.
- `fetchLimit` — cap result count when only a subset is needed.
- `fetchOffset` — skip results for pagination.
- `ModelContext.fetchCount()` — when you only need the count.
