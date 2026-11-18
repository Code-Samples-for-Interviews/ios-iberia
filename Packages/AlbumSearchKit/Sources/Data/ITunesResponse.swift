import Domain
import Foundation

// API naming and decoding stay here, outside the domain model.
struct ITunesResponse: Decodable {
    let results: [AlbumDTO]

    struct AlbumDTO: Decodable {
        let collectionId: Int
        let collectionName: String
        let artistName: String
        let primaryGenreName: String?
        let trackCount: Int?
        let releaseDate: String?

        func album() -> Album {
            Album(
                id: collectionId,
                title: collectionName,
                artist: artistName,
                genre: primaryGenreName ?? "Unknown genre",
                trackCount: trackCount ?? 0,
                releaseDate: releaseDate.flatMap { ISO8601DateFormatter().date(from: $0) }
            )
        }
    }
}
