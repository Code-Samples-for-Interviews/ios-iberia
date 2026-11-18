import Foundation

public struct SearchAlbums: Sendable {
    private let repository: any AlbumRepository

    public init(repository: any AlbumRepository) {
        self.repository = repository
    }

    public func execute(query: String) async throws -> [Album] {
        try Task.checkCancellation()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        let albums = try await repository.search(query: normalizedQuery)
        // Keep the contract even if an implementation ignores cooperative cancellation.
        try Task.checkCancellation()
        return albums
    }
}
