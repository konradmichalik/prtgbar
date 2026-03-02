import Foundation

enum PrtgClientError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid server URL"
        case .unauthorized: "Invalid API key or insufficient permissions"
        case .serverError(let code): "Server returned error \(code)"
        case .networkError(let error): "Network error: \(error.localizedDescription)"
        case .decodingError(let error): "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

// MARK: - V1 API Response Types

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}

private struct V1TableResponse: Decodable {
    let items: [V1Row]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        for key in ["sensors", "devices", "groups", "probenode"] {
            if let k = DynamicKey(stringValue: key),
               let rows = try? container.decode([V1Row].self, forKey: k) {
                items = rows
                return
            }
        }
        items = []
    }
}

private struct V1Row: Decodable {
    let objid: Int
    let name: String
    let statusRaw: Int?
    let messageRaw: String?
    let parentid: Int?
    let tags: String?
    let activeRaw: Int?
    let upsensRaw: Int?
    let downsensRaw: Int?
    let warnsensRaw: Int?
    let pausedsensRaw: Int?
    let unusualsensRaw: Int?
    let lastdownRaw: Double?

    enum CodingKeys: String, CodingKey {
        case objid, name, parentid, tags
        case statusRaw = "status_raw"
        case messageRaw = "message_raw"
        case activeRaw = "active_raw"
        case upsensRaw = "upsens_raw"
        case downsensRaw = "downsens_raw"
        case warnsensRaw = "warnsens_raw"
        case pausedsensRaw = "pausedsens_raw"
        case unusualsensRaw = "unusualsens_raw"
        case lastdownRaw = "lastdown_raw"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objid = try c.decode(Int.self, forKey: .objid)
        name = try c.decode(String.self, forKey: .name)
        statusRaw = try c.decodeIfPresent(Int.self, forKey: .statusRaw)
        messageRaw = try c.decodeIfPresent(String.self, forKey: .messageRaw)
        parentid = try c.decodeIfPresent(Int.self, forKey: .parentid)
        tags = try c.decodeIfPresent(String.self, forKey: .tags)
        activeRaw = try c.decodeIfPresent(Int.self, forKey: .activeRaw)
        upsensRaw = try c.decodeIfPresent(Int.self, forKey: .upsensRaw)
        downsensRaw = try c.decodeIfPresent(Int.self, forKey: .downsensRaw)
        warnsensRaw = try c.decodeIfPresent(Int.self, forKey: .warnsensRaw)
        pausedsensRaw = try c.decodeIfPresent(Int.self, forKey: .pausedsensRaw)
        unusualsensRaw = try c.decodeIfPresent(Int.self, forKey: .unusualsensRaw)
        // lastdown_raw is OLE Automation date — may be Double, String, or absent
        if let val = try? c.decodeIfPresent(Double.self, forKey: .lastdownRaw) {
            lastdownRaw = val
        } else if let str = try? c.decodeIfPresent(String.self, forKey: .lastdownRaw),
                  let val = Double(str) {
            lastdownRaw = val
        } else {
            lastdownRaw = nil
        }
    }
}

// MARK: - SSL Delegate

private final class SelfSignedDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

// MARK: - Client

enum PrtgClient {
    private static let delegate = SelfSignedDelegate()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    // MARK: - Fetch Objects

    static func fetchObjects(serverURL: String, token: String) async throws -> [PrtgObject] {
        async let probes = fetchTable(serverURL: serverURL, token: token, content: "probenode", kind: .probedevice)
        async let groups = fetchTable(serverURL: serverURL, token: token, content: "groups", kind: .group)
        async let devices = fetchTable(serverURL: serverURL, token: token, content: "devices", kind: .device)
        async let sensors = fetchTable(serverURL: serverURL, token: token, content: "sensors", kind: .sensor)

        // The PRTG Root group (parentid=0) is a system container above all probes.
        // Its children appear as parentless roots, so Root itself shows up empty — exclude it.
        let filteredGroups = try await groups.filter { $0.parent != nil }
        return try await probes + filteredGroups + devices + sensors
    }

    // MARK: - Test Connection

    static func testConnection(serverURL: String, token: String) async throws -> Bool {
        let url = try buildURL(
            serverURL: serverURL,
            path: "/api/table.json",
            token: token,
            queryItems: [
                URLQueryItem(name: "content", value: "sensors"),
                URLQueryItem(name: "columns", value: "objid"),
                URLQueryItem(name: "count", value: "1"),
            ]
        )

        _ = try await performRequest(url: url, token: token)
        return true
    }

    // MARK: - V1 Table Fetch

    private static func fetchTable(
        serverURL: String, token: String, content: String, kind: ObjectKind
    ) async throws -> [PrtgObject] {
        let columns: String
        switch kind {
        case .sensor:
            columns = "objid,name,status,message,parentid,tags,active,lastdown"
        default:
            columns = "objid,name,status,parentid,tags,active,upsens,downsens,warnsens,pausedsens,unusualsens"
        }

        let url = try buildURL(
            serverURL: serverURL,
            path: "/api/table.json",
            token: token,
            queryItems: [
                URLQueryItem(name: "content", value: content),
                URLQueryItem(name: "columns", value: columns),
                URLQueryItem(name: "count", value: "*"),
            ]
        )

        let data = try await performRequest(url: url, token: token)

        do {
            let response = try JSONDecoder().decode(V1TableResponse.self, from: data)
            return response.items.map { mapV1Row($0, kind: kind) }
        } catch {
            throw PrtgClientError.decodingError(error)
        }
    }

    // MARK: - V1 → PrtgObject Mapping

    private static func mapV1Row(_ row: V1Row, kind: ObjectKind) -> PrtgObject {
        let status = mapV1Status(row.statusRaw)

        let parent: ParentRef? = if let pid = row.parentid, pid > 0 {
            ParentRef(id: pid, type: "", name: "")
        } else {
            nil
        }

        let tags: [String]? = row.tags?.split(separator: " ").map(String.init)
        let active = row.activeRaw.map { $0 != 0 }

        let summary: StatusSummary? = if kind != .sensor {
            StatusSummary(
                up: row.upsensRaw ?? 0,
                down: row.downsensRaw ?? 0,
                warning: row.warnsensRaw ?? 0,
                paused: row.pausedsensRaw ?? 0,
                unknown: row.unusualsensRaw ?? 0
            )
        } else {
            nil
        }

        // OLE Automation date → Swift Date (only for currently-down sensors)
        let lastDown: Date? = if kind == .sensor,
            let ole = row.lastdownRaw,
            ole > 25569.0,
            SensorStatus.problemStatuses.contains(status)
        {
            Date(timeIntervalSince1970: (ole - 25569.0) * 86400.0)
        } else {
            nil
        }

        return PrtgObject(
            id: row.objid,
            name: row.name,
            kind: kind,
            status: status,
            message: row.messageRaw,
            parent: parent,
            tags: tags,
            active: active,
            sensorStatusSummary: summary,
            lastDown: lastDown
        )
    }

    private static func mapV1Status(_ raw: Int?) -> SensorStatus {
        switch raw {
        case 3: .up
        case 5, 13: .down
        case 4: .warning
        case 7, 8, 9, 12: .paused
        case 10: .unusual
        case 14: .partialdown
        default: .unknown
        }
    }

    // MARK: - URL Building

    private static func buildURL(
        serverURL: String,
        path: String,
        token: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        let baseURL = serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard var components = URLComponents(string: baseURL) else {
            throw PrtgClientError.invalidURL
        }

        if components.scheme == nil {
            components.scheme = "https"
        }

        components.path = path

        var allItems = queryItems
        allItems.append(URLQueryItem(name: "apitoken", value: token))
        components.queryItems = allItems

        guard let url = components.url else {
            throw PrtgClientError.invalidURL
        }

        return url
    }

    // MARK: - Request

    private static func performRequest(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PrtgClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PrtgClientError.networkError(
                NSError(domain: "PRTGBar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            )
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw PrtgClientError.unauthorized
        default:
            throw PrtgClientError.serverError(httpResponse.statusCode)
        }
    }
}
