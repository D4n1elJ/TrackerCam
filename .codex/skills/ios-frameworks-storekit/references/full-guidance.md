# StoreKit

Review and write StoreKit 2 in-app purchase code for correctness, modern API usage, and App Store compliance.

## Responsibility

**Owns:** Product loading, purchase flows, transaction verification, transaction listeners, entitlement tracking, subscription status, StoreKit Views, restore purchases, .storekit configuration, refund handling, offer codes.

**Does NOT own:** App Store Connect product configuration, pricing strategy, server-side receipt validation infrastructure, UI layout for store screens (see swiftui-patterns), app architecture patterns (see ios-architecture).

## Core Principles

1. **Testing-first workflow.** Create `.storekit` configuration file before writing any purchase code. Product IDs validated in Xcode, not at runtime.
2. **Centralized StoreManager.** All purchase logic flows through a single `@MainActor` `ObservableObject`. No scattered `product.purchase()` calls in views.
3. **Always verify transactions.** Check `VerificationResult` before granting entitlements. Never trust unverified transactions.
4. **Always finish transactions.** Call `transaction.finish()` after processing every transaction, including unverified and refunded ones. Unfinished transactions requeue on next launch.
5. **Listen for updates at launch.** `Transaction.updates` must run from app startup. It catches renewals, Family Sharing, Ask to Buy approvals, refunds, and offer code redemptions.
6. **Restore is required.** Apps with non-consumable or subscription IAP must provide a visible restore mechanism. Use `AppStore.sync()`.
7. **Use `purchase(confirmIn:options:)`.** Pass the UI context (scene or SwiftUI environment) so the payment sheet anchors correctly.

## Decision Tree

### Which Purchase UI?

```
Custom store screen?
├── Yes → Load products via Product.products(for:), build custom UI
│   └── Purchase via StoreManager.purchase(_:confirmIn:)
│
└── No → Use StoreKit Views
    ├── Single product → ProductView(id:)
    ├── Multiple products → StoreView(ids:)
    ├── Subscription group → SubscriptionStoreView(groupID:)
    └── Upsell / win-back → SubscriptionOfferView(id:) with visibleRelationship
```

## Red Flags

| Anti-Pattern | Problem | Fix |
|---|---|---|
| No `.storekit` config file | Can't test locally, product ID typos found at runtime | Create config before writing code |
| Scattered `product.purchase()` in views | Duplicated verification, inconsistent state, missed finish() | Route all purchases through StoreManager |
| Missing `transaction.finish()` | Transaction redelivered every launch, queue grows | Always finish after granting/revoking |
| Skipping `VerificationResult` check | Grants entitlements for fraudulent or tampered transactions | Always switch on `.verified` / `.unverified` |
| No `Transaction.updates` listener | Misses renewals, Family Sharing, Ask to Buy, refunds | Start listener at app launch |
| No restore button | App Store rejection | Add visible "Restore Purchases" in settings |
| `Transaction.currentEntitlement(for:)` | Deprecated iOS 18.4 — returns single value, misses Family Sharing | Use `Transaction.currentEntitlements(for:)` (sequence) |
| Checking entitlements without revocation check | Grants access for refunded purchases | Filter `transaction.revocationDate == nil` |

## Testing-First Workflow

```
.storekit config → Local testing → Production code → Unit tests → Sandbox testing
```

1. **Create `.storekit` file** — File > New > StoreKit Configuration File. Add all products with IDs, prices, subscription groups.
2. **Enable in scheme** — Edit Scheme > Run > Options > StoreKit Configuration.
3. **Test in simulator** — Verify products load, purchases complete, subscriptions renew (accelerated).
4. **Write StoreManager** — Implement against validated product configuration.
5. **Unit test with protocol** — Abstract store behind `StoreProtocol`, inject `MockStore` in tests.
6. **Sandbox test** — Create sandbox Apple ID in App Store Connect, test on device.

## StoreManager Architecture

```swift
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit { transactionListener?.cancel() }

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {
            // Log and surface to UI
        }
    }

    func purchase(_ product: Product, confirmIn scene: UIWindowScene) async throws -> Bool {
        let result = try await product.purchase(confirmIn: scene)
        switch result {
        case .success(let verification):
            guard let transaction = try? verification.payloadValue else { return false }
            await grantEntitlement(for: transaction)
            await transaction.finish()
            await updatePurchasedProducts()
            return true
        case .userCancelled:
            return false
        case .pending:
            return false // Arrives via Transaction.updates when approved
        @unknown default:
            return false
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handleTransaction(result)
            }
        }
    }

    private func handleTransaction(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? result.payloadValue else { return }
        if transaction.revocationDate != nil {
            await revokeEntitlement(for: transaction.productID)
        } else {
            await grantEntitlement(for: transaction)
        }
        await transaction.finish()
        await updatePurchasedProducts()
    }

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               transaction.revocationDate == nil {
                purchased.insert(transaction.productID)
            }
        }
        purchasedProductIDs = purchased
    }
}
```

## Mock Store Protocol for Unit Testing

```swift
protocol StoreProtocol: Sendable {
    func products(for ids: [String]) async throws -> [Product]
}

final class MockStore: StoreProtocol {
    var stubbedProducts: [Product] = []

    func products(for ids: [String]) async throws -> [Product] {
        stubbedProducts
    }
}
```

Test purchase logic by injecting `MockStore` into `StoreManager` via init parameter.

## Pre-Ship Checklist

- [ ] `.storekit` configuration file exists with all products
- [ ] Centralized StoreManager — no scattered purchase calls
- [ ] `Transaction.updates` listener starts at app launch
- [ ] Every transaction path calls `transaction.finish()`
- [ ] `VerificationResult` checked before granting entitlements
- [ ] Revoked transactions (`revocationDate != nil`) revoke access
- [ ] Restore Purchases button visible in settings
- [ ] `purchase(confirmIn:options:)` used with UI context
- [ ] Subscription status tracked via `subscriptionStatusTask` or manual polling
- [ ] Tested: successful purchase, cancel, restore, renewal, expiration, refund
- [ ] Sandbox tested on real device with sandbox Apple ID

## References

- `references/storekit2-patterns.md` — Product loading, purchasing, transaction verification, subscription management, StoreKit Views, testing setup
- `references/server-and-advanced.md` — App Store Server API v2, prorated refunds, promotional offers, win-back offers, Advanced Commerce API, iOS 18.4 additions
