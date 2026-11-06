import Foundation

extension PrtgClient {
    enum WriteAction {
        case acknowledge(id: Int, message: String?)
        case pause(id: Int, minutes: Int?, message: String?)
    }

    static func acknowledgeAlarm(
        objectIds: [Int], message: String?,
        serverURL: String, token: String, acceptSelfSignedCerts: Bool = true
    ) async throws {
        var results: [Result<Void, PrtgClientError>] = []
        for id in objectIds {
            do {
                try await perform(
                    .acknowledge(id: id, message: message),
                    serverURL: serverURL, token: token, acceptSelfSignedCerts: acceptSelfSignedCerts
                )
                results.append(.success(()))
            } catch let error as PrtgClientError {
                results.append(.failure(error))
            } catch {
                results.append(.failure(.networkError(error)))
            }
        }
        if let error = ackOutcome(results) { throw error }
    }

    /// One failing sensor must not keep the rest of a grouped notification unacknowledged.
    static func ackOutcome(_ results: [Result<Void, PrtgClientError>]) -> PrtgClientError? {
        let failures = results.compactMap { result -> PrtgClientError? in
            if case .failure(let error) = result { return error }
            return nil
        }
        guard let first = failures.first else { return nil }
        if failures.count == results.count {
            let allReadOnly = failures.allSatisfy { if case .readOnly = $0 { true } else { false } }
            if allReadOnly { return .readOnly }
            if results.count == 1 { return first }
        }
        return .partiallyAcknowledged(failed: failures.count, total: results.count)
    }

    static func pauseObject(
        objectId: Int, minutes: Int?, message: String?,
        serverURL: String, token: String, acceptSelfSignedCerts: Bool = true
    ) async throws {
        try await perform(
            .pause(id: objectId, minutes: minutes, message: message),
            serverURL: serverURL, token: token, acceptSelfSignedCerts: acceptSelfSignedCerts
        )
    }

    static func writeActionURL(_ action: WriteAction, serverURL: String, token: String) throws -> URL {
        let path: String
        var items: [URLQueryItem]
        switch action {
        case .acknowledge(let id, let message):
            path = "/api/acknowledgealarm.htm"
            items = [URLQueryItem(name: "id", value: "\(id)")]
            if let message { items.append(URLQueryItem(name: "ackmsg", value: message)) }
        case .pause(let id, let minutes, let message):
            items = [URLQueryItem(name: "id", value: "\(id)")]
            if let minutes {
                path = "/api/pauseobjectfor.htm"
                items.append(URLQueryItem(name: "duration", value: "\(minutes)"))
            } else {
                path = "/api/pause.htm"
                items.append(URLQueryItem(name: "action", value: "0"))
            }
            if let message { items.append(URLQueryItem(name: "pausemsg", value: message)) }
        }
        return try buildURL(serverURL: serverURL, path: path, token: token, queryItems: items)
    }

    // PRTG answers 401/403 for write calls when the key lacks write permission
    static func mapWriteError(_ error: PrtgClientError) -> PrtgClientError {
        if case .unauthorized = error { return .readOnly }
        return error
    }

    private static func perform(
        _ action: WriteAction, serverURL: String, token: String, acceptSelfSignedCerts: Bool
    ) async throws {
        let url = try writeActionURL(action, serverURL: serverURL, token: token)
        do {
            _ = try await performRequest(url: url, token: token, acceptSelfSignedCerts: acceptSelfSignedCerts)
        } catch let error as PrtgClientError {
            throw mapWriteError(error)
        }
    }
}
