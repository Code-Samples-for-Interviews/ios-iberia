import Domain
import Foundation
import Observation

@MainActor
@Observable
public final class SearchViewModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded([Album])
        case failed
    }

    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            invalidateSearch()
        }
    }
    public private(set) var state: State = .idle
    public private(set) var requestID = UUID()

    private let searchAlbums: SearchAlbums
    private let debounce: Duration

    public init(searchAlbums: SearchAlbums, debounce: Duration = .milliseconds(300)) {
        self.searchAlbums = searchAlbums
        self.debounce = debounce
    }

    public func retry() {
        invalidateSearch()
    }

    /// Called by SwiftUI's task(id:). The view owns the task and its cancellation.
    public func search() async {
        let id = requestID
        let text = query
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return
        }
        state = .loading
        do {
            try await Task.sleep(for: debounce)
            let albums = try await searchAlbums.execute(query: text)
            try Task.checkCancellation()
            guard requestID == id else { return }
            state = .loaded(albums)
        } catch {
            guard requestID == id else { return }
            // URLSession can report URLError.cancelled rather than CancellationError.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                state = .idle
            } else {
                state = .failed
            }
        }
    }

    private func invalidateSearch() {
        // Invalidate immediately, before SwiftUI schedules cancellation of the previous task.
        requestID = UUID()
        state = .idle
    }
}
