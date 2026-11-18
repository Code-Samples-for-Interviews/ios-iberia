import Domain
import Foundation

public actor ITunesAlbumRepository: AlbumRepository {
    private struct Entry {
        let albums: [Album]
        let expiresAt: ContinuousClock.Instant
    }

    private let client: any HTTPClient
    private let lifetime: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private var cache: [String: Entry] = [:]
    private let maximumEntries = 50

    public init(
        client: any HTTPClient = URLSessionHTTPClient(),
        lifetime: Duration = .seconds(180),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.client = client
        self.lifetime = lifetime
        self.now = now
    }

    public func search(query: String) async throws -> [Album] {
        try Task.checkCancellation()
        removeExpiredEntries()
        if let entry = cache[query] {
            return entry.albums
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "country", value: "es"),
            URLQueryItem(name: "limit", value: "30")
        ]
        guard let url = components.url else { throw APIError.invalidResponse }
        let (data, response) = try await client.data(for: URLRequest(url: url))
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.httpStatus(response.statusCode)
        }
        let albums = try JSONDecoder().decode(ITunesResponse.self, from: data).results.map { $0.album() }
        try Task.checkCancellation()

        // Actors can interleave calls at await. Prune again after the network returns.
        removeExpiredEntries()
        if cache[query] == nil, cache.count >= maximumEntries,
           let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[query] = Entry(albums: albums, expiresAt: now().advanced(by: lifetime))
        return albums
    }

    private func removeExpiredEntries() {
        let instant = now()
        cache = cache.filter { $0.value.expiresAt > instant }
    }
}
