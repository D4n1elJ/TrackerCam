import SwiftUI
import AVKit

/// Browse and play recordings saved in the app library (plan §14).
struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urls: [URL] = []
    @State private var playing: URL?

    private let store = RecordingStore()

    var body: some View {
        NavigationStack {
            Group {
                if urls.isEmpty {
                    ContentUnavailableView("No recordings", systemImage: "film",
                                           description: Text("Tracked videos you record appear here."))
                } else {
                    List {
                        ForEach(urls, id: \.self) { url in
                            Button { playing = url } label: {
                                HStack {
                                    Image(systemName: "play.rectangle.fill").foregroundStyle(.tint)
                                    VStack(alignment: .leading) {
                                        Text(url.lastPathComponent).font(.subheadline).lineLimit(1)
                                        Text(Self.modified(url)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx { store.delete(urls[i]) }
                            urls = store.recordings()
                        }
                    }
                }
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $playing) { url in
                VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea()
            }
        }
        .onAppear { urls = store.recordings() }
    }

    private static func modified(_ url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
