//
//  ComplianceStateStore.swift
//  SuggestMeSome
//
//  Feature 14 - Persistent onboarding and legal-acceptance state.
//

import Foundation
import Observation

struct ComplianceOnboardingState: Codable, Equatable {
    var confirmedAdultAt: Date?
    var acknowledgedWellnessDisclaimerAt: Date?
    var acknowledgedAutomationDisclosureAt: Date?
    var acceptedDocumentRecords: [LegalDocumentRecord]
    var completedAt: Date?

    init(
        confirmedAdultAt: Date? = nil,
        acknowledgedWellnessDisclaimerAt: Date? = nil,
        acknowledgedAutomationDisclosureAt: Date? = nil,
        acceptedDocumentRecords: [LegalDocumentRecord] = [],
        completedAt: Date? = nil
    ) {
        self.confirmedAdultAt = confirmedAdultAt
        self.acknowledgedWellnessDisclaimerAt = acknowledgedWellnessDisclaimerAt
        self.acknowledgedAutomationDisclosureAt = acknowledgedAutomationDisclosureAt
        self.acceptedDocumentRecords = acceptedDocumentRecords
        self.completedAt = completedAt
    }

    var acceptedDocumentIDs: Set<String> {
        Set(acceptedDocumentRecords.map(\.documentID))
    }

    func hasAcceptedRequiredDocuments(using configuration: ComplianceConfiguration.Type = ComplianceConfiguration.self) -> Bool {
        configuration.requiredOnboardingDocumentIDs.isSubset(of: acceptedDocumentIDs)
    }

    func isComplete(using configuration: ComplianceConfiguration.Type = ComplianceConfiguration.self) -> Bool {
        confirmedAdultAt != nil &&
        acknowledgedWellnessDisclaimerAt != nil &&
        acknowledgedAutomationDisclosureAt != nil &&
        hasAcceptedRequiredDocuments(using: configuration) &&
        completedAt != nil
    }
}

@MainActor
@Observable
final class ComplianceStateStore {
    static let shared = ComplianceStateStore()

    static let persistenceKey = "compliance.onboarding.state.v1"

    private let userDefaults: UserDefaults

    var onboardingState: ComplianceOnboardingState {
        didSet {
            persist()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.persistenceKey),
           let decoded = try? JSONDecoder().decode(ComplianceOnboardingState.self, from: data) {
            self.onboardingState = decoded
        } else {
            self.onboardingState = ComplianceOnboardingState()
        }
    }

    var hasCompletedRequiredOnboarding: Bool {
        onboardingState.isComplete()
    }

    func confirmAdult(at date: Date = Date()) {
        onboardingState.confirmedAdultAt = date
    }

    func acknowledgeWellnessDisclaimer(at date: Date = Date()) {
        onboardingState.acknowledgedWellnessDisclaimerAt = date
    }

    func acknowledgeAutomationDisclosure(at date: Date = Date()) {
        onboardingState.acknowledgedAutomationDisclosureAt = date
    }

    func acceptRequiredDocuments(at date: Date = Date()) {
        let existingByID = Dictionary(
            uniqueKeysWithValues: onboardingState.acceptedDocumentRecords.map { ($0.documentID, $0) }
        )

        var merged = existingByID
        for documentID in ComplianceConfiguration.requiredOnboardingDocumentIDs {
            merged[documentID] = LegalDocumentRecord(documentID: documentID, acceptedAt: date)
        }

        onboardingState.acceptedDocumentRecords = merged.values.sorted { $0.documentID < $1.documentID }
    }

    func markCompleted(at date: Date = Date()) {
        onboardingState.completedAt = date
    }

    func reset() {
        onboardingState = ComplianceOnboardingState()
    }

    func reloadFromPersistence() {
        if let data = userDefaults.data(forKey: Self.persistenceKey),
           let decoded = try? JSONDecoder().decode(ComplianceOnboardingState.self, from: data) {
            onboardingState = decoded
        } else {
            onboardingState = ComplianceOnboardingState()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(onboardingState) else { return }
        userDefaults.set(data, forKey: Self.persistenceKey)
    }
}
