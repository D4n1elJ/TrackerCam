---
name: ios-frameworks-healthkit
description: Use when implementing or reviewing HealthKit authorization, samples, queries, workouts, background delivery, or HealthKit UI.
---

# HealthKit

Write, review, and govern HealthKit code for correctness, modern API usage, authorization safety, and data integrity. Report only genuine problems — do not nitpick or invent issues.

## Responsibility

**Owns:**

- HKHealthStore lifecycle and availability checks
- Authorization requests and status handling
- HKObjectType / HKSampleType / HKQuantityType / HKCategoryType / HKCorrelationType / HKCharacteristicType
- HKQuantitySample / HKCategorySample / HKCorrelation
- Query descriptors: HKSampleQueryDescriptor, HKStatisticsQueryDescriptor, HKStatisticsCollectionQueryDescriptor, HKAnchoredObjectQueryDescriptor, HKObserverQuery, HKActivitySummaryQueryDescriptor
- HKWorkout / HKWorkoutSession / HKWorkoutBuilder
- HKUnit conversions and compound units
- Background delivery registration and entitlements
- HealthKit UI (HKActivityRingView, etc.)

**Does NOT own:**

- UI views and SwiftUI layout (SwiftUI skill)
- Data persistence beyond HealthKit (SwiftData skill)
- Networking or server sync
- Location tracking or CoreLocation

## Core Principles

1. Always check availability with `HKHealthStore.isHealthDataAvailable()` before any HealthKit work.
2. Request only the types you need — granular authorization.
3. Authorization is not binary — users can deny individual types silently.
4. Use query descriptors (modern async API) over legacy HKQuery subclasses.
5. Background delivery requires entitlement + proper registration at launch.
6. Never cache authorization status — always re-check.
7. HealthKit data can change outside your app — use observer queries for live data.
8. All HealthKit work should happen off the main thread.
9. Use HKStatisticsCollectionQuery for aggregated data (daily steps, weekly averages).
10. Workouts require both start/end events and associated samples.

## Review Process

1. Check authorization handling using `references/healthkit-patterns.md` — Setup & Authorization section.
2. Check data type usage and unit conversions — Data Types and HKUnit Patterns sections.
3. Check query patterns for modern descriptor API usage — Reading Data section.
4. Check background delivery setup — Background Delivery section.
5. Check workout builder patterns — Workouts section.

If doing partial work, load only the relevant reference sections.

## Core Instructions

- Target Swift 6.2 or later, using modern Swift concurrency.
- Prefer modern query descriptors (HKSampleQueryDescriptor, etc.) over legacy HKQuery subclasses.
- Do not introduce third-party HealthKit wrappers without asking first.
- Always handle the case where authorization is denied or data is unavailable.
- Never assume read authorization was granted — HealthKit returns empty results instead of errors for denied read types.
- Use `async/await` overloads where available; avoid callback-based patterns in new code.
- Register observer queries at every app launch for background delivery to work.

## Red Flags

| Pattern | Problem | Fix |
|---|---|---|
| Missing `isHealthDataAvailable()` check | Crashes on iPad or unsupported devices | Guard with availability check before any HKHealthStore use |
| Caching authorization status in a property | Status can change in Settings at any time | Re-check `authorizationStatus(for:)` before each operation |
| Using legacy `HKSampleQuery` in new code | Callback-based, harder to compose | Use `HKSampleQueryDescriptor` with `async/await` |
| Requesting all types at once | Users distrust broad permission requests | Request only types needed for the current feature |
| Assuming read authorization result | HealthKit never reveals read denial | Handle empty results gracefully — never treat empty as "no data exists" |
| Background delivery without observer query at launch | Delivery silently stops working | Register observer queries in `application(_:didFinishLaunchingWithOptions:)` or App init |
| HealthKit queries on main thread | Blocks UI, watchdog kills app | Dispatch all queries to background queues or use async descriptors |
| Saving workout without associated samples | Workout appears empty in Health app | Associate route, heart rate, and energy samples with the workout |
| Hardcoded HKUnit without conversion | Locale mismatch, wrong display values | Use `HKUnit` conversions and respect user's preferred units |
| Missing Info.plist usage descriptions | App rejected by App Review | Add `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` |

## Pre-Ship Checklist

- [ ] `HKHealthStore.isHealthDataAvailable()` checked before any HealthKit access
- [ ] Authorization requests are granular — only types needed for the feature
- [ ] Read authorization denial handled gracefully (empty results, not errors)
- [ ] All queries use modern descriptor API (not legacy HKQuery subclasses)
- [ ] Background delivery entitlement added if using background delivery
- [ ] Observer queries registered at every app launch
- [ ] Info.plist contains `NSHealthShareUsageDescription` and/or `NSHealthUpdateUsageDescription`
- [ ] HKUnit conversions are correct for all quantity types
- [ ] Workouts have associated samples (energy, distance, heart rate as appropriate)
- [ ] No HealthKit work happens on the main thread
- [ ] Authorization status is never cached — always re-checked
- [ ] Error handling covers store unavailability, authorization denial, and query failures

## Output Format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules above but make the changes directly instead of returning a findings report.

## References

- `references/healthkit-patterns.md` — Setup, authorization, data types, query descriptors, background delivery, workouts, units, predicates.
