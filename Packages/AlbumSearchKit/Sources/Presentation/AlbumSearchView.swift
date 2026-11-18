#if os(iOS)
import Domain
import SwiftUI

public struct AlbumSearchView: View {
    @Bindable private var model: SearchViewModel

    public init(model: SearchViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            List {
                content
            }
            .navigationTitle("Album Search")
            .searchable(text: $model.query, prompt: "Artist or album")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .task(id: model.requestID) {
                await model.search()
            }
            .onChange(of: model.state) { _, state in
                switch state {
                case .loaded(let albums):
                    AccessibilityNotification.Announcement(
                        albums.isEmpty ? "No albums found." : "\(albums.count) albums found."
                    ).post()
                case .failed:
                    AccessibilityNotification.Announcement("Search failed. Please try again.").post()
                case .idle, .loading:
                    break
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView(
                "Find an album",
                systemImage: "magnifyingglass",
                description: Text("Search by artist or album name in the iTunes catalog.")
            )
        case .loading:
            ProgressView("Searching albums…")
                .frame(maxWidth: .infinity)
        case .loaded(let albums) where albums.isEmpty:
            ContentUnavailableView(
                "No albums found",
                systemImage: "music.note",
                description: Text("Try another artist or album name.")
            )
        case .loaded(let albums):
            Section {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(album.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .accessibilityHint("Shows album details")
                }
            } header: {
                Text("\(albums.count) albums")
            } footer: {
                Text("Album information from iTunes. Results are limited to 30 albums from the Spanish store.")
            }
        case .failed:
            ContentUnavailableView {
                Label("Unable to search", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try again") {
                    model.retry()
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
        }
    }
}

#Preview {
    AlbumSearchView(model: SearchViewModel(searchAlbums: SearchAlbums(repository: PreviewRepository())))
}

private struct PreviewRepository: AlbumRepository {
    func search(query: String) async throws -> [Album] {
        [Album(id: 1, title: "A Night at the Opera", artist: "Queen", genre: "Rock", trackCount: 12, releaseDate: nil)]
    }
}
#endif

// Accessibility summary:
// - Native search, list, navigation links and retry button support VoiceOver and Switch Control.
// - Album title and artist are read together; the link hint explains navigation.
// - Semantic fonts wrap without line limits and support all Dynamic Type sizes.
// - Loading has a text label; results and failures are announced without moving focus.
// - Native colors support light/dark mode and Increase Contrast. No state relies on color or motion.
// Test: enable VoiceOver, search, listen for completion, open a result and return; trigger an error
// and retry. Repeat at the largest accessibility text size, in dark mode and with Switch Control.
