import Foundation

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum APIError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init() {
        // Query caching belongs to the repository; an expired entry must reach the network.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, response)
    }
}
