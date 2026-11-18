import Foundation

public struct Album: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let artist: String
    public let genre: String
    public let trackCount: Int
    public let releaseDate: Date?

    public init(
        id: Int,
        title: String,
        artist: String,
        genre: String,
        trackCount: Int,
        releaseDate: Date?
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.genre = genre
        self.trackCount = trackCount
        self.releaseDate = releaseDate
    }
}
