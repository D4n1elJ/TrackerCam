# Indexing (iOS 18+)

When supporting iOS 18 and coordinated releases, SwiftData supports indexes to speed up queries. Indexing has a small write-time performance cost, so avoid indexes on data that is read rarely and updated frequently (such as logging).

## Single Property Indexes

```swift
@Model class Article {
    #Index<Article>([\.type], [\.author])

    var type: String
    var author: String
    var publishDate: Date

    init(type: String, author: String, publishDate: Date) {
        self.type = type
        self.author = author
        self.publishDate = publishDate
    }
}
```

## Compound Property Indexes

Mix single properties and groups of properties when they are often queried together:

```swift
#Index<Article>([\.type], [\.type, \.author])
```

## When to Index

- Properties frequently used in `#Predicate` filters or `SortDescriptor`.
- Properties used in uniqueness lookups or relationship resolution.
- Foreign-key-style UUID fields used for cross-feature references.

## When Not to Index

- Write-heavy, read-light properties (e.g. log entries, counters).
- Properties on models with very few rows where a full scan is trivial.
- `@Transient` or computed properties (they are not stored and cannot be indexed).
