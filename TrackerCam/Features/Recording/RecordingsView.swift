import SwiftUI
import AVKit
import AVFoundation

/// Browse, manage, and play recordings saved in the app library (plan §14 / improvements2 #11).
struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [RecordingStore.RecordingItem] = []
    @State private var playing: URL?
    @State private var renameTarget: RecordingStore.RecordingItem?
    @State private var renameText = ""
    @State private var trimTarget: RecordingStore.RecordingItem?
    @State private var errorMessage: String?

    private let store = RecordingStore()

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView("No recordings", systemImage: "film",
                                           description: Text("Tracked videos you record appear here."))
                } else {
                    List {
                        Section {
                            ForEach(items) { item in
                                row(for: item)
                            }
                            .onDelete(perform: delete)
                        } footer: {
                            Text(libraryFooter)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !items.isEmpty {
                        Text(libraryFooter)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $playing) { url in
                ReplayView(url: url)
            }
            .sheet(item: $trimTarget) { item in
                TrimClipSheet(source: item.url) { result in
                    trimTarget = nil
                    switch result {
                    case .success:
                        reload()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                    case .none:
                        break
                    }
                }
            }
            .alert("Rename clip", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") { commitRename() }
            } message: {
                Text("Extension .mov is added automatically.")
            }
            .alert("Library error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear { reload() }
    }

    private var libraryFooter: String {
        let clips = items.count == 1 ? "1 clip" : "\(items.count) clips"
        let bytes = items.reduce(Int64(0)) { $0 + $1.byteCount }
        return "\(clips) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    @ViewBuilder
    private func row(for item: RecordingStore.RecordingItem) -> some View {
        HStack(spacing: 10) {
            Button {
                playing = item.url
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                            Text(item.displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        Text(Self.subtitle(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(item.displayName)")

            Spacer(minLength: 8)

            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Share recording")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.delete(item.url)
                reload()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                store.setFavorite(item.url, isFavorite: !item.isFavorite)
                reload()
            } label: {
                Label(item.isFavorite ? "Unfavorite" : "Favorite",
                      systemImage: item.isFavorite ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .contextMenu {
            Button {
                playing = item.url
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button {
                store.setFavorite(item.url, isFavorite: !item.isFavorite)
                reload()
            } label: {
                Label(item.isFavorite ? "Remove favorite" : "Favorite",
                      systemImage: item.isFavorite ? "star.slash" : "star")
            }
            Button {
                renameText = item.displayName
                renameTarget = item
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                trimTarget = item
            } label: {
                Label("Trim…", systemImage: "timeline.selection")
            }
            ShareLink(item: item.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                store.delete(item.url)
                reload()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { store.delete(items[i].url) }
        reload()
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        if store.rename(target.url, to: renameText) == nil {
            errorMessage = "Could not rename — name may be empty or already in use."
        }
        renameTarget = nil
        reload()
    }

    private func reload() {
        items = store.items()
    }

    private static func subtitle(_ item: RecordingStore.RecordingItem) -> String {
        let date = item.modified.formatted(date: .abbreviated, time: .shortened)
        let size = ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
        return "\(date) · \(size)"
    }
}

// MARK: - Trim sheet

private struct TrimClipSheet: View {
    let source: URL
    /// `nil` = cancelled; `.success` / `.failure` after export attempt.
    var onFinish: (Result<URL, Error>?) -> Void

    @State private var duration: Double = 1
    @State private var start: Double = 0
    @State private var end: Double = 1
    @State private var isExporting = false
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Form {
                if loadFailed {
                    Text("Could not read clip duration.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Range") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start \(Self.timeString(start))")
                            Slider(value: $start, in: 0...max(0.1, end - 0.1))
                            Text("End \(Self.timeString(end))")
                            Slider(value: $end, in: min(duration, start + 0.1)...max(min(duration, start + 0.1), duration))
                            Text("Duration \(Self.timeString(end - start)) of \(Self.timeString(duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Text("Creates a new clip; the original is kept. Tracking sidecar is not trimmed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Trim clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(nil) }
                        .disabled(isExporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Button("Export") { Task { await export() } }
                            .disabled(loadFailed || end <= start)
                    }
                }
            }
            .task { await loadDuration() }
        }
    }

    private func loadDuration() async {
        let asset = AVURLAsset(url: source)
        do {
            let d = try await asset.load(.duration).seconds
            guard d.isFinite, d > 0 else {
                loadFailed = true
                return
            }
            duration = d
            start = 0
            end = min(d, 20)   // default: first 20s — coaching isolate-window
        } catch {
            loadFailed = true
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let url = try await ClipTrimmer.trim(source: source, start: start, end: end)
            onFinish(.success(url))
        } catch {
            onFinish(.failure(error))
        }
    }

    private static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let r = s % 60
        let frac = Int((seconds - Double(s)) * 10)
        if m > 0 {
            return String(format: "%d:%02d.%d", m, r, frac)
        }
        return String(format: "%d.%ds", r, frac)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
