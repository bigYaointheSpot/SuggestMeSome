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
            ComplianceConfiguration.cloudSyncStorageDisclosure.contains("CloudKit")
        )

        let privacyPolicy = ComplianceConfiguration.document(for: .privacyPolicy)
        let consumerHealthNotice = ComplianceConfiguration.document(for: .consumerHealthNotice)
        let supportDocument = ComplianceConfiguration.document(for: .support)

        #expect(!privacyPolicy.containsPlaceholders)
        #expect(ComplianceConfiguration.sellerName == "Alexander Yao")
        #expect(ComplianceConfiguration.supportEmail == "support@suggestmesome.app")
        #expect(ComplianceConfiguration.privacyEmail == "privacy@suggestmesome.app")
        #expect(ComplianceConfiguration.websiteURL.absoluteString == "https://www.suggestmesome.app")
        #expect(privacyPolicy.bodyMarkdown.contains("published by **\(ComplianceConfiguration.sellerName)**"))
        #expect(consumerHealthNotice.bodyMarkdown.contains("does not use Apple Health data for advertising"))
        #expect(consumerHealthNotice.bodyMarkdown.contains("Washington residents"))
        #expect(supportDocument.bodyMarkdown.contains("local contract-validation"))
        #expect(
            ComplianceConfiguration.releaseGateChecklist.contains(where: { $0.contains("production backend") })
        )
        #expect(
            ComplianceConfiguration.legalDocuments.allSatisfy { !$0.containsPlaceholders }
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
}
