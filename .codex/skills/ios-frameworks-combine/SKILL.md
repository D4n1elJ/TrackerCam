---
name: ios-frameworks-combine
description: Use when writing, reviewing, or migrating Combine publishers, subscribers, subjects, operator chains, or async bridges.
---

# Combine

Review and write Combine code for correctness, memory management, and async/await interop. Diagnose silent pipeline failures. Guide migration decisions without rewriting working code.

## Responsibility

**Owns:** Publisher/Subscriber lifecycle, operator chains, Subjects, @Published, AnyCancellable management, Schedulers, error handling in pipelines, Combine-to-async bridging, cold vs hot publishers, share/multicast.

**Does NOT own:** async/await patterns (swift-concurrency), @Observable (swift-concurrency), Timer.publish lifecycle, SwiftUI view architecture, networking layer design.

## Core Principles

1. **Combine is mature, not dead** -- Apple has not deprecated it. Do not rewrite working pipelines. Bridge at boundaries.
2. **AnyCancellable lifecycle is the #1 bug source** -- Every sink needs `[weak self]` and `store(in:)`. Every `assign(to:on:)` with `self` is a retain cycle.
3. **Completion kills the pipeline permanently** -- Once a publisher sends `.finished` or `.failure`, all subsequent `send()` calls are silently ignored. This is the most common cause of "my pipeline stopped working."
4. **Thread safety is your problem** -- `@Published` is not thread-safe. Setting it from a background thread crashes SwiftUI. Use `receive(on: RunLoop.main)` or `@MainActor`.
5. **Error handling position matters** -- `replaceError` after `flatMap` kills the outer pipeline on the first inner error. Handle errors inside `flatMap`.
6. **Cold publishers duplicate work** -- `URLSession.dataTaskPublisher` fires a new request per subscriber. Use `share()` when multiple subscribers consume one expensive publisher.

## Decision Tree: Combine vs async/await vs AsyncAlgorithms

```
Is it a one-shot operation (network call, file read)?
  Yes --> async/await

Does it need time-based operators (debounce, throttle)?
  Yes, new code --> AsyncAlgorithms (.debounce, .throttle)
  Yes, existing Combine --> keep Combine

Are you combining multiple ongoing streams?
  Yes, new code --> AsyncAlgorithms (merge, combineLatest, zip)
  Yes, existing Combine --> keep Combine

Is it existing Combine code that works?
  Yes --> keep it, bridge with .values at boundaries

Is this new code?
  Yes --> async/await + @Observable
```

### Operator Mapping: Combine to AsyncAlgorithms

| Combine | AsyncAlgorithms | Notes |
|---------|----------------|-------|
| `debounce(for:)` | `.debounce(for:)` | Emits after silence window |
| `throttle(for:latest:)` | `.throttle(for:latest:)` | Rate-limits emissions |
| `merge(with:)` | `merge(_:_:)` | Free function, 2-3 inputs |
| `combineLatest(_:)` | `combineLatest(_:_:)` | Free function, emits tuple |
| `zip(_:)` | `zip(_:_:)` | Free function, pairs 1:1 |
| `removeDuplicates()` | `.removeDuplicates()` | Consecutive equal elements |
| `prepend(_:)` | `chain(_:_:)` | Concatenates sequences |
| `collect(.byCount(n))` | `.chunks(ofCount:)` | Fixed-size batches |
| `collect(.byTime(...))` | `.chunked(by: .repeating(every:))` | Time-windowed batching |
| `buffer(size:)` | `.buffer(policy:)` | Bounded buffer with back-pressure |

Full operator reference: `references/combine-patterns.md`
Full migration guide: `references/migration-to-async.md`

## Diagnostic Checklist: Silent Pipeline Failure

When a pipeline stops producing values with no crash or error:

1. Is the `AnyCancellable` still stored? (not deallocated, Set not cleared)
2. Did anything upstream send `.finished` or `.failure`?
3. Is there a `tryMap` or throwing operator without error handling downstream?
4. Was `switchToLatest` used where the outer publisher completed?
5. Is `assign(to:on:)` used with `self` as target? (retain cycle, deinit never called)

## Quick Reference

### AnyCancellable Rules

| Pattern | Result |
|---------|--------|
| `sink { }` without `store(in:)` | Pipeline cancelled immediately |
| `sink { self.x }` without `[weak self]` | Retain cycle |
| `assign(to:on: self)` | Retain cycle -- use `assign(to: &$prop)` |
| Re-subscribing without clearing set | Old subscriptions accumulate |

### Subject Selection

| Need | Use |
|------|-----|
| Events (taps, notifications) | `PassthroughSubject` |
| State with current value | `CurrentValueSubject` |
| SwiftUI-bound property | `@Published` |
| New code, event stream | `AsyncStream` instead |
| New code, observable state | `@Observable` instead |

## Core Instructions

- Diagnose before rebuilding. Silent failures have a cause -- find it.
- Use `[weak self]` in every `sink` closure that captures `self`.
- Use `assign(to: &$prop)` instead of `assign(to:on: self)`.
- Use `receive(on: RunLoop.main)` or `@MainActor` before UI updates.
- Handle errors inside `flatMap`, not downstream of it.
- Use `share()` only when multiple subscribers consume one expensive publisher.
- Bridge with `.values` (Combine to async) or `Future` (async to Combine). Do not rewrite working pipelines.

## References

- `references/combine-patterns.md` -- Publisher/Subscriber model, operators, Subjects, @Published, error handling, Schedulers, memory management, custom publishers.
- `references/migration-to-async.md` -- Operator-to-AsyncAlgorithms mapping, Publisher.values bridging, replacing sink/Published/Subject, before/after migration patterns, when Combine is still the right choice.
