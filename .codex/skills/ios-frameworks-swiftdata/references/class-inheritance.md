# Class Inheritance (iOS 26+)

When supporting iOS 26 and coordinated releases, SwiftData supports class inheritance for models.

**Important:** This is not a common feature. Only add model subclassing if it has a clear benefit. Protocols are often simpler and better.

## Basic Pattern

Child classes must be explicitly marked `@available` for a 26 release or later. This is required even if iOS 26 is set as the minimum deployment target.

```swift
@Model class Article {
    var type: String

    init(type: String) {
        self.type = type
    }
}

@available(iOS 26, *)
@Model class Tutorial: Article {
    var difficulty: Int

    init(difficulty: Int) {
        self.difficulty = difficulty
        super.init(type: "Tutorial")
    }
}

@available(iOS 26, *)
@Model class News: Article {
    var topic: String

    init(topic: String) {
        self.topic = topic
        super.init(type: "News")
    }
}
```

Both the parent and child classes must use the `@Model` macro.

**Note:** When using iOS 26+ as minimum deployment target, subclassed models still need `@available`, but code using those models does not — Xcode matches deployment target to model availability.

## Schema Registration

When providing schemas for model container creation, list both the parent class and all child classes. SwiftData cannot infer the connection.

## Relationships with Subclasses

A relationship to a parent class may contain the parent or any of its subclasses:

```swift
@Model class Magazine {
    @Relationship(deleteRule: .cascade) var articles: [Article]

    init(articles: [Article]) {
        self.articles = articles
    }
}
```

The `articles` array here might contain `Article`, `Tutorial`, or `News` instances.

## Filtering with Subclasses

Query for a specific subclass:

```swift
@Query private var tutorials: [Tutorial]
```

Query for the base class to get all subclasses too:

```swift
@Query private var articles: [Article]
```

Filter for specific child classes using `is`:

```swift
@Query(filter: #Predicate<Article> {
    $0 is Tutorial || $0 is News
}) private var tutorialsAndNews: [Article]
```

Typecast inside predicates to filter on child-class properties:

```swift
@Query(filter: #Predicate<Article> { article in
    if let tutorial = article as? Tutorial {
        tutorial.difficulty < 3
    } else if let news = article as? News {
        news.topic == "General"
    } else {
        false
    }
}) private var frontPageArticles: [Article]
```

The result type is the parent class — use regular Swift typecasting (`as?`) to access child-class properties.

## When to Use vs Avoid

### Good Use Cases
- Clear IS-A relationships (BusinessTrip IS-A Trip)
- Models share fundamental properties but diverge for specialization
- Need both broad queries (all types) and narrow queries (specific subtypes)
- Data naturally forms a hierarchy

### When to Avoid
- Subclasses would only share a few common properties
- Queries only target specialized properties (no broad queries needed)
- A Boolean flag or enum could represent the distinction more efficiently
- Protocol conformance would be more appropriate

## Enum-Based Filtering Pattern

```swift
enum TripKind: String, CaseIterable {
    case all, personal, business
}

struct TripListView: View {
    @Query var trips: [Trip]

    init(tripKind: TripKind, searchText: String = "") {
        let typePredicate: Predicate<Trip>? = switch tripKind {
        case .all: nil
        case .personal: #Predicate { $0 is PersonalTrip }
        case .business: #Predicate { $0 is BusinessTrip }
        }

        let searchPredicate = searchText.isEmpty ? nil : #Predicate<Trip> {
            $0.name.localizedStandardContains(searchText)
        }

        let finalPredicate: Predicate<Trip>?
        if let typePredicate, let searchPredicate {
            finalPredicate = #Predicate { typePredicate.evaluate($0) && searchPredicate.evaluate($0) }
        } else {
            finalPredicate = typePredicate ?? searchPredicate
        }

        _trips = Query(filter: finalPredicate, sort: \.startDate)
    }
}
```

## Polymorphic Relationships

Relationships to a parent class can hold instances of any subclass:

```swift
@Model class TravelPlanner {
    var name: String
    @Relationship(deleteRule: .cascade)
    var upcomingTrips: [Trip] = []  // Can hold BusinessTrip and PersonalTrip
}
```

Use runtime typecasting (`as?`) to access subclass-specific properties from polymorphic collections.

## Migration Consideration

Deep subclassing increases migration complexity. Prefer shallow hierarchies.
