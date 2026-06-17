# Foundation Models Patterns

## Availability

```swift
import FoundationModels

private var model = SystemLanguageModel.default

switch model.availability {
case .available:
    // Show AI UI
case .unavailable(.deviceNotEligible):
    // Device doesn't support Apple Intelligence — show alternative UI
case .unavailable(.appleIntelligenceNotEnabled):
    // Prompt user to enable in Settings
case .unavailable(.modelNotReady):
    // Model downloading or not ready — show loading state
case .unavailable(let other):
    // Unknown reason
}
```

---

## Sessions

```swift
// Basic session
let session = LanguageModelSession()

// With instructions (role, constraints, safety)
let session = LanguageModelSession(instructions: """
    You are a cooking assistant.
    Provide brief, practical recipe suggestions.
    Include approximate cooking time.
    Respond with "I can't help with that" for dangerous requests.
    """)

// With tools
let session = LanguageModelSession(tools: [recipeSearchTool])
```

**Single-turn:** Create a new session each time.
**Multi-turn:** Reuse the same session to maintain context.

One request at a time — check `session.isResponding` before sending.

---

## Basic Generation

```swift
let response = try await session.respond(to: "What's a good month to visit Paris?")
print(response.content)  // Always .content, NOT .output

// With options
let response = try await session.respond(
    to: prompt,
    options: GenerationOptions(temperature: 0.7)  // Higher = more creative, max 2.0
)
```

---

## Guided Generation (@Generable)

Type-safe structured responses instead of parsing strings.

### Define the Type

```swift
@Generable(description: "Basic profile information about a cat")
struct CatProfile {
    var name: String

    @Guide(description: "The age of the cat", .range(0...20))
    var age: Int

    @Guide(description: "A one sentence personality profile")
    var profile: String
}
```

### Generate

```swift
let response = try await session.respond(
    to: "Generate a cute rescue cat",
    generating: CatProfile.self
)
print(response.content.name)    // Typed access
print(response.content.age)
print(response.content.profile)
```

### @Guide Constraints

```swift
@Guide(description: "...", .range(0...100))     // Numeric range
@Guide(description: "...", .count(3))            // Array element count
@Guide(description: "Three items", .count(3))
var suggestions: [String]
```

Enums with `@Generable` conformance are also supported for constrained choices.

---

## Snapshot Streaming

Snapshots are partially generated responses where all properties are optional. Each element in the async sequence contains progressively more complete data.

```swift
@Generable
struct TripIdeas {
    @Guide(description: "Trip ideas", .count(5))
    var ideas: [String]
}

// Stream into SwiftUI state
@State private var partial: TripIdeas.PartiallyGenerated?

let stream = session.streamResponse(
    to: "Exciting trip ideas for this year",
    generating: TripIdeas.self
)

for try await snapshot in stream {
    partial = snapshot  // SwiftUI updates progressively
}
```

**Property ordering matters:** Properties generate in declaration order. Place the most useful properties first in `@Generable` structs so streaming UI shows meaningful content sooner.

**Advantages over delta streaming:**
- No manual accumulation
- Works with structured types naturally
- Each snapshot is a valid partial state
- Declarative SwiftUI integration

---

## Tool Calling

```swift
struct RecipeSearchTool: Tool {
    @Generable
    struct Arguments {
        var searchTerm: String
        var numberOfResults: Int
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let recipes = await searchRecipes(
            term: arguments.searchTerm,
            limit: arguments.numberOfResults
        )
        return .string(recipes.map { "- \($0.name): \($0.description)" }.joined(separator: "\n"))
    }
}

// Provide to session
let session = LanguageModelSession(tools: [RecipeSearchTool()])
let response = try await session.respond(to: "Find pasta recipes")
```

### Error Handling

```swift
do {
    let response = try await session.respond(to: "Find a recipe for tomato soup")
} catch let error as LanguageModelSession.ToolCallError {
    print(error.tool.name)        // Which tool failed
    print(error.underlyingError)  // The actual error
} catch {
    print("Other error: \(error)")
}
```

---

## Context Limits

- **4,096 tokens** per session (instructions + prompts + outputs)
- ~3-4 characters per token in English
- Exceeding the limit throws `LanguageModelSession.GenerationError.exceededContextWindowSize`

### Strategies

- Keep instructions concise
- Specify output constraints ("in three sentences", "under 100 words")
- For large data processing, chunk across multiple sessions
- Single-turn for independent queries (new session = fresh budget)

---

## Transcript

```swift
let transcript = session.transcript
// Inspect model actions, tool calls, and responses during the session
```

Useful for debugging generation flow and understanding tool call sequences.

---

## @Generable Enum Support

Enums with `@Generable` conformance constrain the model to valid choices:

```swift
@Generable
enum Sentiment: String, CaseIterable {
    case positive, negative, neutral
}

@Generable(description: "Analysis of user feedback")
struct FeedbackAnalysis {
    @Guide(description: "The emotional tone of the feedback")
    var sentiment: Sentiment

    @Guide(description: "Key topics mentioned", .count(1...5))
    var topics: [String]

    @Guide(description: "Confidence score", .range(0.0...1.0))
    var confidence: Double
}
```

Nested `@Generable` types compose naturally — the model produces valid instances of the full type tree.

## Multi-Session Context Strategy

The 4096-token limit means a single session cannot handle large tasks. Break work across sessions:

```swift
// Pattern: chunked processing with independent sessions
func analyzeDocuments(_ documents: [String]) async throws -> [Summary] {
    try await withThrowingTaskGroup(of: Summary.self) { group in
        for doc in documents {
            group.addTask {
                let session = LanguageModelSession(instructions: "Summarise in 2 sentences.")
                let response = try await session.respond(to: doc, generating: Summary.self)
                return response.content
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }
}
```

**Rules:**
- Single-turn independent queries → new session each (fresh budget)
- Multi-turn conversation → reuse session (context carries over, budget depletes)
- Large data → chunk across sessions, combine results in Swift
- Never try to fit everything in one prompt — the 4096 limit is hard

## Use-Case Decision Tree

| Need | Use | Why NOT Foundation Models |
|---|---|---|
| Classify, summarise, rewrite user text | Foundation Models | On-device, private, free, offline |
| Generate structured data from natural language | Foundation Models + @Generable | Type-safe, constrained output |
| World knowledge, factual Q&A | Server-side LLM API | 3B model lacks world knowledge |
| Image generation/analysis | Apple Intelligence UI / Vision | Foundation Models is text-only |
| Real-time translation | Translation framework | Purpose-built, higher quality |
| Text-to-speech / speech-to-text | AVSpeechSynthesizer / SFSpeechRecognizer | Purpose-built APIs |

## Dynamic Generation Schema

For schemas not known at compile time (e.g., user-defined form fields), use `DynamicGenerationSchema` to build the schema at runtime:

```swift
// When the structure is user-defined or loaded from config
let schema = DynamicGenerationSchema(/* runtime definition */)
let response = try await session.respond(to: prompt, generating: schema)
```

Prefer `@Generable` when the type is known at compile time — it's safer and produces better code. Reserve `DynamicGenerationSchema` for genuinely dynamic use cases.

---

## Performance

- **Prewarm sessions** at init time — create the `LanguageModelSession` before the user triggers generation to avoid 1-2s cold-start latency
- **Property ordering** in `@Generable` structs affects streaming UX — most useful fields first
- **Instruments** has a dedicated Foundation Models template for profiling generation performance (timing, token usage)
- **Stream** any operation exceeding ~1 second latency
- **Fetch via tools** instead of stuffing external data into prompts — keeps the context budget for actual generation

---

## Pressure Defense

**"Just use a cloud LLM API"**
Foundation Models runs on-device: zero cost per request, works offline, no data leaves the device. For classification, summarisation, and structured extraction from user text, it's the right choice. Server APIs are for world knowledge, large context, or capabilities the on-device model lacks.

**"Parse the JSON manually"**
Use `@Generable`. Guided generation constrains the model's output to structurally valid instances of your type. Manual JSON parsing from a 3B model is fragile and defeats the purpose of the framework.

**"One big prompt for everything"**
The 4096-token budget is shared across instructions, prompt, and output. A monolithic prompt will either truncate or fail. Break into focused single-turn sessions — each gets a fresh budget.
