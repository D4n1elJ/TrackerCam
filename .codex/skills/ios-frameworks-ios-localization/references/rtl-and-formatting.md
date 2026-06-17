# RTL Layout & Locale-Aware Formatting Reference

Covers right-to-left language support, locale-aware number/date/currency formatting, text expansion considerations, and image mirroring. All examples target iOS 26+.

---

## RTL Layout

SwiftUI mirrors layouts automatically for RTL languages (Arabic, Hebrew, Urdu, Persian). Your job is to not break it.

### Semantic Directions

Always use leading/trailing. Never use left/right.

```swift
// Correct -- mirrors automatically
.padding(.leading, 16)
.frame(maxWidth: .infinity, alignment: .leading)
HStack { icon; Spacer(); title }

// Wrong -- fixed to physical direction, breaks in RTL
.padding(.left, 16)
.frame(maxWidth: .infinity, alignment: .left)
```

This applies to:
- `.padding(.leading)` / `.padding(.trailing)`
- `.frame(alignment: .leading)` / `.frame(alignment: .trailing)`
- `HStack` child ordering (leading child appears on the right in RTL)
- `alignment: .leading` in `VStack` and `ZStack`

### Testing RTL

**SwiftUI Preview**:

```swift
#Preview("RTL Layout") {
    ContentView()
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
}
```

**Xcode Scheme** (for full app testing):
1. Edit Scheme > Run > Options
2. App Language: "Right-to-Left Pseudolanguage"

The pseudolanguage reverses layout direction without translating strings, making layout issues obvious.

### Common RTL Layout Issues

| Issue | Fix |
|---|---|
| Chevron points wrong direction | Use `chevron.forward` / `chevron.backward` (SF Symbols handles direction) |
| Custom progress bar fills left-to-right in RTL | Use `scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1)` or `flipsForRightToLeftLayoutDirection` |
| Manual `offset(x:)` ignores RTL | Multiply offset by `layoutDirection == .rightToLeft ? -1 : 1` |
| Text alignment hardcoded | Use `.multilineTextAlignment(.leading)` not `.left` |

---

## Image and Icon Mirroring

### SF Symbols

Directional SF Symbols (arrows, chevrons) mirror automatically. Non-directional symbols (star, heart) do not. No action needed.

### Custom Images

Mark images that represent direction (back arrows, progress indicators) to flip in RTL:

```swift
Image("customBackArrow")
    .flipsForRightToLeftLayoutDirection(true)
```

Images that should never flip (logos, photos, maps, clocks):

```swift
Image("companyLogo")
    // No modifier needed -- images don't flip by default
```

---

## Number Formatting

### Basic Numbers

```swift
let formatter = NumberFormatter()
formatter.locale = Locale.current
formatter.numberStyle = .decimal

formatter.string(from: 1234567)
// US: "1,234,567"
// Germany: "1.234.567"
// France: "1 234 567"
```

### Currency

```swift
let formatter = NumberFormatter()
formatter.locale = Locale.current
formatter.numberStyle = .currency

formatter.string(from: 29.99)
// US: "$29.99"
// UK: "£29.99"
// Japan: "¥30"
// France: "29,99 €"
```

Never prepend a currency symbol manually. The position, spacing, and decimal separator vary by locale.

### Percentages

```swift
let formatter = NumberFormatter()
formatter.locale = Locale.current
formatter.numberStyle = .percent

formatter.string(from: 0.85)
// US: "85%"
// Turkey: "%85"
// Arabic: "٨٥٪"
```

---

## Date Formatting

### Style-Based (Preferred)

```swift
let formatter = DateFormatter()
formatter.locale = Locale.current
formatter.dateStyle = .long
formatter.timeStyle = .short

formatter.string(from: Date())
// US: "January 15, 2026 at 3:30 PM"
// France: "15 janvier 2026 à 15:30"
// Japan: "2026年1月15日 15:30"
```

### SwiftUI Convenience

```swift
Text(date, style: .date)      // Locale-aware date
Text(date, style: .time)      // Locale-aware time
Text(date, style: .relative)  // "2 hours ago" (localized)
Text(date, style: .timer)     // Counting up/down
```

### FormatStyle (Modern API)

```swift
let formatted = date.formatted(.dateTime.month(.wide).day().year())
// US: "January 15, 2026"
// France: "15 janvier 2026"
```

### Never Hardcode Format Strings

```swift
// Wrong -- US-only, breaks everywhere else
formatter.dateFormat = "MM/dd/yyyy"

// Wrong -- assumes 12-hour clock
formatter.dateFormat = "h:mm a"

// Correct -- adapts to locale
formatter.dateStyle = .short
```

---

## Measurement Formatting

```swift
let distance = Measurement(value: 100, unit: UnitLength.meters)
let formatter = MeasurementFormatter()
formatter.locale = Locale.current

formatter.string(from: distance)
// US: "328 ft"
// Metric countries: "100 m"
```

Temperature, weight, and volume formatters similarly adapt to the user's locale and region settings.

---

## Text Expansion

Different languages produce text of different lengths from the same source string. Layouts must accommodate this.

### Expansion Ratios (Relative to English)

| Language | Typical Expansion |
|---|---|
| German | +25-35% |
| French | +15-20% |
| Spanish | +15-25% |
| Italian | +15-20% |
| Finnish | +25-35% |
| Greek | +20-30% |
| Japanese | -10-30% (fewer characters but can be wider) |
| Chinese | -10-30% (fewer characters) |
| Arabic | +20-25% |

### Layout Guidelines

```swift
// Wrong -- fixed width clips translated text
Text(title)
    .frame(width: 120)

// Correct -- flexible, grows with content
Text(title)
    .frame(maxWidth: .infinity, alignment: .leading)

// Wrong -- fixed height for single line, multi-line translations get clipped
Text(subtitle)
    .frame(height: 20)

// Correct -- let text wrap
Text(subtitle)
    .fixedSize(horizontal: false, vertical: true)
```

### Testing Expansion

Use Xcode's pseudolanguages to verify layouts without real translations:

- **Double-Length Pseudolanguage**: Doubles every string. If your layout survives this, it handles German.
- **Accented Pseudolanguage**: Adds diacritics to verify character rendering.
- **Bounded String Pseudolanguage**: Wraps strings in brackets to reveal truncation.

Set these via Edit Scheme > Run > Options > App Language.

---

## Locale-Aware Sorting

```swift
let names = ["Ångström", "Zebra", "Apple"]

// Correct -- respects locale collation rules
let sorted = names.sorted {
    $0.localizedStandardCompare($1) == .orderedAscending
}

// Wrong -- byte-level comparison, ignores locale
let sorted = names.sorted()
```

Swedish sorts Å after Z. English treats Å as A. Always use `localizedStandardCompare` for user-visible lists.

---

## Address and Name Formatting

### PersonNameComponentsFormatter

```swift
var name = PersonNameComponents()
name.givenName = "Taro"
name.familyName = "Yamada"

let formatter = PersonNameComponentsFormatter()
formatter.locale = Locale(identifier: "ja_JP")
formatter.string(from: name)
// "山田太郎" -- family name first in Japanese
```

### CNPostalAddressFormatter

```swift
import Contacts

let formatter = CNPostalAddressFormatter()
formatter.string(from: address)
// Formats street, city, state, zip in locale-appropriate order
// Japan: postal code first, then prefecture, city, street
// US: street, city, state ZIP
```

Never assemble addresses from parts with string concatenation. Address component ordering varies by country.
