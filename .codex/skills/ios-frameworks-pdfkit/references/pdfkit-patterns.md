# PDFKit Patterns

## SwiftUI Integration

```swift
import PDFKit

struct PDFViewer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document == nil {
            pdfView.document = PDFDocument(url: url)
        }
    }
}
```

## Loading Documents

```swift
// From URL (local or remote — blocks for remote)
let document = PDFDocument(url: fileURL)

// From Data
let document = PDFDocument(data: pdfData)

// Async loading
Task.detached {
    let doc = PDFDocument(url: remoteURL)
    await MainActor.run { pdfView.document = doc }
}
```

## PDFView Configuration

```swift
pdfView.autoScales = true                          // Fit to width
pdfView.displayMode = .singlePageContinuous        // Scroll vertically
// .singlePage, .twoUp, .twoUpContinuous
pdfView.displayDirection = .vertical               // or .horizontal
pdfView.displaysPageBreaks = true
pdfView.backgroundColor = .systemBackground
pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
pdfView.maxScaleFactor = 4.0
```

## Page Navigation

```swift
// Go to page
if let page = document.page(at: 5) {
    pdfView.go(to: page)
}

// Page count
let pageCount = document.pageCount

// Current page
let currentPage = pdfView.currentPage

// Go to destination (from outline)
if let destination = outline.destination {
    pdfView.go(to: destination)
}
```

## Text Search

```swift
// Synchronous search
let selections = document.findString("search term", withOptions: .caseInsensitive)
for selection in selections {
    selection.pages  // Pages containing the match
    selection.string // Matched text
}

// Highlight search result
pdfView.setCurrentSelection(selections.first, animate: true)
pdfView.scrollSelectionToVisible(nil)
```

## Annotations

```swift
// Add text annotation
let annotation = PDFAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 50),
                                forType: .freeText, withProperties: nil)
annotation.contents = "Note text"
annotation.font = UIFont.systemFont(ofSize: 14)
annotation.color = .yellow
page.addAnnotation(annotation)

// Add highlight
let highlight = PDFAnnotation(bounds: selectionBounds, forType: .highlight, withProperties: nil)
highlight.color = .yellow.withAlphaComponent(0.5)
page.addAnnotation(highlight)

// Remove annotation
page.removeAnnotation(annotation)
```

## Thumbnails

```swift
let thumbnailView = PDFThumbnailView()
thumbnailView.pdfView = pdfView
thumbnailView.thumbnailSize = CGSize(width: 40, height: 60)
thumbnailView.layoutMode = .horizontal  // or .vertical
```

## Document Outline (Table of Contents)

```swift
if let outline = document.outlineRoot {
    func traverse(_ item: PDFOutline, depth: Int) {
        print(String(repeating: "  ", count: depth) + (item.label ?? ""))
        for i in 0..<item.numberOfChildren {
            if let child = item.child(at: i) {
                traverse(child, depth: depth + 1)
            }
        }
    }
    traverse(outline, depth: 0)
}
```

## Saving Changes

```swift
// Save to URL
document.write(to: outputURL)

// Save to Data
let data = document.dataRepresentation()
```
