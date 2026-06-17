# Chart Modifiers and Interaction

## Axes

### Visibility

```swift
Chart { ... }
    .chartXAxis(.hidden)       // Hide x axis
    .chartYAxis(.visible)      // Show y axis (default)
    .chartXAxis(.automatic)    // System decides
```

### Custom Axis Content

```swift
.chartXAxis {
    AxisMarks(values: .stride(by: .month)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.month(.abbreviated))
    }
}

.chartYAxis {
    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
        AxisGridLine(stroke: StrokeStyle(dash: [2, 2]))
        AxisValueLabel()
    }
}
```

### Axis Components

| Component | Purpose |
|---|---|
| `AxisMarks(values:)` | Group of tick + grid + label at each value |
| `AxisTick()` | Small mark on the axis |
| `AxisGridLine()` | Line across the plot area |
| `AxisValueLabel()` | Text label for the value |
| `AxisValue` | The underlying data value |

### Axis Labels

```swift
.chartXAxisLabel("Month", position: .bottom, alignment: .center)
.chartYAxisLabel("Revenue ($)", position: .leading)

// Custom content
.chartYAxisLabel(position: .leading) {
    Text("Revenue").font(.caption).foregroundStyle(.secondary)
}
```

### Axis Style

```swift
.chartXAxisStyle { axis in
    axis.background(.blue.opacity(0.05))
}
```

---

## Scales

### Domain (Data Range)

```swift
// Explicit numeric domain
.chartYScale(domain: 0...100)

// Explicit category domain (controls order)
.chartXScale(domain: ["Mon", "Tue", "Wed", "Thu", "Fri"])

// Date domain
.chartXScale(domain: startDate...endDate)
```

### Scale Type

```swift
.chartYScale(type: .linear)       // Default
.chartYScale(type: .log)          // Logarithmic
.chartYScale(type: .squareRoot)   // Square root
.chartYScale(type: .symmetricLog) // Symmetric log (handles negatives)
```

### Foreground Style Scale (Colour Mapping)

```swift
// Explicit mapping
.chartForegroundStyleScale([
    "Revenue": .blue,
    "Expenses": .red,
    "Profit": .green,
])

// Domain + range
.chartForegroundStyleScale(
    domain: ["Low", "Medium", "High"],
    range: [.green, .yellow, .red]
)
```

### Symbol and Line Style Scales

```swift
.chartSymbolScale([
    "TypeA": BasicChartSymbolShape.circle,
    "TypeB": BasicChartSymbolShape.square,
])

.chartLineStyleScale([
    "Actual": StrokeStyle(lineWidth: 2),
    "Forecast": StrokeStyle(lineWidth: 2, dash: [5, 3]),
])
```

---

## Legends

```swift
// Visibility
.chartLegend(.hidden)
.chartLegend(.visible)

// Position
.chartLegend(position: .bottom, alignment: .center, spacing: 16)
// Positions: .top, .bottom, .leading, .trailing, .overlay(alignment:)

// Custom content
.chartLegend(position: .bottom) {
    HStack(spacing: 16) {
        Label("Revenue", systemImage: "circle.fill").foregroundStyle(.blue)
        Label("Expenses", systemImage: "circle.fill").foregroundStyle(.red)
    }
    .font(.caption)
}
```

---

## Selection (iOS 17+)

### Single Value Selection

```swift
@State private var selectedDate: Date?

Chart { ... }
    .chartXSelection(value: $selectedDate)

// Visual feedback
Chart {
    ForEach(data) { item in
        BarMark(x: .value("Date", item.date), y: .value("Value", item.value))
    }

    if let selectedDate {
        RuleMark(x: .value("Selected", selectedDate))
            .foregroundStyle(.gray.opacity(0.3))
            .annotation(position: .top) {
                Text(selectedDate, format: .dateTime.month().day())
                    .font(.caption)
            }
    }
}
.chartXSelection(value: $selectedDate)
```

### Range Selection

```swift
@State private var selectedRange: ClosedRange<Date>?

Chart { ... }
    .chartXSelection(range: $selectedRange)
```

### Sector Selection

```swift
@State private var selectedAngle: Double?

Chart { ... }
    .chartAngleSelection(value: $selectedAngle)
```

---

## Scrolling (iOS 17+)

```swift
Chart { ... }
    .chartScrollableAxes(.horizontal)
    .chartXVisibleDomain(length: 7 * 24 * 3600)  // Show 7 days
    .chartScrollPosition(x: $scrollPosition)       // Programmatic control
    .chartScrollTargetBehavior(
        .valueAligned(matching: DateComponents(day: 1))  // Snap to day boundaries
    )
```

### Scroll Position Binding

```swift
@State private var scrollPosition: Date = .now

// Read current position
Text("Viewing: \(scrollPosition.formatted())")

// Jump to position
Button("Go to today") { scrollPosition = .now }
```

---

## Plot Area

### Plot Style

```swift
.chartPlotStyle { plotArea in
    plotArea
        .background(.gray.opacity(0.05))
        .border(.gray.opacity(0.2), width: 1)
        .frame(height: 200)
}
```

### Chart Overlay (Interactive Layer)

```swift
.chartOverlay { proxy in
    GeometryReader { geometry in
        Rectangle().fill(.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let plotFrame = proxy.plotFrame ?? .zero
                    let origin = geometry[plotFrame].origin
                    let x = location.x - origin.x
                    if let date: Date = proxy.value(atX: x) {
                        hoveredDate = date
                    }
                case .ended:
                    hoveredDate = nil
                }
            }
    }
}
```

### Chart Background

```swift
.chartBackground { proxy in
    // Content rendered behind the chart marks
}
```

### Chart Gesture

```swift
.chartGesture { proxy in
    DragGesture()
        .onChanged { value in
            if let date: Date = proxy.value(atX: value.location.x) {
                selectedDate = date
            }
        }
}
```

---

## ChartProxy

Available in `chartOverlay`, `chartBackground`, and `chartGesture` closures.

```swift
// Screen → Data
let date: Date? = proxy.value(atX: screenX)
let value: Double? = proxy.value(atY: screenY)

// Data → Screen
let screenX: CGFloat? = proxy.position(forX: someDate)
let screenY: CGFloat? = proxy.position(forY: someValue)

// Plot area frame
let plotFrame: CGRect? = proxy.plotFrame
```

---

## Animation

```swift
Chart(data) { item in
    BarMark(x: .value("X", item.x), y: .value("Y", item.y))
}
.animation(.default, value: data)

// Transition on appearance
Chart { ... }
    .transition(.opacity)
```

---

## Accessibility

Swift Charts automatically generates audio graph representations. Enhance with:

```swift
BarMark(x: .value("Month", item.month), y: .value("Sales", item.sales))
    .accessibilityLabel("\(item.month)")
    .accessibilityValue("\(item.sales) units")
```
