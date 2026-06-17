# Migration Patterns

> Schema versioning, lightweight migration, custom migration with NSMigrationManager, and testing strategies for Core Data.

## Model Versioning

Core Data uses `.xcdatamodeld` bundles (versioned data model) to track schema evolution. Each version is a `.xcdatamodel` file inside the bundle.

### Adding a new model version

1. Select the `.xcdatamodeld` in Xcode.
2. Editor > Add Model Version.
3. Make schema changes in the new version only. Never edit a shipped version.
4. Set the new version as current: File Inspector > Versioned Core Data Model > Current Model Version.

### Version identifiers

Each `.xcdatamodel` can carry a version identifier (Inspector > Versioned Core Data Model > Model Version Identifier). The persistent store records which version created it. On next launch, Core Data compares the store's metadata against the app's current model to decide if migration is needed.

Check programmatically:

```swift
let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
    ofType: NSSQLiteStoreType,
    at: storeURL,
    options: nil
)
let storeVersionIDs = metadata[NSStoreModelVersionIdentifiersKey] as? [String]
let appVersionIDs = currentModel.versionIdentifiers
```

## Lightweight Migration (Automatic)

Lightweight migration requires no mapping model and no code. Core Data infers the changes automatically.

### Enable it

```swift
let description = NSPersistentStoreDescription()
description.shouldMigrateStoreAutomatically = true
description.shouldInferMappingModelAutomatically = true
container.persistentStoreDescriptions = [description]
```

Or when adding a store manually:

```swift
let options: [String: Any] = [
    NSMigratePersistentStoresAutomaticallyOption: true,
    NSInferMappingModelAutomaticallyOption: true
]
try coordinator.addPersistentStore(
    ofType: NSSQLiteStoreType,
    configurationName: nil,
    at: storeURL,
    options: options
)
```

### What lightweight handles

| Change | Supported | Notes |
|---|---|---|
| Add optional attribute | Yes | Existing rows get NULL |
| Add required attribute with default | Yes | Must set default in model editor |
| Remove attribute | Yes | Column remains on disk, ignored |
| Rename attribute | Yes | Set Renaming Identifier in Inspector |
| Rename entity | Yes | Set Renaming Identifier in Inspector |
| Add optional relationship | Yes | |
| Add entity | Yes | |
| Remove entity | Yes | Table remains on disk |
| Change optional to required | No | Existing NULLs violate constraint |
| Change attribute type | No | |
| Complex relationship restructuring | No | |
| Data transformation | No | |

### What lightweight does NOT handle

If any of these apply, you need a custom migration:

- Changing attribute types (String to Date, Int to String).
- Making an optional attribute required when existing rows contain NULLs.
- Splitting one entity into multiple entities.
- Merging multiple entities into one.
- Complex relationship changes (changing cardinality, restructuring inverse relationships).
- Data transformation (parsing a full name into first/last, converting date formats).

## Custom Migration with NSMigrationManager

When lightweight migration cannot handle the change, use a mapping model and optionally a custom migration policy.

### Step 1: Create a mapping model

File > New > Mapping Model. Select the source model version and the destination model version. Xcode generates a `.xcmappingmodel` file with default attribute mappings.

### Step 2: Create a custom migration policy (if needed)

Subclass `NSEntityMigrationPolicy` to transform data during migration:

```swift
class SplitNameMigrationPolicy: NSEntityMigrationPolicy {
    override func createDestinationInstances(
        forSource sInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        let destination = NSEntityDescription.insertNewObject(
            forEntityName: mapping.destinationEntityName ?? "",
            into: manager.destinationContext
        )

        // Copy unchanged attributes
        destination.setValue(sInstance.value(forKey: "id"), forKey: "id")
        destination.setValue(sInstance.value(forKey: "email"), forKey: "email")

        // Transform: split fullName into firstName + lastName
        if let fullName = sInstance.value(forKey: "fullName") as? String {
            let parts = fullName.split(separator: " ", maxSplits: 1)
            destination.setValue(String(parts.first ?? ""), forKey: "firstName")
            destination.setValue(parts.count > 1 ? String(parts.last!) : "", forKey: "lastName")
        }

        manager.associate(
            sourceInstance: sInstance,
            withDestinationInstance: destination,
            for: mapping
        )
    }
}
```

Set the policy class name in the mapping model Inspector for the relevant entity mapping.

### Step 3: Run the migration

For multi-step or heavy migrations, run `NSMigrationManager` explicitly before opening the store:

```swift
func migrateStoreIfNeeded(at storeURL: URL) throws {
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
        ofType: NSSQLiteStoreType, at: storeURL, options: nil
    )

    guard !currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) else {
        return  // No migration needed
    }

    guard let sourceModel = NSManagedObjectModel.mergedModel(
        from: [.main], forStoreMetadata: metadata
    ) else {
        throw MigrationError.sourceModelNotFound
    }

    guard let mappingModel = NSMappingModel(
        from: [.main], forSourceModel: sourceModel, destinationModel: currentModel
    ) else {
        throw MigrationError.mappingModelNotFound
    }

    let manager = NSMigrationManager(
        sourceModel: sourceModel, destinationModel: currentModel
    )

    let tempURL = storeURL.deletingLastPathComponent()
        .appendingPathComponent("migration_temp.sqlite")

    try manager.migrateStore(
        from: storeURL,
        type: NSSQLiteStoreType,
        options: nil,
        mapping: mappingModel,
        to: tempURL,
        type: NSSQLiteStoreType,
        options: nil
    )

    // Replace old store with migrated store
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: currentModel)
    try coordinator.replacePersistentStore(
        at: storeURL, destinationOptions: nil,
        withPersistentStoreFrom: tempURL, sourceOptions: nil,
        type: NSSQLiteStoreType
    )

    try? FileManager.default.removeItem(at: tempURL)
}
```

## Progressive Migration (Multi-Step)

When the store could be several versions behind the current model, chain migrations through each intermediate version:

```swift
let modelVersions: [(NSManagedObjectModel, NSMappingModel?)] = [
    // (destinationModel, mappingModel from previous version)
    (modelV2, mappingV1toV2),
    (modelV3, mappingV2toV3),
    (modelV4, nil)  // nil = lightweight inferred
]
```

Walk the chain: check store metadata, find the matching source model, migrate one step, repeat until current.

## Core Data + CloudKit Migration Constraints

`NSPersistentCloudKitContainer` imposes additional constraints on schema changes:

| Constraint | Reason |
|---|---|
| Cannot delete attributes or entities | CloudKit schema is additive-only after deployment |
| Cannot rename attributes | CloudKit field names are immutable |
| Cannot make optional required | Existing cloud records may have NULLs |
| New attributes must be optional | CloudKit records created before the change have no value |
| Unique constraints not supported | CloudKit does not enforce uniqueness |
| Relationships must be optional | Eventual consistency means related objects may not exist yet |
| Deny delete rule not supported | Related objects may arrive after deletion |

For CloudKit projects, prefer additive-only schema changes. If a breaking change is unavoidable, you may need a new CloudKit container or a data migration strategy that copies records.

### History tracking for CloudKit sync

Required for `NSPersistentCloudKitContainer`:

```swift
let description = container.persistentStoreDescriptions.first!
description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
description.setOption(
    true as NSNumber,
    forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
)
```

## Testing Migrations

### Why simulator testing is not enough

The iOS Simulator deletes the database on each app rebuild. Schema mismatches that crash 100% of real-device users are invisible in the simulator. Migration testing on a real device or with a production database copy is mandatory before shipping.

### Unit test: lightweight migration

```swift
@Test func lightweightMigrationV1toV2Succeeds() throws {
    // 1. Create a store using the old model
    let oldModel = try loadModel(named: "Model", version: "Model")  // v1
    let storeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".sqlite")
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
    try coordinator.addPersistentStore(
        ofType: NSSQLiteStoreType, configurationName: nil,
        at: storeURL, options: nil
    )

    // 2. Seed old data
    let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    let entity = NSEntityDescription.insertNewObject(forEntityName: "User", into: context)
    entity.setValue("test-id", forKey: "id")
    entity.setValue("Ada Lovelace", forKey: "name")
    try context.save()

    // 3. Close old store
    for store in coordinator.persistentStores {
        try coordinator.remove(store)
    }

    // 4. Reopen with new model + migration options
    let newModel = try loadModel(named: "Model", version: "Model 2")  // v2
    let newCoordinator = NSPersistentStoreCoordinator(managedObjectModel: newModel)
    let options: [String: Any] = [
        NSMigratePersistentStoresAutomaticallyOption: true,
        NSInferMappingModelAutomaticallyOption: true
    ]
    try newCoordinator.addPersistentStore(
        ofType: NSSQLiteStoreType, configurationName: nil,
        at: storeURL, options: options
    )

    // 5. Verify data survived
    let newContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    newContext.persistentStoreCoordinator = newCoordinator
    let request = NSFetchRequest<NSManagedObject>(entityName: "User")
    let results = try newContext.fetch(request)
    #expect(results.count == 1)
    #expect(results.first?.value(forKey: "name") as? String == "Ada Lovelace")

    // 6. Verify new attribute exists (e.g. optional email added in v2)
    #expect(results.first?.entity.attributesByName.keys.contains("email") == true)

    // Cleanup
    try? FileManager.default.removeItem(at: storeURL)
}
```

### Manual testing checklist

Before shipping any schema change:

1. Install the old version on a real device.
2. Create representative data (cover relationships, edge cases, large counts).
3. Install the new version over it (do not delete the app).
4. Verify: app launches, data is intact, new features work.
5. Check migration performance with a large dataset (1000+ rows per entity).
6. Verify relationships load correctly.

### Testing custom migration policies

```swift
@Test func customPolicySplitsNameCorrectly() throws {
    // Create store with v1 model (has fullName)
    // Seed: fullName = "Ada Lovelace"
    // Migrate to v2 model (has firstName, lastName) using mapping model
    // Verify: firstName == "Ada", lastName == "Lovelace"
}
```

## Migration Decision Matrix

| Change | Migration type | Notes |
|---|---|---|
| Add optional attribute | Lightweight | Safest change |
| Add required attribute with stored default | Lightweight | Set default in model editor |
| Remove attribute | Lightweight | Column stays on disk |
| Rename attribute | Lightweight | Set Renaming Identifier |
| Change attribute type | Custom | Need NSEntityMigrationPolicy |
| Make optional required | Custom | Must backfill NULLs |
| Split entity | Custom | Need mapping model |
| Merge entities | Custom | Need mapping model |
| Add entity | Lightweight | |
| Remove entity | Lightweight | Table stays on disk |
| Add optional relationship | Lightweight | |
| Complex relationship change | Custom | |

## Common Failure Scenarios

### 1. "The model used to open the store is incompatible"

The store was created with a different model version and no migration options are set.

Fix: enable lightweight migration options, or provide a mapping model for the version transition.

### 2. Migration works in simulator, crashes on device

Simulator deletes the database on rebuild. The old schema never exists to migrate from.

Fix: test on a real device with existing data, or use a unit test that creates an old-schema store on disk.

### 3. Required attribute added without default

Existing rows have no value for the new attribute. Lightweight migration fails.

Fix: add the attribute as optional, or set a default value in the model editor.

### 4. CloudKit schema change rejected

CloudKit does not allow destructive schema changes after deployment.

Fix: use additive-only changes. New attributes must be optional.

### 5. Store deletion as "migration strategy"

Deleting the store file removes all user data. Users uninstall the app and leave negative reviews.

Fix: invest in proper migration. Gate any store deletion behind `#if DEBUG`. Document the decision if store deletion is truly unavoidable.
