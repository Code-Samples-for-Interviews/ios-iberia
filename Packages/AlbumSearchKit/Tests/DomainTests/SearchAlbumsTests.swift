import Domain
import Foundation
import Testing

struct SearchAlbumsTests {
    @Test(arguments: ["", "   ", "\n\t"])
    func emptyQueriesDoNotReachTheRepository(query: String) async throws {
        let repository = RepositorySpy()
        let result = try await SearchAlbums(repository: repository).execute(query: query)

        #expect(result.isEmpty)
        #expect(await repository.queries.isEmpty)
    }

    @Test
    func normalizesTheQueryAndReturnsRepositoryResults() async throws {
        let repository = RepositorySpy()
        let result = try await SearchAlbums(repository: repository).execute(query: "  QuEeN\n")

        #expect(await repository.queries == ["queen"])
        #expect(result == [sampleAlbum])
    }

    @Test
    func propagatesRepositoryErrors() async {
        let useCase = SearchAlbums(repository: FailingRepository())

        await #expect(throws: SampleError.offline) {
            try await useCase.execute(query: "queen")
        }
    }

    @Test
    func rejectsResultsWhenTheRepositoryCancelsTheTask() async {
        let task = Task {
            try await SearchAlbums(repository: CancellingRepository()).execute(query: "queen")
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

private let sampleAlbum = Album(
    id: 1, title: "A Night at the Opera", artist: "Queen", genre: "Rock", trackCount: 12, releaseDate: nil
)

private actor RepositorySpy: AlbumRepository {
    private(set) var queries: [String] = []

    func search(query: String) async throws -> [Album] {
        queries.append(query)
        return [sampleAlbum]
    }
}

private enum SampleError: Error { case offline }

private struct FailingRepository: AlbumRepository {
    func search(query: String) async throws -> [Album] { throw SampleError.offline }
}

private struct CancellingRepository: AlbumRepository {
    func search(query: String) async throws -> [Album] {
        withUnsafeCurrentTask { $0?.cancel() }
        return [sampleAlbum]
    }
}
