# Generative AI Design Patterns (HIG)

Apple's HIG guidance for presenting AI-generated content in apps.

## Core Principles

1. **Transparency.** Always indicate when content is AI-generated. Never pretend AI output is human-written.
2. **User control.** Let people edit, regenerate, or discard AI output. AI assists — it doesn't decide.
3. **Attribution.** If AI summarises or transforms user content, make it clear what the source was.
4. **Confidence.** Don't present uncertain output with the same visual weight as facts. Communicate confidence levels.
5. **Privacy.** Process on-device when possible (FoundationModels). Be transparent about what data goes to servers.

## Presenting AI-Generated Content

### Visual Distinction

- Use a distinct visual treatment (subtle background, border, or icon) for AI-generated text
- Apple uses the ✨ sparkle glyph (`sparkles` SF Symbol) to indicate AI features
- Don't make AI content look identical to user-authored content

```swift
// AI-generated content indicator
HStack(alignment: .top, spacing: 8) {
    Image(systemName: "sparkles")
        .foregroundStyle(.secondary)
    Text(aiGeneratedText)
}
.padding()
.background(.fill.tertiary, in: .rect(cornerRadius: 12))
```

### Editable Output

- Present AI output as a draft, not a final result
- Provide "Edit", "Regenerate", and "Discard" actions
- Let users modify AI text before accepting it

```swift
VStack(alignment: .leading, spacing: 12) {
    Text(aiSummary)
        .padding()
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))

    HStack {
        Button("Use This") { accept(aiSummary) }
            .buttonStyle(.borderedProminent)
        Button("Regenerate", systemImage: "arrow.clockwise") { regenerate() }
        Button("Discard") { discard() }
            .foregroundStyle(.red)
    }
}
```

### Streaming Display

- Show text appearing progressively (typewriter effect) for long generations
- Use FoundationModels snapshot streaming for structured output
- Show a subtle "Generating…" indicator during generation

## Error and Uncertainty

### When AI Fails

```swift
ContentUnavailableView(
    "Couldn't Generate",
    systemImage: "sparkles.rectangle.stack",
    description: Text("Try rephrasing your request or try again later.")
)
```

### Low-Confidence Output

- If the model is uncertain, say so: "This may not be accurate"
- Don't present AI guesses as facts
- For health/medical/financial contexts, add appropriate disclaimers

## Feature Discovery

- Use TipKit to introduce AI features: "Try asking to summarise this article"
- Don't auto-generate without user intent — always require a trigger action
- Offer AI as an option, not the default ("Summarise" button, not auto-summary)

## Privacy Communication

- Indicate on-device vs cloud processing
- "Processed on your device" badge for FoundationModels
- If sending data to a server, explain what and why before the user commits

## Writing Tools Integration

Apple's system-level Writing Tools (Proofread, Rewrite, Summarize) are available in any standard text view. To support them:
- Use standard `TextEditor` / `TextField` — Writing Tools appear automatically
- Don't disable `.writingToolsBehavior` unless you have a specific reason
- Don't build your own "rewrite" feature that duplicates Writing Tools

## What NOT to Do

- Don't auto-replace user text with AI text without confirmation
- Don't generate content without a user-initiated action
- Don't hide that content is AI-generated
- Don't present AI output in contexts where accuracy is critical without disclaimers
- Don't collect prompt data unnecessarily
- Don't make AI the only way to accomplish a task — always provide a manual path
