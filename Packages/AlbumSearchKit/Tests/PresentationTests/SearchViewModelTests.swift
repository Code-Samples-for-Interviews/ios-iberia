import Domain
import Foundation
import Presentation
import XCTest

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testEmptyQueryStaysIdle() async {
        let repository = ControlledRepository()
        let model = makeModel(repository)
        model.query = "   "
        await model.search()

        XCTAssertEqual(model.state, .idle)
        let count = await repository.requestCount
        XCTAssertEqual(count, 0)
    }

    func testLoadingThenSuccessfulResults() async {
        let repository = ControlledRepository()
        let model = makeModel(repository)
        model.query = "queen"
        let task = Task { await model.search() }
        await repository.waitUntilRequested("queen")
        XCTAssertEqual(model.state, .loading)

        await repository.complete("queen", with: .success([album]))
        await task.value
        XCTAssertEqual(model.state, .loaded([album]))
    }

    func testNewQueryClearsResultsImmediately() async {
        let repository = ControlledRepository()
        let model = makeModel(repository)
        model.query = "queen"
        let task = Task { await model.search() }
        await repository.waitUntilRequested("queen")
        await repository.complete("queen", with: .success([album]))
        await task.value

        model.query = "adele"
        XCTAssertEqual(model.state, .idle)
    }

    func testOlderResponseCannotReplaceNewerResults() async {
        // Run both variants: task cancellation and a dependency that completes before cancellation arrives.
        for cancelOldTask in [false, true] {
            let repository = ControlledRepository()
            let model = makeModel(repository)
            model.query = "queen"
            let oldTask = Task { await model.search() }
            await repository.waitUntilRequested("queen")

            model.query = "adele"
            if cancelOldTask { oldTask.cancel() }
            let newTask = Task { await model.search() }
            await repository.waitUntilRequested("adele")
            await repository.complete("adele", with: .success([]))
            await newTask.value
            await repository.complete("queen", with: .success([album]))
            await oldTask.value

            XCTAssertEqual(model.state, .loaded([]))
        }
    }

    func testOlderErrorCannotReplaceNewerResults() async {
        let repository = ControlledRepository()
        let model = makeModel(repository)
        model.query = "queen"
        let oldTask = Task { await model.search() }
        await repository.waitUntilRequested("queen")
        model.query = "adele"
        let newTask = Task { await model.search() }
        await repository.waitUntilRequested("adele")
        await repository.complete("adele", with: .success([]))
        await newTask.value
        await repository.complete("queen", with: .failure(.offline))
        await oldTask.value

        XCTAssertEqual(model.state, .loaded([]))
    }

    func testClearingQueryRejectsPendingResults() async {
        let repository = ControlledRepository()
        let model = makeModel(repository)
        model.query = "queen"
        let task = Task { await model.search() }
        await repository.waitUntilRequested("queen")
        model.query = ""
        await repository.complete("queen", with: .success([album]))
        await task.value

        XCTAssertEqual(model.state, .idle)
    }

    func testCancellationDoesNotShowAnError() async {
        let repository = ControlledRepository()
        let model = makeModel(repository)
        model.query = "queen"
        let task = Task { await model.search() }
        await repository.waitUntilRequested("queen")
        task.cancel()
        await repository.complete("queen", with: .success([album]))
        await task.value

        XCTAssertEqual(model.state, .idle)
    }

    func testFailureCanBeRetriedWithoutEditingTheQuery() async {
        let repository = ControlledRepository()
        let model = makeModel(repository)
        model.query = "queen"
        let task = Task { await model.search() }
        await repository.waitUntilRequested("queen")
        await repository.complete("queen", with: .failure(.offline))
        await task.value
        XCTAssertEqual(model.state, .failed)

        let previousID = model.requestID
        model.retry()
        XCTAssertNotEqual(model.requestID, previousID)
        let retryTask = Task { await model.search() }
        await repository.waitUntilRequested("queen")
        await repository.complete("queen", with: .success([album]))
        await retryTask.value

        XCTAssertEqual(model.state, .loaded([album]))
    }

    private func makeModel(_ repository: ControlledRepository) -> SearchViewModel {
        SearchViewModel(searchAlbums: SearchAlbums(repository: repository), debounce: .zero)
    }
}

private let album = Album(
    id: 1, title: "A Night at the Opera", artist: "Queen", genre: "Rock", trackCount: 12, releaseDate: nil
)

private enum RepositoryError: Error { case offline }

private actor ControlledRepository: AlbumRepository {
    private var pending: [String: CheckedContinuation<[Album], any Error>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private(set) var requestCount = 0

    func search(query: String) async throws -> [Album] {
        requestCount += 1
        // Deliberately ignores cancellation so tests can deliver responses out of order.
        return try await withCheckedThrowingContinuation { continuation in
            pending[query] = continuation
            waiters.removeValue(forKey: query)?.resume()
        }
    }

    func waitUntilRequested(_ query: String) async {
        guard pending[query] == nil else { return }
        await withCheckedContinuation { waiters[query] = $0 }
    }

    func complete(_ query: String, with result: Result<[Album], RepositoryError>) {
        guard let continuation = pending.removeValue(forKey: query) else {
            preconditionFailure("No pending request for \(query)")
        }
        switch result {
        case .success(let albums): continuation.resume(returning: albums)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
