# Marks and Plots

## Mark Types (Item-Level)

One mark instance per data point. Use inside `Chart { ForEach(...) { item in ... } }`.

### BarMark

```swift
// Vertical bar chart
Chart(data) { item in
    BarMark(
        x: .value("Category", item.category),
        y: .value("Value", item.value)
    )
}

// Horizontal bar chart — swap x and y
BarMark(
    x: .value("Value", item.value),
    y: .value("Category", item.category)
)

// Stacked bars — add foregroundStyle
BarMark(x: .value("Month", item.month), y: .value("Sales", item.sales))
    .foregroundStyle(by: .value("Product", item.product))

// Grouped bars — use position
BarMark(x: .value("Month", item.month), y: .value("Sales", item.sales))
    .foregroundStyle(by: .value("Product", item.product))
    .position(by: .value("Product", item.product))

// Interval bars (Gantt-style)
BarMark(
    xStart: .value("Start", item.start),
    xEnd: .value("End", item.end),
    y: .value("Task", item.task)
)

// Corner radius
BarMark(x: .value("X", item.x), y: .value("Y", item.y))
    .cornerRadius(4)
```

### LineMark

```swift
// Basic line chart
Chart(data) { item in
    LineMark(
        x: .value("Date", item.date),
        y: .value("Value", item.value)
    )
}

// Multiple series
LineMark(x: .value("Date", item.date), y: .value("Value", item.value))
    .foregroundStyle(by: .value("Series", item.series))

// Interpolation methods
LineMark(x: .value("X", item.x), y: .value("Y", item.y))
    .interpolationMethod(.monotone)     // Smooth, monotonic
    // .catmullRom                       // Smooth, passes through points
    // .cardinal                         // Smooth, adjustable tension
    // .linear                           // Straight segments (default)
    // .stepStart / .stepCenter / .stepEnd // Stepped

// Custom line style
LineMark(...)
    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
```

### AreaMark

```swift
// Simple area (filled under line)
AreaMark(
    x: .value("Date", item.date),
    y: .value("Value", item.value)
)

// Range area (band between two values)
AreaMark(
    x: .value("Date", item.date),
    yStart: .value("Low", item.low),
    yEnd: .value("High", item.high)
)

// Stacked areas
AreaMark(x: .value("Date", item.date), y: .value("Value", item.value))
    .foregroundStyle(by: .value("Category", item.category))

// Smoothed
AreaMark(x: .value("X", item.x), y: .value("Y", item.y))
    .interpolationMethod(.catmullRom)
```

### PointMark

```swift
// Scatter plot
PointMark(
    x: .value("Weight", item.weight),
    y: .value("Height", item.height)
)

// Differentiate by symbol
PointMark(x: .value("X", item.x), y: .value("Y", item.y))
    .symbol(by: .value("Type", item.type))

// Custom symbol size
PointMark(...)
    .symbolSize(100)  // Area in points²
```

### RuleMark

```swift
// Horizontal threshold line
RuleMark(y: .value("Target", 10_000))
    .foregroundStyle(.red)
    .lineStyle(StrokeStyle(dash: [5, 3]))
    .annotation(position: .top, alignment: .leading) {
        Text("Target").font(.caption).foregroundStyle(.red)
    }

// Vertical reference line
RuleMark(x: .value("Today", Date.now))

// Horizontal span
RuleMark(xStart: .value("Start", start), xEnd: .value("End", end), y: .value("Y", y))
```

### RectangleMark

```swift
// Heatmap cell
RectangleMark(
    xStart: .value("X Start", item.xStart),
    xEnd: .value("X End", item.xEnd),
    yStart: .value("Y Start", item.yStart),
    yEnd: .value("Y End", item.yEnd)
)
.foregroundStyle(by: .value("Intensity", item.intensity))
```

### SectorMark

```swift
// Pie chart
Chart(data) { item in
    SectorMark(angle: .value("Sales", item.sales))
        .foregroundStyle(by: .value("Product", item.name))
}

// Donut chart (golden ratio inner radius)
SectorMark(
    angle: .value("Sales", item.sales),
    innerRadius: .ratio(0.618),
    angularInset: 1.5
)
.cornerRadius(4)
.foregroundStyle(by: .value("Product", item.name))

// Selection
SectorMark(angle: .value("Value", item.value))
    .opacity(selectedItem == item.id ? 1.0 : 0.5)
```

**Guidance:** Max 5-7 sectors. Group remaining into "Other". For many categories, use horizontal BarMark instead.

---

## Vectorized Plots (Collection-Level, iOS 18+)

Single plot instance for an entire data collection. Better performance for large datasets.

| Mark | Vectorized Plot |
|---|---|
| BarMark | BarPlot |
| LineMark | LinePlot |
| AreaMark | AreaPlot |
| PointMark | PointPlot |
| RuleMark | RulePlot |
| RectangleMark | RectanglePlot |
| SectorMark | SectorPlot |

### LinePlot — Data Collection

```swift
Chart {
    LinePlot(data, x: "date", y: "value")
}
```

### LinePlot — Function Plotting

```swift
Chart {
    LinePlot(x: "x", y: "y") { x in sin(x) }
}

// Parametric
LinePlot(x: "x", y: "y", t: "t", domain: 0...(.pi * 2)) { t in
    (x: cos(t), y: sin(t))
}
```

### AreaPlot — Function

```swift
Chart {
    AreaPlot(x: "x", y: "y") { x in sin(x) }
        .foregroundStyle(.blue.opacity(0.3))
}
```

**When to use vectorized plots:**
- 100+ data points
- Plotting mathematical functions
- Performance-sensitive dashboards
- Single-series visualizations

---

## Common Mark Modifiers

```swift
// Series differentiation
.foregroundStyle(by: .value("Series", item.series))
.symbol(by: .value("Type", item.type))

// Grouped positioning (bars side by side)
.position(by: .value("Group", item.group))

// Per-mark annotation
.annotation(position: .top) {
    Text("\(item.value)").font(.caption2)
}

// Transparency
.opacity(isHighlighted ? 1.0 : 0.3)

// Bar corner radius
.cornerRadius(4)

// Line interpolation
.interpolationMethod(.monotone)

// Custom line dash
.lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))

// Symbol size
.symbolSize(80)
```
