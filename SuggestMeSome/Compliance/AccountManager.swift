//
//  AccountManager.swift
//  SuggestMeSome
//
//  Feature 15 - App-side account, privacy-rights, and consent management
//  scaffolding for a future cloud-backed U.S. launch.
//

import Foundation
import Observation

enum AccountBackendLaunchMode: String, Codable, Equatable {
    case localContractValidation
    case productionBackend

    var title: String {
        switch self {
        case .localContractValidation:
            return "Local Contract Validation"
        case .productionBackend:
            return "Production Backend"
        }
    }

    var detail: String {
        switch self {
        case .localContractValidation:
            return "This build validates account and privacy request flows on device. Connect your production backend before enabling public cloud accounts."
        case .productionBackend:
            return "This build is using the production account and privacy backend."
        }
    }
}

struct UserAccount: Codable, Equatable, Identifiable {
    let id: UUID
    var appleUserID: String?
    var displayName: String
    var email: String
    var createdAt: Date
    var lastSignedInAt: Date
    var launchMode: AccountBackendLaunchMode

    init(
        id: UUID = UUID(),
        appleUserID: String? = nil,
        displayName: String,
        email: String,
        createdAt: Date = Date(),
        lastSignedInAt: Date = Date(),
        launchMode: AccountBackendLaunchMode = .localContractValidation
    ) {
        self.id = id
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.email = email
        self.createdAt = createdAt
        self.lastSignedInAt = lastSignedInAt
        self.launchMode = launchMode
    }
}

struct AppleSignInIdentity: Codable, Equatable {
    var appleUserID: String
    var identityToken: String
    var authorizationCode: String?
    var email: String?
    var displayName: String?
}

enum SessionState: String, Codable, Equatable {
    case signedOut
    case creatingAccount
    case signingIn
    case signedIn
    case deletingAccount
}

enum PrivacyRequestType: String, CaseIterable, Codable, Equatable, Identifiable {
    case access
    case export
    case deleteData
    case deleteAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .access:
            return "Access Request"
        case .export:
            return "Export Request"
        case .deleteData:
            return "Delete Data Request"
        case .deleteAccount:
            return "Delete Account Request"
        }
    }

    var explanation: String {
        switch self {
        case .access:
            return "Ask for a copy of backend-held account and consumer health data associated with your account."
        case .export:
            return "Request a portable export of backend-held account and consumer health data."
        case .deleteData:
            return "Request deletion of backend-held consumer health and account data that is not legally required to be retained."
        case .deleteAccount:
            return "Request deletion of your account and associated backend-held data."
        }
    }
}

enum PrivacyRequestStatus: String, Codable, Equatable {
    case submitted
    case inReview
    case completed
    case cancelled

    var title: String {
        switch self {
        case .submitted:
            return "Submitted"
        case .inReview:
            return "In Review"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        }
    }
}

struct PrivacyRequestRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let accountID: UUID
    let type: PrivacyRequestType
    var status: PrivacyRequestStatus
    let requestedAt: Date
    var completedAt: Date?
    let notes: String

    init(
        id: UUID = UUID(),
        accountID: UUID,
        type: PrivacyRequestType,
        status: PrivacyRequestStatus = .submitted,
        requestedAt: Date = Date(),
        completedAt: Date? = nil,
        notes: String
    ) {
        self.id = id
        self.accountID = accountID
        self.type = type
        self.status = status
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.notes = notes
    }
}

struct ConsumerHealthConsentRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let accountID: UUID
    let categories: [String]
    let purpose: String
    let legalDocumentIDs: [String]?
    let legalVersion: String?
    let legalEffectiveDate: String?
    let acceptedAt: Date
    var withdrawnAt: Date?

    init(
        id: UUID = UUID(),
        accountID: UUID,
        categories: [String],
        purpose: String,
        legalDocumentIDs: [String]? = ComplianceConfiguration.consumerHealthConsentRequiredDocumentIDs,
        legalVersion: String? = ComplianceConfiguration.currentLegalVersion,
        legalEffectiveDate: String? = ComplianceConfiguration.legalEffectiveDateText,
        acceptedAt: Date = Date(),
        withdrawnAt: Date? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.categories = categories
        self.purpose = purpose
        self.legalDocumentIDs = legalDocumentIDs
        self.legalVersion = legalVersion
        self.legalEffectiveDate = legalEffectiveDate
        self.acceptedAt = acceptedAt
        self.withdrawnAt = withdrawnAt
    }

    var isActive: Bool {
        withdrawnAt == nil
    }
}

struct AccountBackendContractState: Codable, Equatable {
    var knownAccounts: [UserAccount]
    var currentAccountID: UUID?
    var privacyRequests: [PrivacyRequestRecord]
    var consumerHealthConsents: [ConsumerHealthConsentRecord]

    static let empty = AccountBackendContractState(
        knownAccounts: [],
        currentAccountID: nil,
        privacyRequests: [],
        consumerHealthConsents: []
    )
}

extension AccountBackendContractState {
    func activeConsumerHealthConsent(for accountID: UUID?) -> ConsumerHealthConsentRecord? {
        guard let accountID else { return nil }
        return consumerHealthConsents.first {
            $0.accountID == accountID &&
            $0.isActive &&
            $0.legalVersion == ComplianceConfiguration.currentLegalVersion
        }
    }

    var currentConsumerHealthConsent: ConsumerHealthConsentRecord? {
        activeConsumerHealthConsent(for: currentAccountID)
    }

    var hasActiveConsumerHealthConsentForCurrentAccount: Bool {
        currentConsumerHealthConsent != nil
    }
}

enum AuthServiceError: LocalizedError, Equatable {
    case invalidEmail
    case missingDisplayName
    case duplicateAccount
    case accountNotFound
    case noSignedInAccount
    case signInWithAppleRequired
    case missingAppleIdentityToken

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter a valid email address."
        case .missingDisplayName:
            return "Enter the name you want associated with the account."
        case .duplicateAccount:
            return "An account with that email already exists on this device."
        case .accountNotFound:
            return "No account with that email was found on this device."
        case .noSignedInAccount:
            return "Sign in to manage account privacy requests."
        case .signInWithAppleRequired:
            return "Use Sign in with Apple to connect your cloud account."
        case .missingAppleIdentityToken:
            return "Apple did not provide a sign-in token."
        }
    }
}

protocol AuthService {
    func restoreState() -> AccountBackendContractState
    func restoreSessionIfNeeded() async -> AccountBackendContractState
    func createAccount(displayName: String, email: String) async throws -> AccountBackendContractState
    func signIn(email: String) async throws -> AccountBackendContractState
    func signInWithApple(_ identity: AppleSignInIdentity) async throws -> AccountBackendContractState
    func signOut() async -> AccountBackendContractState
    func submitPrivacyRequest(_ type: PrivacyRequestType) async throws -> AccountBackendContractState
    func setConsumerHealthConsent(granted: Bool) async throws -> AccountBackendContractState
    func requestAccountExport() async throws -> CloudAccountExportResponse
    func deleteCurrentAccount() async throws -> AccountBackendContractState
}

final class LocalContractAuthService: AuthService {
    static let persistenceKey = "compliance.account.backend.state.v1"

    private let userDefaults: UserDefaults
    private let launchMode: AccountBackendLaunchMode

    init(
        userDefaults: UserDefaults = .standard,
        launchMode: AccountBackendLaunchMode = .localContractValidation
    ) {
        self.userDefaults = userDefaults
        self.launchMode = launchMode
    }

    func restoreState() -> AccountBackendContractState {
        loadState()
    }

    func restoreSessionIfNeeded() async -> AccountBackendContractState {
        loadState()
    }

    func createAccount(displayName: String, email: String) async throws -> AccountBackendContractState {
        let normalizedEmail = try Self.normalizedEmail(email)
        let normalizedName = try Self.normalizedDisplayName(displayName)

        var state = loadState()
        guard state.knownAccounts.contains(where: { $0.email == normalizedEmail }) == false else {
            throw AuthServiceError.duplicateAccount
        }

        let account = UserAccount(
            displayName: normalizedName,
            email: normalizedEmail,
            launchMode: launchMode
        )
        state.knownAccounts.append(account)
        state.currentAccountID = account.id
        persist(state)
        return state
    }

    func signIn(email: String) async throws -> AccountBackendContractState {
        let normalizedEmail = try Self.normalizedEmail(email)
        var state = loadState()

        guard let index = state.knownAccounts.firstIndex(where: { $0.email == normalizedEmail }) else {
            throw AuthServiceError.accountNotFound
        }

        state.knownAccounts[index].lastSignedInAt = Date()
        state.currentAccountID = state.knownAccounts[index].id
        persist(state)
        return state
    }

    func signInWithApple(_ identity: AppleSignInIdentity) async throws -> AccountBackendContractState {
        var state = loadState()
        let resolvedEmail = try Self.normalizedEmail(identity.email ?? "\(identity.appleUserID)@privaterelay.appleid.com")
        let resolvedName = try Self.normalizedDisplayName(identity.displayName ?? "Apple ID User")

        if let index = state.knownAccounts.firstIndex(where: {
            $0.appleUserID == identity.appleUserID || $0.email == resolvedEmail
        }) {
            state.knownAccounts[index].appleUserID = identity.appleUserID
            state.knownAccounts[index].displayName = resolvedName
            state.knownAccounts[index].email = resolvedEmail
            state.knownAccounts[index].lastSignedInAt = Date()
            state.knownAccounts[index].launchMode = launchMode
            state.currentAccountID = state.knownAccounts[index].id
        } else {
            let account = UserAccount(
                appleUserID: identity.appleUserID,
                displayName: resolvedName,
                email: resolvedEmail,
                launchMode: launchMode
            )
            state.knownAccounts.append(account)
            state.currentAccountID = account.id
        }

        persist(state)
        return state
    }

    func signOut() async -> AccountBackendContractState {
        var state = loadState()
        state.currentAccountID = nil
        persist(state)
        return state
    }

    func submitPrivacyRequest(_ type: PrivacyRequestType) async throws -> AccountBackendContractState {
        var state = loadState()
        guard let accountID = state.currentAccountID else {
            throw AuthServiceError.noSignedInAccount
        }

        state.privacyRequests.insert(
            PrivacyRequestRecord(
                accountID: accountID,
                type: type,
                notes: "Recorded in local contract validation mode. Connect the production backend before public release."
            ),
            at: 0
        )
        persist(state)
        return state
    }

    func setConsumerHealthConsent(granted: Bool) async throws -> AccountBackendContractState {
        var state = loadState()
        guard let accountID = state.currentAccountID else {
            throw AuthServiceError.noSignedInAccount
        }

        if granted {
            let activeRecord = state.consumerHealthConsents.first {
                $0.accountID == accountID && $0.isActive
            }
            if activeRecord == nil {
                state.consumerHealthConsents.insert(
                    ConsumerHealthConsentRecord(
                        accountID: accountID,
                        categories: ComplianceConfiguration.consumerHealthConsentCategories,
                        purpose: ComplianceConfiguration.consumerHealthConsentPurpose
                    ),
                    at: 0
                )
            }
        } else if let index = state.consumerHealthConsents.firstIndex(where: {
            $0.accountID == accountID && $0.isActive
        }) {
            state.consumerHealthConsents[index].withdrawnAt = Date()
        }

        persist(state)
        return state
    }

    func requestAccountExport() async throws -> CloudAccountExportResponse {
        let state = loadState()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else {
            throw AuthServiceError.noSignedInAccount
        }
        return CloudAccountExportResponse(
            fileName: "SuggestMeSome_Account_Export.json",
            mimeType: "application/json",
            data: data
        )
    }

    func deleteCurrentAccount() async throws -> AccountBackendContractState {
        var state = loadState()
        guard let accountID = state.currentAccountID else {
            throw AuthServiceError.noSignedInAccount
        }

        state.knownAccounts.removeAll { $0.id == accountID }
        state.privacyRequests.removeAll { $0.accountID == accountID }
        state.consumerHealthConsents.removeAll { $0.accountID == accountID }
        state.currentAccountID = nil
        persist(state)
        return state
    }

    private func loadState() -> AccountBackendContractState {
        guard let data = userDefaults.data(forKey: Self.persistenceKey),
              let decoded = try? JSONDecoder().decode(AccountBackendContractState.self, from: data) else {
            return .empty
        }
        return decoded
    }

    private func persist(_ state: AccountBackendContractState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: Self.persistenceKey)
    }

    private static func normalizedEmail(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains(".") else {
            throw AuthServiceError.invalidEmail
        }
        return trimmed
    }

    private static func normalizedDisplayName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw AuthServiceError.missingDisplayName
        }
        return trimmed
    }
}

@MainActor
@Observable
final class AccountManager {
    static let shared = AccountManager(userDefaults: .standard)

    private let authService: AuthService
    private weak var cloudSyncManager: CloudSyncManager?
    private weak var collaborationCoordinator: CollaborationCoordinator?

    private(set) var sessionState: SessionState = .signedOut
    private(set) var knownAccounts: [UserAccount] = []
    private(set) var currentUser: UserAccount?
    private(set) var privacyRequests: [PrivacyRequestRecord] = []
    private(set) var consumerHealthConsents: [ConsumerHealthConsentRecord] = []
    var statusMessage: String?
    var lastErrorMessage: String?

    init(authService: AuthService) {
        self.authService = authService
        apply(authService.restoreState())
    }

    convenience init(userDefaults: UserDefaults) {
        switch ComplianceConfiguration.accountBackendLaunchMode {
        case .localContractValidation:
            self.init(
                authService: LocalContractAuthService(
                    userDefaults: userDefaults,
                    launchMode: ComplianceConfiguration.accountBackendLaunchMode
                )
            )
        case .productionBackend:
            self.init(
                authService: ProductionBackendAuthService(
                    userDefaults: userDefaults
                )
            )
        }
    }

    var launchMode: AccountBackendLaunchMode {
        currentUser?.launchMode ?? ComplianceConfiguration.accountBackendLaunchMode
    }

    var currentAccountPrivacyRequests: [PrivacyRequestRecord] {
        guard let accountID = currentUser?.id else { return [] }
        return privacyRequests.filter { $0.accountID == accountID }
    }

    var currentConsumerHealthConsent: ConsumerHealthConsentRecord? {
        currentState.currentConsumerHealthConsent
    }

    var hasActiveConsumerHealthConsent: Bool {
        currentConsumerHealthConsent != nil
    }

    func createAccount(displayName: String, email: String) async {
        sessionState = .creatingAccount
        statusMessage = nil
        lastErrorMessage = nil
        do {
            let state = try await authService.createAccount(displayName: displayName, email: email)
            apply(state)
            statusMessage = "Account created on this device. Connect your production backend before public cloud launch."
        } catch {
            sessionState = currentUser == nil ? .signedOut : .signedIn
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Account creation failed."
        }
    }

    func signIn(email: String) async {
        sessionState = .signingIn
        statusMessage = nil
        lastErrorMessage = nil
        do {
            let state = try await authService.signIn(email: email)
            apply(state)
            statusMessage = "Signed in on this device."
        } catch {
            sessionState = currentUser == nil ? .signedOut : .signedIn
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Sign in failed."
        }
    }

    func signInWithApple(_ identity: AppleSignInIdentity) async {
        sessionState = .signingIn
        statusMessage = nil
        lastErrorMessage = nil
        do {
            let state = try await authService.signInWithApple(identity)
            apply(state)
            statusMessage = "Cloud account connected."
        } catch {
            sessionState = currentUser == nil ? .signedOut : .signedIn
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Sign in failed."
        }
    }

    func signOut() async {
        statusMessage = nil
        lastErrorMessage = nil
        let state = await authService.signOut()
        apply(state)
        statusMessage = "Signed out."
    }

    func restoreSessionIfNeeded() async {
        let state = await authService.restoreSessionIfNeeded()
        apply(state)
    }

    func submitPrivacyRequest(_ type: PrivacyRequestType) async {
        statusMessage = nil
        lastErrorMessage = nil
        do {
            let state = try await authService.submitPrivacyRequest(type)
            apply(state)
            statusMessage = "\(type.title) submitted."
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Privacy request failed."
        }
    }

    func setConsumerHealthConsent(granted: Bool) async {
        statusMessage = nil
        lastErrorMessage = nil
        do {
            let state = try await authService.setConsumerHealthConsent(granted: granted)
            apply(state)
            statusMessage = granted
                ? "Consumer health sync consent recorded."
                : "Consumer health sync consent withdrawn."
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Consent update failed."
        }
    }

    func deleteCurrentAccount() async {
        sessionState = .deletingAccount
        statusMessage = nil
        lastErrorMessage = nil
        do {
            let state = try await authService.deleteCurrentAccount()
            apply(state)
            statusMessage = "Cloud account deleted and this device was signed out."
        } catch {
            sessionState = currentUser == nil ? .signedOut : .signedIn
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Account deletion failed."
        }
    }

    func requestAccountExport() async throws -> CloudAccountExportResponse {
        try await authService.requestAccountExport()
    }

    func recordExternalError(_ message: String) {
        statusMessage = nil
        lastErrorMessage = message
    }

    func configureCloudSyncManager(_ manager: CloudSyncManager) {
        cloudSyncManager = manager
        Task { @MainActor in
            await manager.handleAccountStateDidChange(currentState)
        }
    }

    func configureCollaborationCoordinator(_ coordinator: CollaborationCoordinator) {
        collaborationCoordinator = coordinator
        coordinator.hydrateAccountState(currentState)
    }

    func reloadFromPersistence() {
        statusMessage = nil
        lastErrorMessage = nil
        apply(authService.restoreState())
    }

    private func apply(_ state: AccountBackendContractState) {
        knownAccounts = state.knownAccounts.sorted { $0.createdAt > $1.createdAt }
        privacyRequests = state.privacyRequests.sorted { $0.requestedAt > $1.requestedAt }
        consumerHealthConsents = state.consumerHealthConsents.sorted { $0.acceptedAt > $1.acceptedAt }
        currentUser = state.knownAccounts.first(where: { $0.id == state.currentAccountID })
        sessionState = currentUser == nil ? .signedOut : .signedIn
        if let cloudSyncManager {
            Task { @MainActor in
                await cloudSyncManager.handleAccountStateDidChange(state)
            }
        }
        if let collaborationCoordinator {
            Task { @MainActor in
                await collaborationCoordinator.handleAccountStateDidChange(state)
            }
        }
    }

    private var currentState: AccountBackendContractState {
        AccountBackendContractState(
            knownAccounts: knownAccounts,
            currentAccountID: currentUser?.id,
            privacyRequests: privacyRequests,
            consumerHealthConsents: consumerHealthConsents
        )
    }
}
