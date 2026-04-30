import Foundation

final class ProductionBackendAuthService: AuthService {
    static let persistenceKey = "compliance.account.backend.production-state.v1"

    private let userDefaults: UserDefaults
    private let backendClient: CloudBackendClient
    private let tokenStore: CloudSessionTokenStore
    private let syncStateStore: CloudSyncStateStore

    init(
        userDefaults: UserDefaults = .standard,
        backendClient: CloudBackendClient = HTTPCloudBackendClient(),
        tokenStore: CloudSessionTokenStore = KeychainCloudSessionTokenStore.shared,
        syncStateStore: CloudSyncStateStore? = nil
    ) {
        self.userDefaults = userDefaults
        self.backendClient = backendClient
        self.tokenStore = tokenStore
        self.syncStateStore = syncStateStore ?? CloudSyncStateStore(userDefaults: userDefaults)
    }

    func restoreState() -> AccountBackendContractState {
        let state = resolvedStateForCurrentSession(loadState())
        persist(state)
        return state
    }

    func restoreSessionIfNeeded() async -> AccountBackendContractState {
        guard let tokens = tokenStore.loadTokens() else {
            let state = resolvedStateForCurrentSession(loadState())
            persist(state)
            return state
        }
        let hasFreshAccessToken = tokens.accessTokenExpiresAt > Date().addingTimeInterval(60)

        do {
            let response = try await backendClient.refreshSession(
                CloudSessionRefreshRequest(
                    deviceID: syncStateStore.deviceID(),
                    refreshToken: tokens.refreshToken
                )
            )
            tokenStore.saveTokens(response.tokens)
            let state = normalized(response.accountState)
            persist(state)
            return state
        } catch {
            if hasFreshAccessToken, !error.isCloudConsentRequiredResponse {
                let state = normalized(loadState())
                persist(state)
                return state
            }
            tokenStore.clearTokens()
            var state = loadState()
            state.currentAccountID = nil
            persist(state)
            return state
        }
    }

    func createAccount(displayName: String, email: String) async throws -> AccountBackendContractState {
        throw AuthServiceError.signInWithAppleRequired
    }

    func signIn(email: String) async throws -> AccountBackendContractState {
        throw AuthServiceError.signInWithAppleRequired
    }

    func signInWithApple(_ identity: AppleSignInIdentity) async throws -> AccountBackendContractState {
        guard !identity.identityToken.isEmpty else {
            throw AuthServiceError.missingAppleIdentityToken
        }

        let response = try await backendClient.exchangeAppleIdentity(
            CloudAuthExchangeRequest(
                deviceID: syncStateStore.deviceID(),
                appleUserID: identity.appleUserID,
                identityToken: identity.identityToken,
                authorizationCode: identity.authorizationCode,
                email: identity.email,
                displayName: identity.displayName
            )
        )

        tokenStore.saveTokens(response.tokens)
        let state = normalized(response.accountState)
        persist(state)
        return state
    }

    func signOut() async -> AccountBackendContractState {
        tokenStore.clearTokens()
        var state = loadState()
        state.currentAccountID = nil
        persist(state)
        return state
    }

    func submitPrivacyRequest(_ type: PrivacyRequestType) async throws -> AccountBackendContractState {
        let state = try await withValidAccessToken { [self] accessToken in
            let response = try await backendClient.submitPrivacyRequest(
                type,
                accessToken: accessToken
            )
            return normalized(response.accountState)
        }
        persist(state)
        return state
    }

    func setConsumerHealthConsent(granted: Bool) async throws -> AccountBackendContractState {
        let state = try await withValidAccessToken { [self] accessToken in
            let response = try await backendClient.setConsumerHealthConsent(
                CloudConsumerHealthConsentRequest(granted: granted),
                accessToken: accessToken
            )
            return normalized(response.accountState)
        }
        persist(state)
        return state
    }

    func requestAccountExport() async throws -> CloudAccountExportResponse {
        try await withValidAccessToken { [self] accessToken in
            try await backendClient.fetchAccountExport(accessToken: accessToken)
        }
    }

    func deleteCurrentAccount() async throws -> AccountBackendContractState {
        let state = try await withValidAccessToken { [self] accessToken in
            let response = try await backendClient.deleteAccount(accessToken: accessToken)
            return normalized(response.accountState)
        }
        tokenStore.clearTokens()
        syncStateStore.clearRuntimeState()
        persist(state)
        return state
    }

    private func withValidAccessToken<T>(
        _ work: @escaping (String) async throws -> T
    ) async throws -> T {
        guard let tokens = tokenStore.loadTokens() else {
            throw AuthServiceError.noSignedInAccount
        }

        if tokens.accessTokenExpiresAt > Date().addingTimeInterval(60) {
            return try await work(tokens.accessToken)
        }

        let refreshed = try await backendClient.refreshSession(
            CloudSessionRefreshRequest(
                deviceID: syncStateStore.deviceID(),
                refreshToken: tokens.refreshToken
            )
        )
        tokenStore.saveTokens(refreshed.tokens)
        persist(normalized(refreshed.accountState))
        return try await work(refreshed.tokens.accessToken)
    }

    private func loadState() -> AccountBackendContractState {
        guard let data = userDefaults.data(forKey: Self.persistenceKey),
              let decoded = try? JSONDecoder().decode(AccountBackendContractState.self, from: data) else {
            return .empty
        }
        return normalized(decoded)
    }

    private func persist(_ state: AccountBackendContractState) {
        guard let data = try? JSONEncoder().encode(normalized(state)) else { return }
        userDefaults.set(data, forKey: Self.persistenceKey)
    }

    private func normalized(_ state: AccountBackendContractState) -> AccountBackendContractState {
        var normalizedState = state
        normalizedState.knownAccounts = normalizedState.knownAccounts.map { account in
            var account = account
            account.launchMode = .productionBackend
            return account
        }
        return normalizedState
    }

    private func resolvedStateForCurrentSession(
        _ state: AccountBackendContractState
    ) -> AccountBackendContractState {
        var resolved = normalized(state)
        guard tokenStore.loadTokens() == nil else {
            return resolved
        }
        resolved.currentAccountID = nil
        return resolved
    }
}
