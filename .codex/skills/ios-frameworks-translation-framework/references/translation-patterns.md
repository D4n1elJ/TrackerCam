# Translation Patterns

## System Translation UI

```swift
import Translation

@State private var showTranslation = false

Text(foreignText)
    .translationPresentation(
        isPresented: $showTranslation,
        text: foreignText,
        replacementAction: { translatedText in
            // Optional: replace the original text with translation
            self.displayText = translatedText
        }
    )

Button("Translate") { showTranslation = true }
```

## Custom Translation with TranslationSession

```swift
@State private var translatedText = ""

Text(foreignText)
    .translationTask(source: Locale.Language(identifier: "ja"),
                     target: Locale.Language(identifier: "en")) { session in
        let response = try await session.translate(foreignText)
        translatedText = response.targetText
    }
```

### Using Configuration Object

```swift
@State private var config: TranslationSession.Configuration?

Text(foreignText)
    .translationTask(config) { session in
        let response = try await session.translate(foreignText)
        translatedText = response.targetText
    }

Button("Translate") {
    config = .init(source: Locale.Language(identifier: "es"),
                   target: Locale.Language(identifier: "en"))
}
```

## Batch Translation

```swift
.translationTask(config) { session in
    let requests = texts.map { TranslationSession.Request(sourceText: $0) }
    let responses = try await session.translations(from: requests)
    translatedTexts = responses.map(\.targetText)
}
```

## Language Availability

```swift
let availability = LanguageAvailability()

// Check specific pair
let status = await availability.status(
    from: Locale.Language(identifier: "en"),
    to: Locale.Language(identifier: "ja")
)

switch status {
case .installed: break      // Ready to use offline
case .supported: break      // Available, may need download
case .unsupported: break    // Not available
@unknown default: break
}

// All supported languages
let languages = await availability.supportedLanguages
```

## Error Handling

```swift
do {
    let response = try await session.translate(text)
} catch let error as TranslationError {
    switch error {
    case .unsupportedLanguagePairing: // Language pair not available
    default: break
    }
}
```
