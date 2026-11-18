#if os(iOS)
import Domain
import SwiftUI

public struct AlbumDetailView: View {
    private let album: Album

    public init(album: Album) {
        self.album = album
    }

    public var body: some View {
        List {
            Section {
                Text(album.title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            Section("Album information") {
                field("Artist", value: album.artist)
                field("Genre", value: album.genre)
                field("Tracks", value: album.trackCount > 0 ? String(album.trackCount) : "Not available")
                field("Released", value: album.releaseDate.map {
                    $0.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt))
                } ?? "Not available")
            }
        }
        .navigationTitle("Album details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, value: String) -> some View {
        // A vertical layout keeps long values readable at accessibility text sizes.
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(album: Album(
            id: 1,
            title: "A Night at the Opera",
            artist: "Queen",
            genre: "Rock",
            trackCount: 12,
            releaseDate: Date(timeIntervalSince1970: 185_760_000)
        ))
    }
}
#endif

// Accessibility summary:
// - VoiceOver can navigate by headings; each field reads its label followed by its value.
// - The native Back button supports VoiceOver, Voice Control and Switch Control.
// - A scrollable vertical layout and semantic fonts support the largest Dynamic Type sizes.
// - Native colors adapt to dark mode and Increase Contrast; no images or animations carry information.
// Test: open an album with VoiceOver, navigate headings, read every field and activate Back.
// Repeat at the largest accessibility text size in portrait, landscape and dark mode; check all values wrap.
