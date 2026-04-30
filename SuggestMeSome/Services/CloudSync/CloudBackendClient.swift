import Foundation

enum CloudBackendClientError: LocalizedError {
    case unavailableBackend
    case invalidResponse
    case httpStatus(Int)
    case decodingFailure
    case missingSession
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unavailableBackend:
            return "Cloud sync is not configured in this build."
        case .invalidResponse:
            return "The cloud backend returned an invalid response."
        case .httpStatus(let statusCode):
            return "The cloud backend returned an error (\(statusCode))."
        case .decodingFailure:
            return "The app could not decode the cloud backend response."
        case .missingSession:
            return "Sign in to your account before syncing."
        case .network(let message):
            return message
        }
    }
}

protocol CloudBackendClient {
    func exchangeAppleIdentity(_ request: CloudAuthExchangeRequest) async throws -> CloudAuthSessionResponse
    func refreshSession(_ request: CloudSessionRefreshRequest) async throws -> CloudAuthSessionResponse
    func bootstrap(_ request: CloudSyncBootstrapRequest, accessToken: String) async throws -> CloudSyncResponse
    func push(_ request: CloudSyncPushRequest, accessToken: String) async throws -> CloudSyncPushResponse
    func pull(_ request: CloudSyncPullRequest, accessToken: String) async throws -> CloudSyncResponse
    func submitPrivacyRequest(
        _ type: PrivacyRequestType,
        accessToken: String
    ) async throws -> CloudPrivacyRequestResponse
    func setConsumerHealthConsent(
        _ request: CloudConsumerHealthConsentRequest,
        accessToken: String
    ) async throws -> CloudPrivacyRequestResponse
    func fetchAccountExport(accessToken: String) async throws -> CloudAccountExportResponse
    func deleteAccount(accessToken: String) async throws -> CloudPrivacyRequestResponse
}

struct HTTPCloudBackendClient: CloudBackendClient {
    let baseURL: URL?
    let session: URLSession
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        baseURL: URL? = ComplianceConfiguration.accountBackendBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func exchangeAppleIdentity(_ request: CloudAuthExchangeRequest) async throws -> CloudAuthSessionResponse {
        try await send(
            path: "auth/apple/exchange",
            method: "POST",
            body: request
        )
    }

    func refreshSession(_ request: CloudSessionRefreshRequest) async throws -> CloudAuthSessionResponse {
        try await send(
            path: "auth/session/refresh",
            method: "POST",
            body: request
        )
    }

    func bootstrap(_ request: CloudSyncBootstrapRequest, accessToken: String) async throws -> CloudSyncResponse {
        try await send(
            path: "sync/bootstrap",
            method: "POST",
            body: request,
            accessToken: accessToken
        )
    }

    func push(_ request: CloudSyncPushRequest, accessToken: String) async throws -> CloudSyncPushResponse {
        try await send(
            path: "sync/push",
            method: "POST",
            body: request,
            accessToken: accessToken
        )
    }

    func pull(_ request: CloudSyncPullRequest, accessToken: String) async throws -> CloudSyncResponse {
        try await send(
            path: "sync/pull",
            method: "POST",
            body: request,
            accessToken: accessToken
        )
    }

    func submitPrivacyRequest(
        _ type: PrivacyRequestType,
        accessToken: String
    ) async throws -> CloudPrivacyRequestResponse {
        struct PrivacyRequestBody: Codable {
            let typeRawValue: String
        }

        return try await send(
            path: "account/privacy/request",
            method: "POST",
            body: PrivacyRequestBody(typeRawValue: type.rawValue),
            accessToken: accessToken
        )
    }

    func setConsumerHealthConsent(
        _ request: CloudConsumerHealthConsentRequest,
        accessToken: String
    ) async throws -> CloudPrivacyRequestResponse {
        try await send(
            path: "account/consumer-health-consent",
            method: "POST",
            body: request,
            accessToken: accessToken
        )
    }

    func fetchAccountExport(accessToken: String) async throws -> CloudAccountExportResponse {
        try await send(
            path: "account/export",
            method: "GET",
            body: Optional<String>.none,
            accessToken: accessToken
        )
    }

    func deleteAccount(accessToken: String) async throws -> CloudPrivacyRequestResponse {
        try await send(
            path: "account/delete",
            method: "POST",
            body: Optional<String>.none,
            accessToken: accessToken
        )
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Request?,
        accessToken: String? = nil
    ) async throws -> Response {
        guard let baseURL else {
            throw CloudBackendClientError.unavailableBackend
        }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudBackendClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw CloudBackendClientError.httpStatus(httpResponse.statusCode)
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw CloudBackendClientError.decodingFailure
            }
        } catch let error as CloudBackendClientError {
            throw error
        } catch {
            throw CloudBackendClientError.network(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }
}
