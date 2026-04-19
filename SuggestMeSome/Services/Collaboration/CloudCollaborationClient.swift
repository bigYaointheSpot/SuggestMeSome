import Foundation

protocol CloudCollaborationClient {
    func fetchRelationships(accessToken: String) async throws -> [CoachRelationshipDTO]
    func fetchInvites(accessToken: String) async throws -> [CoachInviteDTO]
    func createInvite(_ request: CoachInviteCreateRequest, accessToken: String) async throws -> CoachInviteDTO
    func respondToInvite(stableID: String, request: CoachInviteActionRequest, accessToken: String) async throws -> CoachInviteDTO
    func revokeInvite(stableID: String, accessToken: String) async throws -> CoachInviteDTO

    func updateRelationshipScopes(stableID: String, request: RelationshipScopeUpdateRequest, accessToken: String) async throws -> CoachRelationshipDTO
    func fetchRoster(accessToken: String) async throws -> [InsightSnapshotDTO]

    func fetchAssignments(accessToken: String) async throws -> [ProgramAssignmentDTO]
    func createAssignment(_ request: ProgramAssignmentCreateRequest, accessToken: String) async throws -> ProgramAssignmentDTO
    func updateAssignmentStatus(stableID: String, request: ProgramAssignmentStatusUpdateRequest, accessToken: String) async throws -> ProgramAssignmentActionResponseDTO

    func fetchNotes(accessToken: String) async throws -> [CoachNoteDTO]
    func createCoachNote(_ request: CoachNoteCreateRequest, accessToken: String) async throws -> CoachNoteDTO
    func markCoachNoteRead(stableID: String, accessToken: String) async throws -> CoachNoteDTO

    func fetchNotificationPreferences(accessToken: String) async throws -> NotificationPreferenceDTO
    func updateNotificationPreferences(_ request: NotificationPreferenceUpdateRequest, accessToken: String) async throws -> NotificationPreferenceDTO
    func registerDevice(_ request: DevicePushRegistrationRequest, accessToken: String) async throws -> DevicePushRegistrationDTO

    func fetchInsightSnapshots(accessToken: String) async throws -> [InsightSnapshotDTO]
    func fetchWeeklyDigests(accessToken: String) async throws -> [WeeklyDigestDTO]

    func fetchBlueprints(accessToken: String) async throws -> [SavedProgramBlueprintDTO]
    func saveBlueprint(_ request: SavedProgramBlueprintCreateRequest, accessToken: String) async throws -> SavedProgramBlueprintDTO

    func fetchProgramShares(accessToken: String) async throws -> [ProgramShareGrantDTO]
    func createProgramShare(_ request: ProgramShareGrantCreateRequest, accessToken: String) async throws -> ProgramShareGrantDTO
    func revokeProgramShare(stableID: String, accessToken: String) async throws -> ProgramShareGrantDTO

    func fetchProgressShares(accessToken: String) async throws -> [ProgressShareCardDTO]
    func createProgressShare(_ request: ProgressShareCardCreateRequest, accessToken: String) async throws -> ProgressShareCardDTO
    func revokeProgressShare(stableID: String, accessToken: String) async throws -> ProgressShareCardDTO
}

struct HTTPCloudCollaborationClient: CloudCollaborationClient {
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

    func fetchRelationships(accessToken: String) async throws -> [CoachRelationshipDTO] {
        try await send(path: "collab/relationships", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func fetchInvites(accessToken: String) async throws -> [CoachInviteDTO] {
        try await send(path: "collab/invites", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func createInvite(_ request: CoachInviteCreateRequest, accessToken: String) async throws -> CoachInviteDTO {
        try await send(path: "collab/invites", method: "POST", body: request, accessToken: accessToken)
    }

    func respondToInvite(stableID: String, request: CoachInviteActionRequest, accessToken: String) async throws -> CoachInviteDTO {
        try await send(path: "collab/invites/\(stableID)/action", method: "POST", body: request, accessToken: accessToken)
    }

    func revokeInvite(stableID: String, accessToken: String) async throws -> CoachInviteDTO {
        try await send(path: "collab/invites/\(stableID)/revoke", method: "POST", body: Optional<String>.none, accessToken: accessToken)
    }

    func updateRelationshipScopes(stableID: String, request: RelationshipScopeUpdateRequest, accessToken: String) async throws -> CoachRelationshipDTO {
        try await send(path: "collab/relationships/\(stableID)/scopes", method: "PUT", body: request, accessToken: accessToken)
    }

    func fetchRoster(accessToken: String) async throws -> [InsightSnapshotDTO] {
        try await send(path: "collab/roster", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func fetchAssignments(accessToken: String) async throws -> [ProgramAssignmentDTO] {
        try await send(path: "collab/assignments", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func createAssignment(_ request: ProgramAssignmentCreateRequest, accessToken: String) async throws -> ProgramAssignmentDTO {
        try await send(path: "collab/assignments", method: "POST", body: request, accessToken: accessToken)
    }

    func updateAssignmentStatus(stableID: String, request: ProgramAssignmentStatusUpdateRequest, accessToken: String) async throws -> ProgramAssignmentActionResponseDTO {
        try await send(path: "collab/assignments/\(stableID)/status", method: "PUT", body: request, accessToken: accessToken)
    }

    func fetchNotes(accessToken: String) async throws -> [CoachNoteDTO] {
        try await send(path: "collab/notes", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func createCoachNote(_ request: CoachNoteCreateRequest, accessToken: String) async throws -> CoachNoteDTO {
        try await send(path: "collab/notes", method: "POST", body: request, accessToken: accessToken)
    }

    func markCoachNoteRead(stableID: String, accessToken: String) async throws -> CoachNoteDTO {
        try await send(path: "collab/notes/\(stableID)/read", method: "POST", body: Optional<String>.none, accessToken: accessToken)
    }

    func fetchNotificationPreferences(accessToken: String) async throws -> NotificationPreferenceDTO {
        try await send(path: "notifications/preferences", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func updateNotificationPreferences(_ request: NotificationPreferenceUpdateRequest, accessToken: String) async throws -> NotificationPreferenceDTO {
        try await send(path: "notifications/preferences", method: "PUT", body: request, accessToken: accessToken)
    }

    func registerDevice(_ request: DevicePushRegistrationRequest, accessToken: String) async throws -> DevicePushRegistrationDTO {
        try await send(path: "notifications/device", method: "POST", body: request, accessToken: accessToken)
    }

    func fetchInsightSnapshots(accessToken: String) async throws -> [InsightSnapshotDTO] {
        try await send(path: "insights/snapshots", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func fetchWeeklyDigests(accessToken: String) async throws -> [WeeklyDigestDTO] {
        try await send(path: "insights/digests", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func fetchBlueprints(accessToken: String) async throws -> [SavedProgramBlueprintDTO] {
        try await send(path: "library/blueprints", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func saveBlueprint(_ request: SavedProgramBlueprintCreateRequest, accessToken: String) async throws -> SavedProgramBlueprintDTO {
        try await send(path: "library/blueprints", method: "POST", body: request, accessToken: accessToken)
    }

    func fetchProgramShares(accessToken: String) async throws -> [ProgramShareGrantDTO] {
        try await send(path: "sharing/programs", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func createProgramShare(_ request: ProgramShareGrantCreateRequest, accessToken: String) async throws -> ProgramShareGrantDTO {
        try await send(path: "sharing/programs", method: "POST", body: request, accessToken: accessToken)
    }

    func revokeProgramShare(stableID: String, accessToken: String) async throws -> ProgramShareGrantDTO {
        try await send(path: "sharing/programs/\(stableID)/revoke", method: "POST", body: Optional<String>.none, accessToken: accessToken)
    }

    func fetchProgressShares(accessToken: String) async throws -> [ProgressShareCardDTO] {
        try await send(path: "sharing/progress", method: "GET", body: Optional<String>.none, accessToken: accessToken)
    }

    func createProgressShare(_ request: ProgressShareCardCreateRequest, accessToken: String) async throws -> ProgressShareCardDTO {
        try await send(path: "sharing/progress", method: "POST", body: request, accessToken: accessToken)
    }

    func revokeProgressShare(stableID: String, accessToken: String) async throws -> ProgressShareCardDTO {
        try await send(path: "sharing/progress/\(stableID)/revoke", method: "POST", body: Optional<String>.none, accessToken: accessToken)
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Request?,
        accessToken: String
    ) async throws -> Response {
        guard let baseURL else {
            throw CloudBackendClientError.unavailableBackend
        }

        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let isRetryable = method.uppercased() == "GET"
        return try await performRequest(request, retryable: isRetryable)
    }

    private func performRequest<Response: Decodable>(
        _ request: URLRequest,
        retryable: Bool
    ) async throws -> Response {
        // Exponential backoff delays for GET retries: 250ms, 750ms, 2s.
        let retryDelaysNanos: [UInt64] = retryable
            ? [250_000_000, 750_000_000, 2_000_000_000]
            : []

        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CloudBackendClientError.invalidResponse
                }
                if (500...599).contains(httpResponse.statusCode), attempt < retryDelaysNanos.count {
                    try await Task.sleep(nanoseconds: retryDelaysNanos[attempt])
                    attempt += 1
                    continue
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
            } catch let urlError as URLError where attempt < retryDelaysNanos.count && shouldRetry(urlError) {
                try await Task.sleep(nanoseconds: retryDelaysNanos[attempt])
                attempt += 1
                continue
            } catch {
                throw CloudBackendClientError.network(
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }

    private func shouldRetry(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
