import Data
import Domain
import Foundation
import Synchronization
import Testing

struct ITunesAlbumRepositoryTests {
    @Test
    func validCacheAvoidsNetworkAndMapsTheResponse() async throws {
        let client = HTTPClientStub(responses: [.success(albumJSON)])
        let clock = ManualClock()
        let repository = ITunesAlbumRepository(client: client, now: { clock.now })

        let first = try await repository.search(query: "queen")
        clock.advance(by: .seconds(179))
        let second = try await repository.search(query: "queen")

        #expect(first == second)
        #expect(await client.requests.count == 1)
        let album = try #require(first.first)
        #expect(album.id == 1)
        #expect(album.title == "A Night at the Opera")
        #expect(album.artist == "Queen")
        #expect(album.genre == "Rock")
        #expect(album.trackCount == 12)
        #expect(album.releaseDate == ISO8601DateFormatter().date(from: "1975-11-21T08:00:00Z"))
    }

    @Test
    func cacheExpiresAtTheBoundaryAndIsReplaced() async throws {
        let client = HTTPClientStub(responses: [.success(albumJSON), .success(emptyJSON)])
        let clock = ManualClock()
        let repository = ITunesAlbumRepository(client: client, now: { clock.now })

        _ = try await repository.search(query: "queen")
        clock.advance(by: .seconds(180))
        let refreshed = try await repository.search(query: "queen")
        let cached = try await repository.search(query: "queen")

        #expect(refreshed.isEmpty)
        #expect(cached == refreshed)
        #expect(await client.requests.count == 2)
    }

    @Test
    func differentQueriesUseDifferentEntries() async throws {
        let client = HTTPClientStub(responses: [.success(albumJSON), .success(emptyJSON)])
        let repository = ITunesAlbumRepository(client: client)

        _ = try await repository.search(query: "queen")
        #expect(try await repository.search(query: "adele").isEmpty)
        #expect(try await repository.search(query: "queen").count == 1)
        #expect(await client.requests.count == 2)
    }

    @Test
    func buildsAnEncodedHTTPSRequest() async throws {
        let client = HTTPClientStub(responses: [.success(emptyJSON)])
        let repository = ITunesAlbumRepository(client: client)
        _ = try await repository.search(query: "ac/dc & friends")

        let request = try #require(await client.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.scheme == "https")
        #expect(url.host == "itunes.apple.com")
        #expect(url.path == "/search")
        #expect(components.queryItems?.contains(URLQueryItem(name: "term", value: "ac/dc & friends")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "entity", value: "album")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "country", value: "es")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "limit", value: "30")) == true)
    }

    @Test
    func httpErrorsAreNotCached() async throws {
        let client = HTTPClientStub(responses: [.httpError(503), .success(albumJSON)])
        let repository = ITunesAlbumRepository(client: client)

        await #expect(throws: APIError.httpStatus(503)) {
            try await repository.search(query: "queen")
        }
        #expect(try await repository.search(query: "queen").count == 1)
        #expect(await client.requests.count == 2)
    }

    @Test
    func transportErrorsAreNotCached() async throws {
        let client = HTTPClientStub(responses: [.offline, .success(albumJSON)])
        let repository = ITunesAlbumRepository(client: client)

        await #expect(throws: URLError.self) { try await repository.search(query: "queen") }
        #expect(try await repository.search(query: "queen").count == 1)
        #expect(await client.requests.count == 2)
    }

    @Test
    func decodingErrorsAreNotCached() async throws {
        let client = HTTPClientStub(responses: [.success(Data("not json".utf8)), .success(albumJSON)])
        let repository = ITunesAlbumRepository(client: client)

        await #expect(throws: DecodingError.self) { try await repository.search(query: "queen") }
        #expect(try await repository.search(query: "queen").count == 1)
    }

    @Test
    func missingOptionalFieldsHaveExplicitFallbacks() async throws {
        let json = Data(#"{"results":[{"collectionId":2,"collectionName":"An album","artistName":"An artist"}]}"#.utf8)
        let repository = ITunesAlbumRepository(client: HTTPClientStub(responses: [.success(json)]))
        let album = try #require(try await repository.search(query: "album").first)

        #expect(album.genre == "Unknown genre")
        #expect(album.trackCount == 0)
        #expect(album.releaseDate == nil)
    }

    @Test
    func cancelledResponseIsNotCachedEvenWhenClientIgnoresCancellation() async throws {
        let client = ControlledHTTPClient()
        let repository = ITunesAlbumRepository(client: client)
        let task = Task { try await repository.search(query: "queen") }
        await client.waitUntilRequested()
        task.cancel()
        await client.complete()

        await #expect(throws: CancellationError.self) { try await task.value }

        let nextTask = Task { try await repository.search(query: "queen") }
        await client.waitUntilRequested()
        await client.complete()
        _ = try await nextTask.value
        #expect(await client.requestCount == 2)
    }

    @Test
    func cacheEvictsTheOldestEntryWhenFull() async throws {
        let client = HTTPClientStub(responses: Array(repeating: .success(emptyJSON), count: 52))
        let clock = ManualClock()
        let repository = ITunesAlbumRepository(client: client, now: { clock.now })
        for index in 0..<51 {
            _ = try await repository.search(query: "query-\(index)")
            clock.advance(by: .seconds(1))
        }
        _ = try await repository.search(query: "query-50")
        #expect(await client.requests.count == 51)
        _ = try await repository.search(query: "query-0")
        #expect(await client.requests.count == 52)
    }
}

private let albumJSON = Data(#"{"results":[{"collectionId":1,"collectionName":"A Night at the Opera","artistName":"Queen","primaryGenreName":"Rock","trackCount":12,"releaseDate":"1975-11-21T08:00:00Z"}]}"#.utf8)
private let emptyJSON = Data(#"{"results":[]}"#.utf8)

private final class ManualClock: Sendable {
    private let instant = Mutex(ContinuousClock.now)
    var now: ContinuousClock.Instant { instant.withLock { $0 } }
    func advance(by duration: Duration) { instant.withLock { $0 = $0.advanced(by: duration) } }
}

private enum StubResponse: Sendable {
    case success(Data)
    case httpError(Int)
    case offline
}

private enum StubError: Error { case noResponse }

private actor HTTPClientStub: HTTPClient {
    private var responses: [StubResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [StubResponse]) { self.responses = responses }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw StubError.noResponse }
        switch responses.removeFirst() {
        case .success(let data):
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        case .httpError(let status):
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case .offline:
            throw URLError(.notConnectedToInternet)
        }
    }
}

private actor ControlledHTTPClient: HTTPClient {
    private var pending: CheckedContinuation<(Data, HTTPURLResponse), Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        return await withCheckedContinuation { continuation in
            pending = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilRequested() async {
        guard pending == nil else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func complete() {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: (
            albumJSON,
            HTTPURLResponse(url: URL(string: "https://itunes.apple.com/search")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        ))
    }
}
