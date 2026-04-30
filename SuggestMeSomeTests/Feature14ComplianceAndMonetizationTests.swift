//
//  Feature14ComplianceAndMonetizationTests.swift
//  SuggestMeSomeTests
//
//  Feature 14 - Compliance, legal, and monetization hardening coverage.
//

import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature14ComplianceAndMonetizationTests {

    @Test func freeEntitlementRequiresPremiumForPremiumFeatures() {
        #expect(
            FeatureAccessPolicy.decision(
                for: .dailyCoach,
                entitlementState: .free
            ) == .premiumRequired(.dailyCoach)
        )
        #expect(
            !FeatureAccessPolicy.isAccessible(
                .watchCompanion,
                entitlementState: .free
            )
        )
    }

    @Test func premiumEntitlementUnlocksAllPremiumFeatures() {
        for feature in PremiumFeature.allCases {
            #expect(
                FeatureAccessPolicy.isAccessible(
                    feature,
                    entitlementState: .premiumUnlocked
                )
            )
        }
    }

    @Test func onboardingStateRequiresAdultAcknowledgementsAndDocumentAcceptance() {
        var state = ComplianceOnboardingState()
        #expect(!state.isComplete())

        let now = Date(timeIntervalSince1970: 1_712_345_678)
        state.confirmedAdultAt = now
        state.acknowledgedWellnessDisclaimerAt = now
        state.acknowledgedAutomationDisclosureAt = now
        state.acceptedDocumentRecords = ComplianceConfiguration.requiredOnboardingDocumentIDs
            .sorted()
            .map { LegalDocumentRecord(documentID: $0, acceptedAt: now) }
        state.completedAt = now

        #expect(state.hasAcceptedRequiredDocuments())
        #expect(state.isComplete())
    }

    @Test func complianceStateStorePersistsAcceptedDocumentVersions() {
        let suiteName = "Feature14ComplianceStateStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ComplianceStateStore(userDefaults: defaults)
        let markerDate = Date(timeIntervalSince1970: 1_812_345_678)

        store.confirmAdult(at: markerDate)
        store.acknowledgeWellnessDisclaimer(at: markerDate)
        store.acknowledgeAutomationDisclosure(at: markerDate)
        store.acceptRequiredDocuments(at: markerDate)
        store.markCompleted(at: markerDate)

        let reloaded = ComplianceStateStore(userDefaults: defaults)
        #expect(reloaded.onboardingState.confirmedAdultAt == markerDate)
        #expect(reloaded.onboardingState.completedAt == markerDate)
        #expect(
            reloaded.onboardingState.acceptedDocumentIDs ==
            ComplianceConfiguration.requiredOnboardingDocumentIDs
        )
    }

    @Test func purchaseManagerBootsFromCachedEntitlementState() {
        let suiteName = "Feature14PurchaseManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            EntitlementState.premiumUnlocked.rawValue,
            forKey: "purchase.entitlement.state.v1"
        )

        let purchaseManager = PurchaseManager(
            userDefaults: defaults,
            startListeningForTransactions: false
        )

        #expect(purchaseManager.entitlementState == .premiumUnlocked)
        #expect(purchaseManager.isPremiumUnlocked)
    }

#if DEBUG
    @Test func debugPremiumOverrideCanToggleBetweenFreeAndPremium() async {
        let suiteName = "Feature14DebugPurchaseManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let purchaseManager = PurchaseManager(
            userDefaults: defaults,
            startListeningForTransactions: false
        )

        #expect(!purchaseManager.debugPremiumOverrideEnabled)
        #expect(purchaseManager.entitlementState == .free)

        purchaseManager.setDebugPremiumOverride(true)

        #expect(purchaseManager.debugPremiumOverrideEnabled)
        #expect(purchaseManager.entitlementState == .premiumUnlocked)
        #expect(purchaseManager.isPremiumUnlocked)

        let reloaded = PurchaseManager(
            userDefaults: defaults,
            startListeningForTransactions: false
        )

        #expect(reloaded.debugPremiumOverrideEnabled)
        #expect(reloaded.entitlementState == .premiumUnlocked)

        reloaded.setDebugPremiumOverride(false)
        await reloaded.refreshEntitlements()

        #expect(!reloaded.debugPremiumOverrideEnabled)
        #expect(reloaded.entitlementState == .free)
        #expect(!reloaded.isPremiumUnlocked)
    }
#endif

    @Test func legalConfigurationIncludesRequiredDisclosuresAndAppleHealthCopy() {
        #expect(
            ComplianceConfiguration.premiumUnlockDisclosure ==
            "Premium Unlock is a one-time purchase. It unlocks coaching, analytics, smart generation, Apple Health integration, and Apple Watch features. Manual workout logging remains free."
        )
        #expect(!ComplianceConfiguration.requiresOrganizationAccountBeforeRelease)
        #expect(ComplianceConfiguration.accountBackendLaunchMode == .productionBackend)
        #expect(
            ComplianceConfiguration.onboardingEligibilityTitle == "Training eligibility"
        )
        #expect(
            ComplianceConfiguration.onboardingEligibilityDisclosure.contains("18 or older")
        )
        #expect(
            ComplianceConfiguration.adultsOnlyLegalDisclosure == "SuggestMeSome is intended for adults age 18 and older."
        )
        #expect(
            ComplianceConfiguration.appleHealthDisclosure.contains("Apple Health")
        )
        #expect(
            ComplianceConfiguration.dailyCoachGuidanceDisclosure.contains("not diagnostic measurements or medical advice")
        )
        #expect(
            ComplianceConfiguration.doctorCheckDisclosure.contains("doctor")
        )
        #expect(
            ComplianceConfiguration.cloudSyncStorageDisclosure.contains("dedicated backend")
        )
        #expect(
            ComplianceConfiguration.onboardingPrivacyDisclosure.contains("Sign in with Apple")
        )
        #expect(
            ComplianceConfiguration.onboardingPrivacyDisclosure.contains("collaborate privately")
        )
        #expect(
            ComplianceConfiguration.accountSignInDisclosure.contains("Apple account identifier")
        )
        #expect(
            ComplianceConfiguration.pushNotificationDisclosure.contains("APNs token")
        )
        #expect(
            ComplianceConfiguration.privacyAppealDisclosure.contains(ComplianceConfiguration.privacyEmail)
        )

        let privacyPolicy = ComplianceConfiguration.document(for: .privacyPolicy)
        let consumerHealthNotice = ComplianceConfiguration.document(for: .consumerHealthNotice)
        let termsDocument = ComplianceConfiguration.document(for: .termsOfUse)
        let supportDocument = ComplianceConfiguration.document(for: .support)

        #expect(!privacyPolicy.containsPlaceholders)
        #expect(ComplianceConfiguration.sellerName == "Alexander Yao")
        #expect(ComplianceConfiguration.supportEmail == "support@suggestmesome.app")
        #expect(ComplianceConfiguration.privacyEmail == "privacy@suggestmesome.app")
        #expect(ComplianceConfiguration.websiteURL.absoluteString == "https://www.suggestmesome.app")
        #expect(ComplianceConfiguration.privacyChoicesURL.absoluteString == "https://www.suggestmesome.app/privacy-choices")
        #expect(privacyPolicy.bodyMarkdown.contains("published by **\(ComplianceConfiguration.sellerName)**"))
        #expect(privacyPolicy.bodyMarkdown.contains("invitee email addresses"))
        #expect(privacyPolicy.bodyMarkdown.contains("APNs device-token registrations"))
        #expect(privacyPolicy.bodyMarkdown.contains("private progress shares"))
        #expect(privacyPolicy.bodyMarkdown.contains("Privacy Choices"))
        #expect(consumerHealthNotice.bodyMarkdown.contains("does not use Apple Health data for advertising"))
        #expect(consumerHealthNotice.bodyMarkdown.contains("Washington residents"))
        #expect(consumerHealthNotice.bodyMarkdown.contains("visibility settings"))
        #expect(consumerHealthNotice.bodyMarkdown.contains("Privacy Choices URL"))
        #expect(consumerHealthNotice.bodyMarkdown.contains("Revoking collaboration access stops future sharing"))
        #expect(termsDocument.bodyMarkdown.contains("Premium Unlock is a one-time in-app purchase"))
        #expect(termsDocument.bodyMarkdown.contains("Santa Clara County, California"))
        #expect(supportDocument.summary.contains("privacy choices"))
        #expect(supportDocument.bodyMarkdown.contains("Privacy Choices"))
        #expect(supportDocument.bodyMarkdown.contains("Restore Purchases"))
        #expect(!supportDocument.bodyMarkdown.contains("U.S. Launch Checklist"))
        #expect(
            ComplianceConfiguration.releaseGateChecklist.contains(where: { $0.contains("Sign in with Apple") && $0.contains("push registration") })
        )
        #expect(
            ComplianceConfiguration.releaseGateChecklist.contains(where: { $0.contains("Preview Cloud Features") })
        )
        #expect(
            ComplianceConfiguration.legalDocuments.allSatisfy { !$0.containsPlaceholders }
        )
        #expect(
            ComplianceConfiguration.legalDocuments.allSatisfy { $0.version == ComplianceConfiguration.currentLegalVersion }
        )
        #expect(
            privacyPolicy.bodyMarkdown.contains("Effective \(ComplianceConfiguration.legalEffectiveDateText)")
        )
    }

    @Test func cloudFeaturePreviewSnapshotUsesReadOnlyReviewerSafeSampleData() {
        let snapshot = CloudFeaturePreviewSnapshot.sample

        #expect(snapshot.accountDisplayName == "Preview Athlete")
        #expect(snapshot.relationshipSummaries.count >= 2)
        #expect(snapshot.assignmentSummaries.contains(where: { $0.contains("Week 3") }))
        #expect(snapshot.programShareSummaries.contains(where: { $0.contains("read-only") }))
        #expect(snapshot.notificationSummaries.contains(where: { $0.contains("Coach invites") }))
        #expect(
            ComplianceConfiguration.cloudFeaturePreviewDisclosure.contains("does not create an account")
        )
    }

    @Test func importedWorkoutCopyUsesAppleHealthLabels() {
        let workout = Workout(
            date: Date(),
            startTime: Date(),
            durationSeconds: 600,
            sourceType: .healthKitImported
        )

        #expect(workout.sourceLabel == "Imported from Apple Health")
        #expect(workout.sourceBadgeLabel == "Apple Health")
    }

    @Test func accountManagerSupportsLocalAccountAndPrivacyFlows() async {
        let suiteName = "Feature15AccountManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let authService = LocalContractAuthService(userDefaults: defaults)
        let accountManager = AccountManager(authService: authService)

        await accountManager.createAccount(
            displayName: "Alex",
            email: "ALEX@Example.com"
        )

        #expect(accountManager.sessionState == .signedIn)
        #expect(accountManager.currentUser?.displayName == "Alex")
        #expect(accountManager.currentUser?.email == "alex@example.com")
        #expect(accountManager.launchMode == .localContractValidation)

        await accountManager.submitPrivacyRequest(.access)
        await accountManager.setConsumerHealthConsent(granted: true)

        #expect(accountManager.currentAccountPrivacyRequests.count == 1)
        #expect(accountManager.currentAccountPrivacyRequests.first?.type == .access)
        #expect(accountManager.currentConsumerHealthConsent?.isActive == true)

        await accountManager.signOut()
        #expect(accountManager.sessionState == .signedOut)

        await accountManager.signIn(email: "alex@example.com")
        #expect(accountManager.sessionState == .signedIn)
        #expect(accountManager.currentUser?.email == "alex@example.com")
    }

    @Test func accountDeletionClearsLocalAccountPrivacyState() async {
        let suiteName = "Feature15DeleteAccount.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let authService = LocalContractAuthService(userDefaults: defaults)
        let accountManager = AccountManager(authService: authService)

        await accountManager.createAccount(
            displayName: "Alex",
            email: "alex@example.com"
        )
        await accountManager.submitPrivacyRequest(.deleteData)
        await accountManager.setConsumerHealthConsent(granted: true)

        #expect(accountManager.currentUser != nil)
        #expect(accountManager.currentAccountPrivacyRequests.isEmpty == false)
        #expect(accountManager.currentConsumerHealthConsent != nil)

        await accountManager.deleteCurrentAccount()

        #expect(accountManager.sessionState == .signedOut)
        #expect(accountManager.currentUser == nil)
        #expect(accountManager.knownAccounts.isEmpty)
        #expect(accountManager.privacyRequests.isEmpty)
        #expect(accountManager.consumerHealthConsents.isEmpty)
    }

    @Test func productionBackendRestoreStateSignsOutWhenSessionTokensAreMissing() async throws {
        let suiteName = "Feature18ProductionRestore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backendClient = TestCloudBackendClient()
        let tokenStore = InMemoryCloudSessionTokenStore()
        let authService = ProductionBackendAuthService(
            userDefaults: defaults,
            backendClient: backendClient,
            tokenStore: tokenStore,
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
        )

        backendClient.exchangeResponse = CloudAuthSessionResponse(
            accountState: feature18SignedInState(),
            tokens: feature18Tokens(
                accessToken: "access-initial",
                refreshToken: "refresh-initial",
                expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )

        _ = try await authService.signInWithApple(feature18AppleIdentity())
        tokenStore.clearTokens()

        let accountManager = AccountManager(authService: authService)

        #expect(accountManager.sessionState == .signedOut)
        #expect(accountManager.currentUser == nil)
        #expect(accountManager.knownAccounts.count == 1)
        #expect(accountManager.knownAccounts.first?.launchMode == .productionBackend)
    }

    @Test func productionBackendRestoreSessionRefreshesExpiredTokens() async throws {
        let suiteName = "Feature18ProductionRefresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backendClient = TestCloudBackendClient()
        let tokenStore = InMemoryCloudSessionTokenStore()
        let authService = ProductionBackendAuthService(
            userDefaults: defaults,
            backendClient: backendClient,
            tokenStore: tokenStore,
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
        )

        backendClient.exchangeResponse = CloudAuthSessionResponse(
            accountState: feature18SignedInState(),
            tokens: feature18Tokens(
                accessToken: "access-exchange",
                refreshToken: "refresh-exchange",
                expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )

        _ = try await authService.signInWithApple(feature18AppleIdentity())

        tokenStore.saveTokens(
            feature18Tokens(
                accessToken: "access-expired",
                refreshToken: "refresh-expired",
                expiresAt: Date(timeIntervalSince1970: 1)
            )
        )
        backendClient.refreshResponse = CloudAuthSessionResponse(
            accountState: feature18SignedInState(),
            tokens: feature18Tokens(
                accessToken: "access-refreshed",
                refreshToken: "refresh-refreshed",
                expiresAt: Date(timeIntervalSince1970: 1_900_000_600)
            )
        )

        let restored = await authService.restoreSessionIfNeeded()

        #expect(restored.currentAccountID == feature18AccountID)
        #expect(tokenStore.loadTokens()?.accessToken == "access-refreshed")
        #expect(backendClient.refreshedSessionRequests.count == 1)
        #expect(backendClient.refreshedSessionRequests.first?.refreshToken == "refresh-expired")
    }

    @Test func productionBackendAccountManagerSupportsExportDeleteDataAndDeleteAccount() async throws {
        let suiteName = "Feature18ProductionAccountManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backendClient = TestCloudBackendClient()
        let tokenStore = InMemoryCloudSessionTokenStore()
        let authService = ProductionBackendAuthService(
            userDefaults: defaults,
            backendClient: backendClient,
            tokenStore: tokenStore,
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
        )
        let accountManager = AccountManager(authService: authService)

        backendClient.exchangeResponse = CloudAuthSessionResponse(
            accountState: feature18SignedInState(),
            tokens: feature18Tokens(
                accessToken: "access-live",
                refreshToken: "refresh-live",
                expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )

        let deleteDataRequest = PrivacyRequestRecord(
            accountID: feature18AccountID,
            type: .deleteData,
            notes: "Submitted to backend"
        )
        backendClient.privacyResponses[.deleteData] = CloudPrivacyRequestResponse(
            accountState: feature18SignedInState(
                privacyRequests: [deleteDataRequest]
            )
        )
        backendClient.exportResponse = CloudAccountExportResponse(
            fileName: "SuggestMeSome_Account_Export.zip",
            mimeType: "application/zip",
            data: Data("cloud-export".utf8)
        )
        backendClient.deleteResponse = CloudPrivacyRequestResponse(accountState: .empty)

        await accountManager.signInWithApple(feature18AppleIdentity())
        #expect(accountManager.sessionState == .signedIn)
        #expect(accountManager.currentUser?.email == "alex@example.com")

        await accountManager.submitPrivacyRequest(.deleteData)
        #expect(accountManager.currentAccountPrivacyRequests.map(\.type) == [.deleteData])
        #expect(backendClient.submittedPrivacyRequests == [.deleteData])

        let export = try await accountManager.requestAccountExport()
        #expect(export.fileName == "SuggestMeSome_Account_Export.zip")
        #expect(String(data: export.data, encoding: .utf8) == "cloud-export")
        #expect(backendClient.exportedAccessTokens == ["access-live"])

        await accountManager.deleteCurrentAccount()
        #expect(accountManager.sessionState == .signedOut)
        #expect(accountManager.currentUser == nil)
        #expect(accountManager.knownAccounts.isEmpty)
        #expect(tokenStore.loadTokens() == nil)
        #expect(backendClient.deletedAccessTokens == ["access-live"])
    }

    @Test func productionBackendConsumerHealthConsentUsesBackendContract() async throws {
        let suiteName = "Feature21ProductionConsent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backendClient = TestCloudBackendClient()
        let tokenStore = InMemoryCloudSessionTokenStore()
        let authService = ProductionBackendAuthService(
            userDefaults: defaults,
            backendClient: backendClient,
            tokenStore: tokenStore,
            syncStateStore: CloudSyncStateStore(userDefaults: defaults)
        )
        let accountManager = AccountManager(authService: authService)
        let consent = ConsumerHealthConsentRecord(
            accountID: feature18AccountID,
            categories: ComplianceConfiguration.consumerHealthConsentCategories,
            purpose: ComplianceConfiguration.consumerHealthConsentPurpose,
            acceptedAt: Date(timeIntervalSince1970: 1_900_000_500)
        )

        backendClient.exchangeResponse = CloudAuthSessionResponse(
            accountState: feature18SignedInState(),
            tokens: feature18Tokens(
                accessToken: "access-consent",
                refreshToken: "refresh-consent",
                expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
            )
        )
        backendClient.consumerHealthConsentResponse = CloudPrivacyRequestResponse(
            accountState: feature18SignedInState(consumerHealthConsents: [consent])
        )

        await accountManager.signInWithApple(feature18AppleIdentity())
        await accountManager.setConsumerHealthConsent(granted: true)

        #expect(accountManager.currentConsumerHealthConsent == consent)
        #expect(backendClient.consumerHealthConsentRequests.map(\.granted) == [true])
        #expect(backendClient.consumerHealthConsentRequests.first?.legalVersion == ComplianceConfiguration.currentLegalVersion)
        #expect(backendClient.consumerHealthConsentAccessTokens == ["access-consent"])
    }
}

private let feature18AccountID = UUID(uuidString: "F1000000-0000-0000-0000-000000000001")!

private func feature18AppleIdentity() -> AppleSignInIdentity {
    AppleSignInIdentity(
        appleUserID: "apple-user-1",
        identityToken: "identity-token",
        authorizationCode: "auth-code",
        email: "alex@example.com",
        displayName: "Alex"
    )
}

private func feature18Tokens(
    accessToken: String,
    refreshToken: String,
    expiresAt: Date
) -> CloudSessionTokensDTO {
    CloudSessionTokensDTO(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessTokenExpiresAt: expiresAt
    )
}

private func feature18SignedInState(
    privacyRequests: [PrivacyRequestRecord] = [],
    consumerHealthConsents: [ConsumerHealthConsentRecord] = []
) -> AccountBackendContractState {
    AccountBackendContractState(
        knownAccounts: [
            UserAccount(
                id: feature18AccountID,
                appleUserID: "apple-user-1",
                displayName: "Alex",
                email: "alex@example.com",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                lastSignedInAt: Date(timeIntervalSince1970: 1_800_000_300),
                launchMode: .productionBackend
            )
        ],
        currentAccountID: feature18AccountID,
        privacyRequests: privacyRequests,
        consumerHealthConsents: consumerHealthConsents
    )
}

private enum TestCloudBackendClientError: Error {
    case missingStub
}

private final class TestCloudBackendClient: CloudBackendClient {
    var exchangeResponse: CloudAuthSessionResponse?
    var refreshResponse: CloudAuthSessionResponse?
    var privacyResponses: [PrivacyRequestType: CloudPrivacyRequestResponse] = [:]
    var consumerHealthConsentResponse: CloudPrivacyRequestResponse?
    var exportResponse: CloudAccountExportResponse?
    var deleteResponse: CloudPrivacyRequestResponse?

    var exchangedAppleIdentities: [CloudAuthExchangeRequest] = []
    var refreshedSessionRequests: [CloudSessionRefreshRequest] = []
    var submittedPrivacyRequests: [PrivacyRequestType] = []
    var consumerHealthConsentRequests: [CloudConsumerHealthConsentRequest] = []
    var consumerHealthConsentAccessTokens: [String] = []
    var exportedAccessTokens: [String] = []
    var deletedAccessTokens: [String] = []

    func exchangeAppleIdentity(_ request: CloudAuthExchangeRequest) async throws -> CloudAuthSessionResponse {
        exchangedAppleIdentities.append(request)
        guard let exchangeResponse else { throw TestCloudBackendClientError.missingStub }
        return exchangeResponse
    }

    func refreshSession(_ request: CloudSessionRefreshRequest) async throws -> CloudAuthSessionResponse {
        refreshedSessionRequests.append(request)
        guard let refreshResponse else { throw TestCloudBackendClientError.missingStub }
        return refreshResponse
    }

    func bootstrap(
        _ request: CloudSyncBootstrapRequest,
        accessToken: String
    ) async throws -> CloudSyncResponse {
        CloudSyncResponse(
            serverTime: Date(timeIntervalSince1970: 1_900_000_000),
            payload: CloudSyncBatchPayload(),
            cursors: []
        )
    }

    func push(
        _ request: CloudSyncPushRequest,
        accessToken: String
    ) async throws -> CloudSyncPushResponse {
        CloudSyncPushResponse(
            acceptedBatchID: request.batchID,
            payload: CloudSyncBatchPayload(),
            warnings: []
        )
    }

    func pull(
        _ request: CloudSyncPullRequest,
        accessToken: String
    ) async throws -> CloudSyncResponse {
        CloudSyncResponse(
            serverTime: Date(timeIntervalSince1970: 1_900_000_000),
            payload: CloudSyncBatchPayload(),
            cursors: []
        )
    }

    func submitPrivacyRequest(
        _ type: PrivacyRequestType,
        accessToken: String
    ) async throws -> CloudPrivacyRequestResponse {
        submittedPrivacyRequests.append(type)
        guard let response = privacyResponses[type] else {
            throw TestCloudBackendClientError.missingStub
        }
        return response
    }

    func setConsumerHealthConsent(
        _ request: CloudConsumerHealthConsentRequest,
        accessToken: String
    ) async throws -> CloudPrivacyRequestResponse {
        consumerHealthConsentRequests.append(request)
        consumerHealthConsentAccessTokens.append(accessToken)
        guard let consumerHealthConsentResponse else {
            throw TestCloudBackendClientError.missingStub
        }
        return consumerHealthConsentResponse
    }

    func fetchAccountExport(accessToken: String) async throws -> CloudAccountExportResponse {
        exportedAccessTokens.append(accessToken)
        guard let exportResponse else { throw TestCloudBackendClientError.missingStub }
        return exportResponse
    }

    func deleteAccount(accessToken: String) async throws -> CloudPrivacyRequestResponse {
        deletedAccessTokens.append(accessToken)
        guard let deleteResponse else { throw TestCloudBackendClientError.missingStub }
        return deleteResponse
    }
}
