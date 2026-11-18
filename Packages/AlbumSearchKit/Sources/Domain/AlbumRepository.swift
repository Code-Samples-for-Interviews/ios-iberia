/// The use case supplies a trimmed, lowercase query. Implementations must propagate cancellation.
public protocol AlbumRepository: Sendable {
    func search(query: String) async throws -> [Album]
}
