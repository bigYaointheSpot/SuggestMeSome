import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
struct Feature21LegalAndScopeHardeningTests {

    @Test func hostedLegalPagesStayAlignedWithAppDisclosureAnchors() throws {
        let pages = try hostedLegalPages()
        let anchors = [
            ComplianceConfiguration.currentLegalVersion,
            ComplianceConfiguration.legalEffectiveDateText,
            ComplianceConfiguration.supportEmail,
            ComplianceConfiguration.privacyEmail,
            "Apple Health-derived recovery data stays on device",
            "not sent to CloudKit or the sync backend",
            "does not include ads or third-party analytics",
            "Premium Unlock is a one-time",
            "privacy request is denied",
            "Withdraw Consumer Health Data consent"
        ]

        for (path, html) in pages {
            for anchor in anchors {
                #expect(
                    html.contains(anchor),
                    "Expected \(path) to contain legal anchor: \(anchor)"
                )
            }
        }
    }

    @Test func cloudSyncPayloadDoesNotExportHealthKitDailySummaries() throws {
        let payload = CloudSyncBatchPayload()
        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? ""

        #expect(!json.contains("healthKit"))
        #expect(!json.contains("HealthKitDailySummary"))
    }

    @Test func mainAppEntitlementIncludesWatchWidgetAppGroup() throws {
        let entitlementText = try repoText(at: "SuggestMeSome/SuggestMeSome.entitlements")
        #expect(entitlementText.contains("com.apple.security.application-groups"))
        #expect(entitlementText.contains("group.com.alexyao.SuggestMeSome"))
    }

    @Test func healthKitDailySummariesAreExcludedFromSyncMetadataAudit() throws {
        let syncSupport = try repoText(at: "SuggestMeSome/SyncContracts/SyncMetadataSupport.swift")
        let auditService = try repoText(at: "SuggestMeSome/Services/Persistence/SyncMetadataAuditService.swift")
        let healthKitRecoverySupport = try repoText(at: "SuggestMeSome/Services/HealthKit/HealthKitRecoverySyncSupport.swift")

        #expect(!syncSupport.contains("extension HealthKitDailySummary: SyncTrackableModel"))
        #expect(!auditService.contains("audit(HealthKitDailySummary.self"))
        #expect(!healthKitRecoverySupport.contains("markSyncUpdated"))
    }

    @Test func portableBackupDisclosureNamesLocalHealthSummaryScope() throws {
        let exportView = try repoText(at: "SuggestMeSome/Views/Settings/DataExportView.swift")

        #expect(exportView.contains("user-initiated local file export"))
        #expect(exportView.contains("single unencrypted JSON file"))
        #expect(exportView.contains("cached Apple Health-derived recovery summaries"))
        #expect(exportView.contains("not sent to CloudKit or the backend"))
    }

    @Test func collaborationDisclosureAcknowledgementsAreAccountAndVersionScoped() {
        let suiteName = "Feature21Disclosure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let accountID = UUID(uuidString: "21000000-0000-0000-0000-000000000001")!
        let otherAccountID = UUID(uuidString: "21000000-0000-0000-0000-000000000002")!

        #expect(!CollaborationDisclosureAcknowledgementStore.isAcknowledged(
            .coachInvite,
            accountID: accountID,
            userDefaults: defaults
        ))

        CollaborationDisclosureAcknowledgementStore.recordAcknowledgement(
            .coachInvite,
            accountID: accountID,
            userDefaults: defaults
        )

        #expect(CollaborationDisclosureAcknowledgementStore.isAcknowledged(
            .coachInvite,
            accountID: accountID,
            userDefaults: defaults
        ))
        #expect(!CollaborationDisclosureAcknowledgementStore.isAcknowledged(
            .coachInvite,
            accountID: otherAccountID,
            userDefaults: defaults
        ))
        #expect(CollaborationDisclosureAcknowledgementStore.key(
            for: .coachInvite,
            accountID: accountID
        ).contains(ComplianceConfiguration.currentLegalVersion))
    }
}

private func hostedLegalPages() throws -> [(String, String)] {
    let paths = Set(
        ComplianceConfiguration.legalDocuments
            .compactMap(\.hostedURL)
            .map { url in
                let hostedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return hostedPath.isEmpty ? "website/index.html" : "website/\(hostedPath)/index.html"
            }
    )

    return try paths.sorted().map { path in
        (path, try repoText(at: path))
    }
}

private func repoText(at relativePath: String) throws -> String {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = testsDirectory.deletingLastPathComponent()
    let url = repoRoot.appending(path: relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}
