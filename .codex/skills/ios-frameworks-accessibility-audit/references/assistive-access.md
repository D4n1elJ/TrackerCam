# Assistive Access

Assistive Access (iOS 17+) provides a simplified, high-contrast UI mode for users with cognitive disabilities. Apps can provide a dedicated Assistive Access experience using a separate scene.

## SwiftUI Scene

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        // Dedicated simplified UI for Assistive Access mode
        AssistiveAccess {
            SimplifiedContentView()
        }
    }
}
```

When Assistive Access is active, the system shows the `AssistiveAccess` scene instead of the main `WindowGroup`. Design this scene with:
- Larger touch targets (minimum 60pt)
- Simplified navigation (flat hierarchy, no deep nesting)
- Reduced cognitive load (fewer options per screen)
- Clear, simple labels

## Runtime Detection

```swift
struct AdaptiveView: View {
    @Environment(\.accessibilityAssistiveAccessEnabled) private var assistiveAccessEnabled

    var body: some View {
        if assistiveAccessEnabled {
            SimplifiedLayout()
        } else {
            FullLayout()
        }
    }
}
```

## Navigation Icons

Provide custom icons for the Assistive Access home screen:

```swift
SimplifiedContentView()
    .assistiveAccessNavigationIcon(systemImage: "heart.fill")
```

## Info.plist Keys

| Key | Type | Purpose |
|-----|------|---------|
| `UISupportsAssistiveAccess` | Boolean | Declares app supports Assistive Access |
| `UISupportsFullScreenInAssistiveAccess` | Boolean | App runs full screen in Assistive Access (not grid) |

## UIKit Support

For UIKit apps, use the `.windowAssistiveAccessApplication` scene role:

```swift
class AssistiveAccessSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = SimplifiedViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}
```

Configure in Info.plist with the `UIApplicationSceneManifest` specifying the Assistive Access scene configuration.

## Previewing

```swift
#Preview(traits: .assistiveAccess) {
    SimplifiedContentView()
}
```

## Design Guidelines

1. **Flat navigation.** One level deep maximum. No tab bars with sub-navigation.
2. **Large, clear buttons.** Minimum 60pt height, high contrast, simple icons.
3. **Minimal text.** Short labels, no paragraphs. Icons carry meaning.
4. **No complex gestures.** Tap only — no swipe actions, long press, or drag.
5. **Consistent layout.** Same screen structure throughout. Predictability reduces confusion.
6. **Limit choices.** 4-6 options per screen maximum. Group related actions.

## Common Mistakes

1. **No Assistive Access scene** — if your app is useful to this audience, provide one. It's a separate scene, not a mode toggle.
2. **Sharing view models between scenes** — the Assistive Access scene should have its own simplified data flow.
3. **Complex navigation in simplified UI** — keep it flat. One tap to get anywhere.
4. **Small touch targets** — 44pt is the standard minimum; Assistive Access should use 60pt+.
5. **Forgetting runtime detection** — use `@Environment(\.accessibilityAssistiveAccessEnabled)` when you need to adapt shared components.
