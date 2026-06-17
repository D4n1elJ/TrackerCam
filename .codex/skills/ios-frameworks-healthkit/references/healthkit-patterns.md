# HealthKit Patterns Reference

## Setup & Authorization

### Availability Check

```swift
guard HKHealthStore.isHealthDataAvailable() else {
    // HealthKit not available (iPad, unsupported device)
    return
}

let store = HKHealthStore()
```

### Authorization Request

```swift
let typesToShare: Set<HKSampleType> = [
    HKQuantityType(.bodyMass),
    HKCategoryType(.sleepAnalysis),
]

let typesToRead: Set<HKObjectType> = [
    HKQuantityType(.stepCount),
    HKQuantityType(.heartRate),
    HKQuantityType(.bodyMass),
    HKCategoryType(.sleepAnalysis),
    HKCharacteristicType(.dateOfBirth),
]

try await store.requestAuthorization(toShare: typesToShare, read: typesToRead)
```

### Type Identifiers

**HKQuantityTypeIdentifier** — numeric measurements:
- `.stepCount`, `.heartRate`, `.bodyMass`, `.activeEnergyBurned`
- `.distanceWalkingRunning`, `.bloodGlucose`, `.bodyTemperature`
- `.oxygenSaturation`, `.restingHeartRate`, `.vo2Max`
- `.height`, `.bodyFatPercentage`, `.respiratoryRate`

**HKCategoryTypeIdentifier** — enum-based values:
- `.sleepAnalysis`, `.menstrualFlow`, `.appetiteChanges`
- `.mindfulSession`, `.handwashingEvent`

**HKCorrelationTypeIdentifier** — grouped samples:
- `.bloodPressure` (systolic + diastolic)
- `.food` (dietary nutrients)

**HKCharacteristicTypeIdentifier** — read-only user data:
- `.dateOfBirth`, `.biologicalSex`, `.bloodType`, `.fitzpatrickSkinType`

### Authorization Status

```swift
// Write authorization — you can check this
let status = store.authorizationStatus(for: HKQuantityType(.bodyMass))
switch status {
case .notDetermined: // Not yet asked
case .sharingDenied: // User denied write access
case .sharingAuthorized: // User granted write access
@unknown default: break
}

// Read authorization — NEVER exposed by HealthKit
// You cannot determine if read access was granted or denied.
// HealthKit returns empty results for denied read types.
```

### Info.plist Keys

- `NSHealthShareUsageDescription` — required when reading HealthKit data
- `NSHealthUpdateUsageDescription` — required when writing HealthKit data

---

## Data Types

| Type | Description | Example |
|---|---|---|
| `HKQuantityType` | Numeric measurements | Steps, heart rate, weight |
| `HKCategoryType` | Enum-based values | Sleep analysis, menstrual flow |
| `HKCorrelationType` | Grouped samples | Blood pressure (systolic + diastolic) |
| `HKWorkoutType` | Workout sessions | Running, cycling, swimming |
| `HKCharacteristicType` | Read-only user data | Date of birth, blood type, biological sex |

### HKUnit Patterns

```swift
HKUnit.count()                              // Steps, events
HKUnit.meter()                              // Distance
HKUnit.gramUnit(with: .kilo)                // Weight (kg)
HKUnit.pound()                              // Weight (lbs)
HKUnit.count().unitDivided(by: .minute())   // Heart rate (bpm)
HKUnit.kilocalorie()                        // Energy
HKUnit.percent()                            // SpO2, body fat percentage
HKUnit.degreeCelsius()                      // Temperature
HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter()) // Blood glucose (mmol/L)
HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)) // Blood glucose (mg/dL)
HKUnit.minute()                             // Duration
HKUnit.second()                             // Duration
```

---

## Saving Data

```swift
let store = HKHealthStore()

// Quantity sample (e.g., body mass)
let type = HKQuantityType(.bodyMass)
let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 75.0)
let sample = HKQuantitySample(
    type: type,
    quantity: quantity,
    start: Date(),
    end: Date()
)
try await store.save(sample)

// Correlation (e.g., blood pressure)
let systolicType = HKQuantityType(.bloodPressureSystolic)
let diastolicType = HKQuantityType(.bloodPressureDiastolic)
let systolic = HKQuantitySample(
    type: systolicType,
    quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 120),
    start: Date(), end: Date()
)
let diastolic = HKQuantitySample(
    type: diastolicType,
    quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 80),
    start: Date(), end: Date()
)
let bloodPressure = HKCorrelation(
    type: HKCorrelationType(.bloodPressure),
    start: Date(), end: Date(),
    objects: [systolic, diastolic]
)
try await store.save(bloodPressure)
```

---

## Reading Data — Modern Query Descriptors (iOS 15.4+)

### Sample Query

```swift
let descriptor = HKSampleQueryDescriptor(
    predicates: [.quantitySample(type: HKQuantityType(.stepCount))],
    sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
    limit: 10
)
let results = try await descriptor.result(for: store)

for sample in results {
    let steps = sample.quantity.doubleValue(for: .count())
    print("\(sample.startDate): \(steps) steps")
}
```

### Statistics Query (Single Aggregate)

```swift
let startOfDay = Calendar.current.startOfDay(for: .now)

let statsDescriptor = HKStatisticsQueryDescriptor(
    predicate: .quantitySample(
        type: HKQuantityType(.stepCount),
        predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: .now)
    ),
    options: .cumulativeSum
)
let stats = try await statsDescriptor.result(for: store)
let steps = stats?.sumQuantity()?.doubleValue(for: .count())
```

### Statistics Collection (Time-Bucketed Aggregates)

```swift
let startOfDay = Calendar.current.startOfDay(for: .now)

let collectionDescriptor = HKStatisticsCollectionQueryDescriptor(
    predicate: .quantitySample(type: HKQuantityType(.stepCount)),
    options: .cumulativeSum,
    anchorDate: startOfDay,
    intervalComponents: DateComponents(day: 1)
)
let collection = try await collectionDescriptor.result(for: store)

collection.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
    let steps = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
    print("\(stats.startDate): \(steps) steps")
}
```

### Anchored Object Query (Incremental Updates)

```swift
let anchoredDescriptor = HKAnchoredObjectQueryDescriptor(
    predicates: [.quantitySample(type: HKQuantityType(.heartRate))],
    anchor: savedAnchor
)
let anchoredResult = try await anchoredDescriptor.result(for: store)

let newSamples = anchoredResult.addedSamples
let deletedObjects = anchoredResult.deletedObjects
let newAnchor = anchoredResult.newAnchor
// Persist newAnchor for next incremental fetch
```

### Observer Query (Background Notifications)

```swift
let observerQuery = HKObserverQuery(
    queryDescriptors: [
        HKQueryDescriptor(sampleType: HKQuantityType(.stepCount))
    ]
) { query, types, handler, error in
    if let error {
        print("Observer error: \(error)")
        handler()
        return
    }
    // Fetch new data here, then signal completion
    handler()
}
store.execute(observerQuery)
```

### Activity Summary Query

```swift
let calendar = Calendar.current
let components = calendar.dateComponents([.year, .month, .day], from: .now)

let summaryDescriptor = HKActivitySummaryQueryDescriptor(
    predicate: HKQuery.predicate(forActivitySummariesBetweenStart: startComponents, end: components)
)
let summaries = try await summaryDescriptor.result(for: store)

for summary in summaries {
    let activeEnergy = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
    let exerciseMinutes = summary.appleExerciseTime.doubleValue(for: .minute())
    let standHours = summary.appleStandHours.doubleValue(for: .count())
}
```

---

## Background Delivery

```swift
// 1. Add HealthKit Background Delivery entitlement in Xcode
// 2. Register at every app launch (AppDelegate or App init)

func enableBackgroundDelivery() {
    let store = HKHealthStore()
    let stepType = HKQuantityType(.stepCount)

    store.enableBackgroundDelivery(for: stepType, frequency: .hourly) { success, error in
        if let error {
            print("Background delivery failed: \(error)")
        }
    }

    // Observer query MUST be registered at every launch
    let observerQuery = HKObserverQuery(
        queryDescriptors: [
            HKQueryDescriptor(sampleType: stepType)
        ]
    ) { query, types, handler, error in
        // Process new data
        handler()
    }
    store.execute(observerQuery)
}
```

**Frequency options:**
- `.immediate` — as soon as new data is available
- `.hourly` — at most once per hour
- `.daily` — at most once per day

**Requirements:**
- HealthKit Background Delivery entitlement must be enabled
- Observer query must be registered at every app launch
- App is woken in the background briefly to process updates
- Call the completion handler promptly to avoid being throttled

---

## Workouts

### Save Workout (iOS)

```swift
let workout = HKWorkout(
    activityType: .running,
    start: startDate,
    end: endDate,
    duration: endDate.timeIntervalSince(startDate),
    totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 300),
    totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000),
    metadata: nil
)
try await store.save(workout)

// Associate samples with the workout
let heartRateSamples: [HKQuantitySample] = // ... collected during workout
try await store.addSamples(heartRateSamples, to: workout)
```

### Workout Builder Pattern

```swift
let config = HKWorkoutConfiguration()
config.activityType = .running
config.locationType = .outdoor

let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
try await builder.beginCollection(at: startDate)

// Add samples during workout
let heartRateSample = HKQuantitySample(
    type: HKQuantityType(.heartRate),
    quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 145),
    start: sampleDate, end: sampleDate
)
try await builder.addSamples([heartRateSample])

// Finish workout
try await builder.endCollection(at: endDate)
let workout = try await builder.finishWorkout()
```

### Workout Session (watchOS)

```swift
let config = HKWorkoutConfiguration()
config.activityType = .running
config.locationType = .outdoor

let session = try HKWorkoutSession(healthStore: store, configuration: config)
let builder = session.associatedWorkoutBuilder()
builder.dataSource = HKLiveWorkoutDataSource(
    healthStore: store,
    workoutConfiguration: config
)

session.startActivity(with: Date())
try await builder.beginCollection(at: Date())

// ... workout in progress ...

session.end()
try await builder.endCollection(at: Date())
let workout = try await builder.finishWorkout()
```

---

## Category Samples

```swift
// Sleep analysis
let sleepType = HKCategoryType(.sleepAnalysis)
let sample = HKCategorySample(
    type: sleepType,
    value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    start: bedtime,
    end: wakeTime
)
try await store.save(sample)

// Sleep analysis values:
// .inBed, .asleepUnspecified, .awake
// .asleepCore, .asleepDeep, .asleepREM (iOS 16+)

// Mindful session
let mindfulType = HKCategoryType(.mindfulSession)
let mindfulSample = HKCategorySample(
    type: mindfulType,
    value: HKCategoryValue.notApplicable.rawValue,
    start: sessionStart,
    end: sessionEnd
)
try await store.save(mindfulSample)
```

---

## Characteristic Data (Read-Only)

```swift
do {
    let dateOfBirth = try store.dateOfBirthComponents()
    let biologicalSex = try store.biologicalSex().biologicalSex
    let bloodType = try store.bloodType().bloodType
    let skinType = try store.fitzpatrickSkinType().skinType
} catch {
    // User has not set this data or denied access
}
```

---

## Predicate Helpers

```swift
// Time-based predicates
HKQuery.predicateForSamples(
    withStart: startDate,
    end: endDate,
    options: .strictStartDate
)

// Source-based predicates
HKQuery.predicateForObjects(from: Set<HKSource>)
HKQuery.predicateForObjects(from: HKDevice)

// Workout predicates
HKQuery.predicateForWorkouts(with: .running)
HKQuery.predicateForWorkouts(with: .greaterThan, duration: 1800) // > 30 min
HKQuery.predicateForWorkouts(with: .greaterThan, totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000))

// Combine predicates
let compound = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, typePredicate])
```

---

## Common Patterns

### Preferred Units

```swift
// Get the user's preferred unit for a quantity type
let preferredUnits = try await store.preferredUnits(for: [HKQuantityType(.bodyMass)])
if let unit = preferredUnits[HKQuantityType(.bodyMass)] {
    let value = sample.quantity.doubleValue(for: unit)
}
```

### Delete Samples

```swift
// Delete specific objects
try await store.delete(sample)

// Delete by predicate (only samples your app wrote)
let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
try await store.deleteObjects(of: HKQuantityType(.bodyMass), predicate: predicate)
```

### Source Queries

```swift
// Find which apps/devices contributed data for a type
let sourceDescriptor = HKSourceQueryDescriptor(
    predicate: .quantitySample(type: HKQuantityType(.stepCount))
)
let sources = try await sourceDescriptor.result(for: store)
for source in sources {
    print("\(source.name) — \(source.bundleIdentifier)")
}
```
