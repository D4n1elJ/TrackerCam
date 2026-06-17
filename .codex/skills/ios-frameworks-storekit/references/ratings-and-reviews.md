# Ratings and Reviews (HIG)

## Core Rule

Ask at the right moment, sparingly, and never interfere with the user's task. A well-timed prompt gets better ratings than a frequent one.

## SKStoreReviewController

```swift
import StoreKit

// SwiftUI
@Environment(\.requestReview) private var requestReview

Button("Rate") { requestReview() }

// UIKit
if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
    SKStoreReviewController.requestReview(in: scene)
}
```

### System Constraints
- **iOS limits display to 3 times per 365-day period** per app
- The system decides whether to actually show the prompt
- You call it, but Apple controls presentation
- In development, the prompt always appears

## When to Ask

### Good Moments (User Just Succeeded)
- After completing a meaningful task ("Workout complete!")
- After a positive outcome (export finished, goal reached)
- After using the app N times successfully (e.g., 5th session)
- After a natural pause in workflow

### Bad Moments (Never Ask Here)
- First launch
- During onboarding
- After an error or crash
- While the user is mid-task (editing, recording, composing)
- Immediately after a purchase
- When the app is in the background

## Timing Strategy

```swift
@AppStorage("sessionCount") private var sessionCount = 0
@AppStorage("lastReviewRequestDate") private var lastReviewDate: Double = 0

func checkForReviewPrompt() {
    sessionCount += 1

    let daysSinceLastRequest = Date().timeIntervalSince1970 - lastReviewDate
    let minimumDaysBetween: Double = 120 * 86400  // 120 days

    guard sessionCount >= 5,
          daysSinceLastRequest > minimumDaysBetween else { return }

    // Delay slightly — don't interrupt the moment
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        requestReview()
        lastReviewDate = Date().timeIntervalSince1970
    }
}
```

## Custom "Enjoying the App?" Pre-Screen

Some apps show a custom prompt first to filter unhappy users to support instead of the App Store. **Apple discourages this** — it violates guideline 1.1.7 if it gates the review prompt.

**Don't do this:**
```
"Enjoying the app?" → Yes → Show review prompt
                    → No  → Send to support
```

**Instead:** Just call `requestReview()` at a good moment. If users are unhappy, provide a visible feedback/support option elsewhere in the app.

## What NOT to Do

- Don't build custom star-rating UI that mimics the system prompt
- Don't offer incentives for reviews (App Store guideline violation)
- Don't deep-link to the App Store review page to bypass the 3/year limit
- Don't show a custom "rate us" alert — use the system API
- Don't ask during onboarding or first session
- Don't ask after a negative experience
