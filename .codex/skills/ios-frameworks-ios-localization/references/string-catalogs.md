# String Catalogs -- Complete Reference

String Catalogs (`.xcstrings`) are the unified localization format. They replace `.strings` and `.stringsdict` with a single JSON-based file. All examples target iOS 26+.

---

## String Catalog Workflow

### Setup

1. File > New > File > String Catalog
2. Name it `Localizable.xcstrings` and add to target
3. Verify Build Settings:
   - "Use Compiler to Extract Swift Strings" = Yes
   - "Localization Prefers String Catalogs" = Yes

### What Xcode Extracts Automatically

- `Text("...")`, `Label("...", ...)`, `Button("...") {}` in SwiftUI
- `String(localized: "...")` in Swift
- `NSLocalizedString("...", comment: "...")` in Objective-C/Swift
- Info.plist values
- App Shortcuts phrases

### Translation States

| State | Indicator | Meaning |
|---|---|---|
| New | Gray | Not yet translated |
| Needs Review | Yellow | Source changed, translation may be stale |
| Reviewed | Green | Translation confirmed current |
| Stale | Red | String no longer referenced in code |

---

## Generated Symbols (Xcode 26+)

Type-safe localization that catches typos at compile time instead of failing silently at runtime.

### Setup

1. Enable Build Setting: "Generate String Catalog Symbols" = Yes (default in new Xcode 26 projects)
2. Add strings manually to the String Catalog via the + button
3. Build -- Xcode generates symbols on `LocalizedStringResource`

**Only manually-added strings generate symbols.** Auto-extracted strings do not.

### Usage

```swift
// Static string -- generates a static property
// Key: "App.HomeScreen.Title" -> Symbol: .appHomeScreenTitle
Text(.appHomeScreenTitle)

// String with placeholder -- generates a function with labeled arguments
// Key: "%lld friends' posts" -> Symbol: .subtitle(friendsPosts:)
Text(.subtitle(friendsPosts: 42))

// In Foundation code
let message = String(localized: .curatedCollection)

// Custom views accepting LocalizedStringResource
struct DetailView: View {
    let title: LocalizedStringResource
    var body: some View { Text(title) }
}
DetailView(title: .editingTitle)
```

### Custom String Tables

Organize large apps with multiple `.xcstrings` files:

```swift
// Default table: Localizable.xcstrings
Text(.welcomeMessage)

// Custom table: Discover.xcstrings
Text(Discover.featuredCollection)

// Custom table: Settings.xcstrings
Text(Settings.privacyPolicy)
```

### Refactoring Extracted Strings to Symbols

Xcode 26 provides a built-in refactoring action:

1. Right-click a string literal in code
2. Refactor > Convert Strings to Symbols
3. Preview all affected call sites
4. Customize symbol names if needed
5. Apply -- Xcode updates code and catalog simultaneously

```swift
// Before
Text("Welcome to WWDC!", comment: "Main welcome message")

// After
Text(.welcomeToWWDC)
```

Batch conversion of entire String Catalogs is supported from the preview sheet.

---

## #bundle Macro (Xcode 26+)

Solves the bundle resolution problem for Swift Packages and frameworks. SwiftUI defaults to `.main` bundle, which does not contain strings from packages.

```swift
// Main app target -- works without bundle:
Text("My Collections", comment: "Section title")

// Swift Package or framework -- requires #bundle
Text("My Collections", bundle: #bundle, comment: "Section title")

// With custom table
Text("My Collections", tableName: "Discover", bundle: #bundle, comment: "Section title")
```

`#bundle` automatically resolves to the correct bundle for the current target. It replaces the older `.module` pattern and is backwards-compatible with older OS versions.

---

## Automatic Comment Generation

Xcode 26 uses an on-device model to generate translator comments automatically.

### Setup

Xcode Settings > Editing > "Automatically generate string catalog comments" = On

### How It Works

When you add a new string in code, Xcode analyzes the surrounding context and generates a comment describing where and how the string is used. Example output:

> "The text label on a button to cancel the deletion of a collection"

Comments appear in XLIFF exports with `from="auto-generated"` attribution:

```xml
<trans-unit id="Grand Canyon">
    <source>Grand Canyon</source>
    <note from="auto-generated">Suggestion for searching landmarks</note>
</trans-unit>
```

Developer-written comments always take priority over auto-generated ones.

---

## Plural Form Complexity

Languages have wildly different plural rules. String Catalogs handle this automatically -- you write one interpolated string, and the catalog provides variations for each language.

| Language | Forms | Categories |
|---|---|---|
| English | 2 | one, other |
| French | 2 | one, other |
| Russian | 3 | one, few, many |
| Polish | 3 | one, few, other |
| Czech | 3 | one, few, other |
| Arabic | 6 | zero, one, two, few, many, other |
| Japanese | 1 | other (no plural distinction) |

### Multiple Variables

When a string has multiple interpolated integers, the catalog creates variations for each combination:

```swift
Text("\(songCount) songs on \(albumCount) albums")
// English: 2 x 2 = 4 entries (one song/one album, one song/other albums, etc.)
// Arabic: 6 x 6 = 36 entries
```

---

## String Interpolation in LocalizedStringResource

`LocalizedStringResource` supports string interpolation. Interpolated values become placeholders in the catalog that translators can reorder.

```swift
// Integer -- creates plural variations
Text("\(count) items")

// String -- no plural, but translators can move the placeholder
let name = "Dan"
Text("Welcome, \(name)!")

// Multiple values
Text("\(city) - \(temperature)°")
```

The catalog stores these with format specifiers (`%lld`, `%@`) and translators see labeled placeholders they can reposition for their language's word order.

---

## App Shortcuts Localization

App Intents and App Shortcuts strings are automatically extracted to the String Catalog.

```swift
struct ShowTrendsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Trends"

    @Parameter(title: "Timeframe")
    var timeframe: Timeframe

    static var parameterSummary: some ParameterSummary {
        Summary("\(.applicationName) Trends for \(\.$timeframe)")
    }
}

struct MyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowTrendsIntent(),
            phrases: [
                "\(.applicationName) Trends for \(\.$timeframe)",
                "Show trends for \(\.$timeframe) in \(.applicationName)"
            ]
        )
    }
}
```

Xcode extracts the intent title, parameter titles, and all phrase variations into the String Catalog. Translators localize the phrases, and Siri matches the localized versions at runtime.

---

## Migration from Legacy Files

### .strings to .xcstrings

1. Select the `.strings` file in the Navigator
2. Editor > Convert to String Catalog
3. Xcode preserves all existing translations
4. Delete the old `.strings` file after verifying

### .stringsdict to .xcstrings

`.stringsdict` plural files merge into the String Catalog automatically during conversion. Plural variations are preserved.

### Gradual Migration

`.strings` and `.xcstrings` coexist in the same target. Xcode checks both at runtime. Migrate one table at a time:

1. Create `Localizable.xcstrings` for new code
2. Convert existing tables one at a time
3. Test translations after each conversion
4. Remove legacy files when fully migrated

---

## XLIFF Export for External Translators

Export localizations for translation teams via File > Export Localizations. Xcode produces XLIFF files containing all strings from String Catalogs.

### Export / Import Cycle

1. File > Export Localizations > select target languages
2. Send `.xcloc` bundles to translators
3. Translators edit the XLIFF inside each bundle
4. File > Import Localizations to merge translations back

### Auto-Generated Comment Attribution

When Xcode 26's automatic comment generation is enabled, exported XLIFF marks AI-generated notes so translators can distinguish them from developer-written context:

```xml
<trans-unit id="Grand Canyon">
    <source>Grand Canyon</source>
    <note from="auto-generated">Suggestion for searching landmarks</note>
</trans-unit>
```

Developer-written `comment:` parameters export without the `from="auto-generated"` attribute and always take priority.

### String Catalog vs Legacy XLIFF Format

String Catalog exports produce cleaner plural trans-units than legacy `.stringsdict`:

```xml
<!-- String Catalog format -- one trans-unit per plural form -->
<trans-unit id="%lld items|==|plural.one">
    <source>%lld item</source>
</trans-unit>
<trans-unit id="%lld items|==|plural.other">
    <source>%lld items</source>
</trans-unit>
```

This flat structure is easier for translators and translation management systems to process than the nested `NSStringLocalizedFormatKey` dictionaries of `.stringsdict`.

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| Strings not in catalog | Build setting disabled | "Use Compiler to Extract Swift Strings" = Yes, then clean + build |
| Translations not showing | Language not added to project | Project > Info > Localizations > + |
| Generated symbols not appearing | Build setting off or strings are auto-extracted | Enable "Generate String Catalog Symbols", add strings manually via + button |
| `#bundle` not resolving | Missing import | Add `import Foundation` |
| Package strings not found | No `bundle:` parameter | Add `bundle: #bundle` to all localized calls in packages |
