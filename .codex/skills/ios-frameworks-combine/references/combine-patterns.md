# Combine Patterns

## Publisher / Subscriber / Subscription Model

A **Publisher** declares a type of value and error it can produce. A **Subscriber** receives values. A **Subscription** connects them and manages demand (back-pressure).

```swift
// The protocol chain:
// Publisher.subscribe(Subscriber)
//   --> Subscriber.receive(subscription:)
//   --> Subscription.request(.unlimited)  // or .max(n)
//   --> Subscriber.receive(value)         // 0 or more times
//   --> Subscriber.receive(completion:)   // exactly once (.finished or .failure)
```

In practice, you rarely implement these protocols directly. Use `sink`, `assign`, or operator chains.

## Common Operators

### Transform

```swift
// map: transform each value
publisher.map { $0.name }

// compactMap: transform + filter nil
publisher.compactMap { Int($0) }

// flatMap: each value produces a new publisher
searchText
    .flatMap { query in api.search(query) }
```

**flatMap pitfall**: Without `maxPublishers: .max(1)`, flatMap creates a new inner publisher per upstream value. For search-as-you-type, use `map` + `switchToLatest`:

```swift
searchText
    .map { query in api.search(query) }
    .switchToLatest()  // Cancels previous search on new query
```

### Filter

```swift
// filter: pass values matching predicate
publisher.filter { $0 > 0 }

// removeDuplicates: skip consecutive equal values
publisher.removeDuplicates()

// removeDuplicates with custom comparison
publisher.removeDuplicates(by: { $0.id == $1.id })

// first: take first value then complete
publisher.first()

// prefix: take first N values
publisher.prefix(5)

// dropFirst: skip first N values
publisher.dropFirst(3)
```

### Combine Multiple Sources

```swift
// combineLatest: latest from each, fires when ANY changes
Publishers.CombineLatest(namePublisher, agePublisher)
    .map { name, age in "\(name), \(age)" }

// merge: interleave values from same-type publishers
Publishers.Merge(localUpdates, remoteUpdates)
    .sink { update in handle(update) }

// zip: pairs values 1:1, waits for both
Publishers.Zip(requestA, requestB)
    .sink { responseA, responseB in /* both arrived */ }
```

| Operator | Fires When | Use Case |
|----------|-----------|----------|
| combineLatest | Any input changes | Form validation (all fields) |
| merge | Any input produces | Combining event streams |
| zip | All inputs produce one value | Parallel requests needing both results |

### Time-Based

```swift
// debounce: emit after silence window
searchText
    .debounce(for: .milliseconds(300), scheduler: RunLoop.main)

// throttle: emit at most once per interval
scrollOffset
    .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)

// delay: shift values forward in time
publisher.delay(for: .seconds(1), scheduler: RunLoop.main)
```

| Operator | Behavior | Use Case |
|----------|----------|----------|
| debounce | Waits for silence, emits last | Search fields, auto-save |
| throttle(latest: true) | Emits latest at fixed intervals | Scroll tracking, sensor data |
| throttle(latest: false) | Emits first at fixed intervals | Rate-limiting taps |

## Subjects

### PassthroughSubject

No initial value. Late subscribers miss previous values. Use for events.

```swift
let taps = PassthroughSubject<Void, Never>()
taps.send()
```

### CurrentValueSubject

Always has a current value. Late subscribers get it immediately. Use for state.

```swift
let isLoading = CurrentValueSubject<Bool, Never>(false)
isLoading.value = true   // Direct read/write
isLoading.send(false)    // Also works
```

### Completion Kills the Subject

Once a subject receives `.finished` or `.failure`, all subsequent `send()` calls are silently ignored. No crash, no warning.

```swift
let subject = PassthroughSubject<Int, Never>()
subject.send(1)                        // Delivered
subject.send(completion: .finished)
subject.send(2)                        // Silently ignored
```

## @Published Property Wrapper

### willSet Timing

`@Published` fires in `willSet`, not `didSet`. Subscribers see the new value before the property is actually set.

```swift
class ViewModel: ObservableObject {
    @Published var count = 0

    init() {
        $count.sink { newValue in
            // newValue is incoming, self.count is still OLD
            print("New: \(newValue), Current: \(self.count)")
        }
        .store(in: &cancellables)
    }
}
```

### Thread Safety

`@Published` is not thread-safe. Setting from a background thread crashes SwiftUI.

```swift
// Fix: @MainActor on the class
@MainActor
class ViewModel: ObservableObject {
    @Published var data: [Item] = []
}
```

### Nested ObservableObject

SwiftUI does not observe nested `ObservableObject` changes. Forward manually:

```swift
class AppState: ObservableObject {
    @Published var settings = Settings()
    private var cancellables = Set<AnyCancellable>()

    init() {
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
```

Better: migrate to `@Observable` (iOS 17+), which handles nesting automatically.

## Error Handling

```swift
// tryMap: transform that can throw
publisher.tryMap { data in
    try JSONDecoder().decode(Model.self, from: data)
}

// mapError: convert error types
publisher.mapError { AppError.network($0) }

// replaceError: fallback value, makes pipeline infallible
publisher.replaceError(with: defaultValue)

// retry: re-subscribe on failure
publisher.retry(3)

// catch: replace failed publisher with another
publisher.catch { error in fallbackPublisher }
```

**Order matters**: `retry` before `replaceError`. Retry re-subscribes; replaceError terminates the error path.

```swift
api.fetchData()
    .retry(3)
    .replaceError(with: cached)
    .sink { data in update(data) }
    .store(in: &cancellables)
```

**replaceError after flatMap kills the outer pipeline**:

```swift
// BAD: one inner error terminates everything
$searchText
    .flatMap { query in api.search(query) }
    .replaceError(with: [])

// GOOD: each inner publisher handles its own errors
$searchText
    .flatMap { query in
        api.search(query).replaceError(with: [])
    }
    .sink { ... }
```

## Schedulers

```swift
// receive(on:): deliver values on a specific scheduler
publisher
    .receive(on: RunLoop.main)
    .sink { value in updateUI(value) }

// subscribe(on:): perform upstream work on a specific scheduler
publisher
    .subscribe(on: DispatchQueue.global())
    .receive(on: RunLoop.main)
    .sink { value in updateUI(value) }
```

`receive(on:)` affects downstream. `subscribe(on:)` affects upstream. In most cases you only need `receive(on: RunLoop.main)` before UI updates.

## Memory Management

### AnyCancellable Storage

```swift
private var cancellables = Set<AnyCancellable>()

publisher
    .sink { [weak self] value in self?.handle(value) }
    .store(in: &cancellables)
```

### The 4 Leak Patterns

1. **Strong self in sink** -- use `[weak self]`
2. **Missing store(in:)** -- cancellable deallocates, pipeline cancelled immediately
3. **Accumulating subscriptions** -- call `cancellables.removeAll()` before re-subscribing
4. **assign(to:on: self)** -- captures `self` strongly. Use `assign(to: &$prop)` instead (no AnyCancellable returned, lifecycle tied to @Published owner)

## Cold vs Hot Publishers

Most publishers are **cold** -- each subscriber gets independent execution.

```swift
// Two subscribers = two network requests
let pub = URLSession.shared.dataTaskPublisher(for: url).map(\.data)
pub.sink { cache($0) }.store(in: &cancellables)   // Request 1
pub.sink { display($0) }.store(in: &cancellables)  // Request 2
```

### share()

Makes a cold publisher hot. First subscriber triggers work, others share output.

```swift
let pub = URLSession.shared.dataTaskPublisher(for: url)
    .map(\.data)
    .share()
```

Gotchas:
- Late subscribers miss values (no replay)
- All subscribers cancel = upstream cancels; new subscriber triggers fresh execution
- Use `multicast(subject:)` with `CurrentValueSubject` if late subscribers need the last value

## Custom Publishers

Implement `Publisher` protocol for reusable patterns. Prefer composing existing operators first.

```swift
struct PollingPublisher: Publisher {
    typealias Output = Data
    typealias Failure = Error

    let url: URL
    let interval: TimeInterval

    func receive<S: Subscriber>(subscriber: S)
        where S.Input == Output, S.Failure == Failure
    {
        let subscription = PollingSubscription(
            subscriber: subscriber, url: url, interval: interval
        )
        subscriber.receive(subscription: subscription)
    }
}
```

In practice, `Timer.publish` + `flatMap` or a `PassthroughSubject` fed by a timer covers most polling needs without a custom publisher.
