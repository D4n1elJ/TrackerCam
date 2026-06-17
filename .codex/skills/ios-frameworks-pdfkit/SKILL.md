---
name: ios-frameworks-pdfkit
description: Use when displaying, loading, annotating, searching, selecting, or bridging PDFKit documents into SwiftUI.
---

# PDFKit

Review and write PDFKit code for correct document loading, view configuration, and annotation patterns.

## Responsibility

**Owns:** PDFView, PDFDocument, PDFPage, PDFAnnotation, PDFThumbnailView, PDFSelection, PDFOutline, text search, page navigation, annotation creation, UIViewRepresentable wrapping.

**Does NOT own:** PDF generation from HTML (WebKit/print formatter), server-side PDF processing, Core Graphics PDF context drawing.

## Core Principles

1. **PDFView is UIKit.** Wrap in UIViewRepresentable for SwiftUI. No native SwiftUI equivalent.
2. **Load documents async.** PDFDocument(url:) blocks — load on a background queue.
3. **Configure after setting document.** AutoScales, display mode, and other properties may reset when document changes.
4. **Annotations modify the document.** PDFAnnotation changes are in-memory until you call document.write(to:).

## References

- `references/pdfkit-patterns.md` — PDFView setup, document loading, annotations, thumbnails, search, SwiftUI integration
