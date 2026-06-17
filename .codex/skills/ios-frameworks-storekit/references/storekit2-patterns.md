# StoreKit 2 Patterns

## Product Loading

### Basic Loading

```swift
import StoreKit

let productIDs = [
    "com.app.coins_100",
    "com.app.premium",
    "com.app.pro_monthly"
]

let products = try await Product.products(for: productIDs)
```

### Detect Missing Products

```swift
let products = try await Product.products(for: productIDs)
let loadedIDs = Set(products.map { $0.id })
let missingIDs = Set(productIDs).subtracting(loadedIDs)

if !missingIDs.isEmpty {
    // Products not configured in App Store Connect or .storekit file
    log.warning("Missing products: \(missingIDs)")
}
```

### Product Properties

```swift
product.id            // "com.app.premium"
product.displayName   // "Premium Upgrade"
product.description   // "Unlock all features"
product.displayPrice  // "$4.99"
product.price         // Decimal(4.99)
product.type          // .consumable | .nonConsumable | .autoRenewable | .nonRenewing
```

### Subscription Properties

```swift
if let sub = product.subscription {
    sub.subscriptionGroupID     // Group identifier
    sub.subscriptionPeriod      // .unit (.day/.week/.month/.year) + .value
    sub.introductoryOffer       // Free trial / intro pricing
    sub.promotionalOffers       // Array of promo offers
}
```

---

## Purchasing

### purchase(confirmIn:options:) — iOS 18.2+

Pass a UI context so the payment sheet anchors to the correct scene.

```swift
let result = try await product.purchase(confirmIn: scene)
```

With options:

```swift
let result = try await product.purchase(
    confirmIn: scene,
    options: [
        .appAccountToken(UUID())  // Associate with your user account
    ]
)
```

### SwiftUI Purchase Environment

```swift
struct BuyButton: View {
    let product: Product
    @Environment(\.purchase) private var purchase

    var body: some View {
        Button("Buy \(product.displayPrice)") {
            Task {
                let result = try await purchase(product)
                // Handle result
            }
        }
    }
}
```

### Handling PurchaseResult

```swift
switch result {
case .success(let verificationResult):
    guard let transaction = try? verificationResult.payloadValue else {
        // Verification failed — do not grant
        return
    }
    await grantEntitlement(for: transaction)
    await transaction.finish()

case .userCancelled:
    break // No action needed

case .pending:
    // Ask to Buy or payment issue — arrives via Transaction.updates when approved
    break

@unknown default:
    break
}
```

---

## Transaction Verification

### VerificationResult

```swift
switch result {
case .verified(let transaction):
    // Signed by App Store — safe to grant
    await grantEntitlement(for: transaction)
    await transaction.finish()

case .unverified(let transaction, let error):
    // Invalid signature — do not grant
    // Still finish to clear from queue
    await transaction.finish()
}
```

Verification confirms: App Store signature valid, bundle ID matches, device matches.

### Finishing Transactions

Always call `finish()`:
- After granting entitlement
- After storing receipt/ID
- For unverified transactions (clears queue)
- For refunded transactions

Unfinished transactions redeliver on next launch and re-emit from `Transaction.updates`.

---

## Transaction Listener

Start at app launch. Catches renewals, Family Sharing, Ask to Buy approvals, refunds, offer code redemptions.

```swift
func listenForTransactions() -> Task<Void, Never> {
    Task.detached { [weak self] in
        for await verificationResult in Transaction.updates {
            await self?.handleTransaction(verificationResult)
        }
    }
}
```

---

## Entitlement Tracking

### All Current Entitlements

```swift
var purchasedProductIDs: Set<String> = []

for await result in Transaction.currentEntitlements {
    guard let transaction = try? result.payloadValue else { continue }
    if transaction.revocationDate == nil {
        purchasedProductIDs.insert(transaction.productID)
    }
}
```

### Specific Product (Sequence-Based)

```swift
// Preferred — handles Family Sharing (multiple entitlements per product)
for await result in Transaction.currentEntitlements(for: productID) {
    if let transaction = try? result.payloadValue,
       transaction.revocationDate == nil {
        return true
    }
}
```

`Transaction.currentEntitlement(for:)` (singular) is deprecated in iOS 18.4. Use the sequence-based API above.

---

## Subscription Management

### Check Status for Group

```swift
let statuses = try await Product.SubscriptionInfo.status(for: groupID)

for status in statuses {
    switch status.state {
    case .subscribed:       // Active — full access
    case .expired:          // Show resubscribe / win-back
    case .inGracePeriod:    // Billing issue, access maintained — prompt payment update
    case .inBillingRetryPeriod: // Apple retrying — maintain access
    case .revoked:          // Family Sharing removed — revoke
    @unknown default: break
    }
}
```

### subscriptionStatusTask Modifier

Attach at the top of your view hierarchy. Fires on launch and on every status change.

```swift
@main
struct MyApp: App {
    @State private var tier: Tier = .free

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.subscriptionTier, tier)
                .subscriptionStatusTask(for: "pro_tier") { statuses in
                    tier = statuses.contains(where: { $0.state == .subscribed })
                        ? .pro : .free
                }
        }
    }
}
```

### Status Updates (Async Sequence)

For non-SwiftUI contexts or when you need more control than `subscriptionStatusTask`:

```swift
for await statuses in Product.SubscriptionInfo.Status.updates(for: groupID) {
    for status in statuses {
        switch status.state {
        case .subscribed: grantAccess()
        case .expired: revokeAccess()
        default: break
        }
    }
}
```

### Renewal Info

```swift
if let renewalInfo = try? status.renewalInfo.payloadValue {
    renewalInfo.willAutoRenew       // Will it renew?
    renewalInfo.autoRenewPreference // Product ID at next renewal
    renewalInfo.expirationReason    // .autoRenewDisabled | .billingError | .didNotConsentToPriceIncrease | ...
    renewalInfo.gracePeriodExpirationDate // Non-nil if in grace period
}
```

---

## StoreKit Views

### ProductView (iOS 17+)

```swift
ProductView(id: "com.app.premium")

// With custom icon
ProductView(id: "com.app.premium") {
    Image(systemName: "star.fill")
}

// Styles: .regular, .compact, .large
ProductView(id: "com.app.premium")
    .productViewStyle(.compact)
```

### StoreView (iOS 17+)

```swift
StoreView(ids: ["com.app.coins_100", "com.app.coins_500"])
```

### SubscriptionStoreView (iOS 17+)

```swift
SubscriptionStoreView(groupID: "pro_tier") {
    VStack {
        Text("Go Pro").font(.largeTitle.bold())
        Text("Unlock all features")
    }
}
.subscriptionStoreControlStyle(.prominentPicker) // .automatic | .picker | .buttons | .prominentPicker
```

### SubscriptionOfferView (iOS 18.4+)

Shows contextual offers based on the customer's relationship to the subscription group.

```swift
// Show upgrade options
SubscriptionOfferView(groupID: "pro_tier", visibleRelationship: .upgrade)

// Show win-back for expired users
SubscriptionOfferView(groupID: "pro_tier", visibleRelationship: .current)

// With detail action linking to full store
SubscriptionOfferView(id: "com.app.pro_monthly")
    .subscriptionOfferViewDetailAction { showStore = true }

// visibleRelationship options: .upgrade, .downgrade, .crossgrade, .current, .all

// With promotional icon from App Store Connect
SubscriptionOfferView(id: "com.app.pro_monthly", prefersPromotionalIcon: true)

// With custom icon and placeholder
SubscriptionOfferView(id: "com.app.pro_monthly") {
    Image("pro-icon")
        .resizable()
        .frame(width: 60, height: 60)
} placeholder: {
    Image(systemName: "photo")
}

// With app icon
SubscriptionOfferView(groupID: "pro_tier", visibleRelationship: .all, useAppIcon: true)
```

---

## AppTransaction (iOS 18.4+)

```swift
let appTransaction = try await AppTransaction.shared
appTransaction.appTransactionID   // Unique per Apple Account download (back-deployed to iOS 15)
appTransaction.originalPlatform   // .iOS, .macOS, .tvOS, .visionOS
```

Use `originalPlatform` to handle business model changes — e.g., entitle macOS purchasers who migrate to iOS.

---

## Transaction Enhancements (iOS 18.4+)

```swift
transaction.appTransactionID    // Links to app download
transaction.offerPeriod         // Subscription period for redeemed offer
transaction.advancedCommerceInfo // Advanced Commerce API data (large catalogs, creator experiences)
```

### Win-Back Patterns

```swift
if let expirationReason = renewalInfo.expirationReason {
    switch expirationReason {
    case .priceIncrease:
        showWinBackOffer()          // Offer promotional pricing
    case .billingError:
        showPaymentUpdatePrompt()   // Prompt to update payment method
    case .autoRenewDisabled:
        showResubscribePrompt()     // Highlight what they're missing
    default: break
    }
}
```

### SubscriptionStatus by Transaction ID

```swift
let status = try await Product.SubscriptionInfo.Status(transactionID: "txn_id")
```

---

## Restore Purchases

Required by App Store Review for non-consumables and subscriptions.

```swift
func restorePurchases() async {
    try? await AppStore.sync()
    await updatePurchasedProducts()
}
```

---

## Mock Store Protocol

Abstract store interactions behind a protocol for unit testing.

```swift
protocol StoreProtocol: Sendable {
    func products(for ids: [String]) async throws -> [Product]
}

final class LiveStore: StoreProtocol {
    func products(for ids: [String]) async throws -> [Product] {
        try await Product.products(for: ids)
    }
}

final class MockStore: StoreProtocol {
    var stubbedProducts: [Product] = []
    func products(for ids: [String]) async throws -> [Product] { stubbedProducts }
}
```

Inject via `StoreManager(store:)` init parameter.

---

## .storekit Configuration Setup

1. **Create** — File > New > StoreKit Configuration File. Name it `Products.storekit`.
2. **Add products** — Click "+", choose type (consumable, non-consumable, auto-renewable, non-renewing). Set product ID, reference name, price.
3. **Subscription groups** — Group auto-renewable products by tier. Set subscription period, introductory offer, promotional offers.
4. **Enable in scheme** — Edit Scheme > Run > Options > StoreKit Configuration > select file.
5. **Test** — Run in simulator. Products load instantly, purchases complete without network, subscriptions renew on accelerated schedule.

### Transaction Manager

Debug > StoreKit > Manage Transactions (while running with StoreKit config). Create transactions manually, modify properties, test edge cases.

### Sandbox Testing

1. Create sandbox tester in App Store Connect > Users and Access > Sandbox Testers.
2. Sign in on device: Settings > App Store > Sandbox Account.
3. Clear purchase history: Settings > App Store > Sandbox Account > Clear Purchase History.

---

## Manage Subscriptions

### Show Manage Subscriptions Sheet

Open the system subscription management UI from within your app.

```swift
// SwiftUI
@Environment(\.openURL) private var openURL

// Opens App Store subscription management
try await AppStore.showManageSubscriptions(in: scene)
```

### In-App Refund Request

```swift
// Present refund request sheet for a specific transaction
let status = try await transaction.beginRefundRequest(in: scene)

switch status {
case .success:
    break // Refund submitted — handle via Transaction.updates
case .userCancelled:
    break // User dismissed the sheet
@unknown default:
    break
}
```

---

## Migration from StoreKit 1

### Key Changes

| StoreKit 1 | StoreKit 2 |
|---|---|
| `SKPaymentTransactionObserver` delegate | `Transaction.updates` async sequence |
| `SKProductsRequest` + delegate | `Product.products(for:)` async |
| `SKPaymentQueue.add(payment)` | `product.purchase(confirmIn:)` async |
| `Bundle.main.appStoreReceiptURL` + server validation | `VerificationResult` automatic JWS verification |
| `SKPaymentTransaction` | `Transaction` with strong types |
| `finishTransaction(_:)` on queue | `transaction.finish()` async |
| `restoreCompletedTransactions()` | `AppStore.sync()` |

All StoreKit 1 APIs still work but receive no new features. New apps should use StoreKit 2 exclusively.
