# Server & Advanced StoreKit

## App Store Server API v2

### Set App Account Token

Associate a transaction with your server-side user account, even for purchases made outside your app (offer codes, App Store promotions).

```
PATCH /inApps/v1/transactions/{originalTransactionId}
```

```json
{
  "appAccountToken": "550e8400-e29b-41d4-a716-446655440000"
}
```

### Get App Transaction Info

```
GET /inApps/v2/appTransaction/{transactionId}
```

Returns `signedAppTransactionInfo` — a JWS containing app download metadata (version, platform, environment).

---

## Prorated Refund Handling

### Send Consumption Information v2

```
PUT /inApps/v2/transactions/consumption/{transactionId}
```

```json
{
  "customerConsented": true,
  "sampleContentProvided": false,
  "deliveryStatus": "DELIVERED",
  "refundPreference": "GRANT_PRORATED",
  "consumptionPercentage": 25000
}
```

Key fields:
- `customerConsented` (required) — user consented to send consumption data.
- `deliveryStatus` (required) — `"DELIVERED"` or `"UNDELIVERED_*"` variants.
- `refundPreference` — `"NO_REFUND"`, `"GRANT_REFUND"`, `"GRANT_PRORATED"`.
- `consumptionPercentage` — 0 to 100000 in **millipercent** (25000 = 25%). Applies to consumables, non-consumables, non-renewing subscriptions. For auto-renewable subscriptions, App Store calculates based on time remaining.

### Refund Notifications

```json
{
  "notificationType": "REFUND",
  "data": {
    "signedTransactionInfo": "...",
    "refundPercentage": 75,
    "revocationType": "REFUND_PRORATED"
  }
}
```

`revocationType` values:
- `REFUND_FULL` — 100% refund, revoke all access.
- `REFUND_PRORATED` — partial refund, revoke proportional access.
- `FAMILY_REVOKE` — Family Sharing removed.

---

## Promotional Offers with JWS v2 Signatures

### Server-Side Signature Creation

Use the open-source App Store Server Library (Swift, Java, Python, Node.js).

```swift
import AppStoreServerLibrary

let creator = PromotionalOfferV2SignatureCreator(
    privateKey: signingKey,
    keyID: keyID,
    issuerID: issuerID,
    bundleID: bundleID
)

let signature = try creator.createSignature(
    productIdentifier: "com.app.pro_monthly",
    subscriptionOfferIdentifier: "promo_winback",
    applicationUsername: nil,
    nonce: UUID(),
    timestamp: Date().timeIntervalSince1970,
    transactionIdentifier: transaction.id  // Optional but recommended
)
```

### Client-Side Purchase with Promo Offer

```swift
let result = try await product.purchase(
    confirmIn: scene,
    options: [
        .promotionalOffer(offerID: "promo_winback", signature: jwsSignature)
    ]
)
```

### SubscriptionStoreView with Promo Offer

```swift
SubscriptionStoreView(groupID: groupID)
    .subscriptionPromotionalOffer(
        for: { subscription in
            subscription.promotionalOffers.first
        },
        signature: { subscription, offer in
            try await server.signOffer(
                productID: subscription.id,
                offerID: offer.id
            )
        }
    )
```

### Custom Intro Eligibility Signature

```swift
let result = try await product.purchase(
    confirmIn: scene,
    options: [
        .introductoryOfferEligibility(signature: jwsSignature)
    ]
)
```

---

## Win-Back Offers

Show targeted offers to expired subscribers. Pair with `expirationReason` to choose the right offer.

```swift
if renewalInfo.expirationReason == .didNotConsentToPriceIncrease {
    SubscriptionOfferView(groupID: groupID, visibleRelationship: .current)
        .preferredSubscriptionOffer(offer: winBackOffer)
}
```

Expiration reasons:
- `.autoRenewDisabled` — user turned off renewal.
- `.billingError` — payment method issue.
- `.didNotConsentToPriceIncrease` — user rejected price increase.
- `.productUnavailable` — product removed.

---

## Advanced Commerce API

Supports large content catalogs, creator experiences (tipping, patronage), and subscriptions with add-ons.

### Detection

```swift
if transaction.advancedCommerceInfo != nil {
    // Transaction from Advanced Commerce API
}

if renewalInfo.advancedCommerceInfo != nil {
    // Renewal uses Advanced Commerce API
}
```

Returns `nil` for standard IAP transactions.

---

## iOS 18.4 Additions

### appTransactionID

Unique identifier for the app download, consistent across all purchases by the same Apple Account. Available on `Transaction`, `AppTransaction`, and `RenewalInfo`.

```swift
let transaction: Transaction
let appTxID = transaction.appTransactionID

let appTransaction = try await AppTransaction.shared
if let verified = try? appTransaction.payloadValue {
    let sameID = verified.appTransactionID
}

let renewalInfo: RenewalInfo
let alsoSameID = renewalInfo.appTransactionID
```

Use cases: identify individual Family Sharing members, correlate transactions server-side.

### offerPeriod

ISO 8601 duration for the active offer. Available on `Transaction.offer` and `RenewalInfo`.

```swift
if let period = transaction.offer?.period {
    // e.g. "P1M" for 1 month
}

if let period = renewalInfo.offerPeriod {
    // Period at next renewal
}
```

### advancedCommerceInfo

Present on `Transaction` and `RenewalInfo` only for Advanced Commerce API purchases. `nil` for standard IAP.

### originalPlatform on AppTransaction

```swift
let platform = appTransaction.originalPlatform
// .iOS | .macOS | .tvOS | .visionOS
// watchOS downloads report .iOS
```

### Subscription Status by Transaction ID

```swift
let status = try await Product.SubscriptionInfo.status(for: transaction.id)
```

---

## Transaction.currentEntitlement Deprecation

`Transaction.currentEntitlement(for:)` (singular, returns one value) is deprecated in iOS 18.4. It fails to surface multiple entitlements for the same product (Family Sharing scenario).

Replace with the sequence-based API:

```swift
// Deprecated
let entitlement = await Transaction.currentEntitlement(for: productID)

// Replacement
for await result in Transaction.currentEntitlements(for: productID) {
    if let transaction = try? result.payloadValue,
       transaction.revocationDate == nil {
        // Entitled
    }
}
```

---

## Offer Codes (iOS 18.2+)

Now support all product types, not just subscriptions.

```swift
// SwiftUI
.offerCodeRedemption(isPresented: $showRedeemSheet)

// UIKit
StoreKit.AppStore.presentOfferCodeRedeemSheet(in: scene)
```

New `.oneTime` payment mode for one-time offer code redemptions (iOS 17.2+).
