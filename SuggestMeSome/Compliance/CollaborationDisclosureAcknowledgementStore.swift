import Foundation

enum CollaborationDisclosureAcknowledgementKind: String {
    case coachInvite
    case privateShare
    case visibilityScopes
}

enum CollaborationDisclosureAcknowledgementStore {
    static func isAcknowledged(
        _ kind: CollaborationDisclosureAcknowledgementKind,
        accountID: UUID?,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard let accountID else { return false }
        return userDefaults.bool(forKey: key(for: kind, accountID: accountID))
    }

    static func recordAcknowledgement(
        _ kind: CollaborationDisclosureAcknowledgementKind,
        accountID: UUID?,
        userDefaults: UserDefaults = .standard
    ) {
        guard let accountID else { return }
        userDefaults.set(true, forKey: key(for: kind, accountID: accountID))
    }

    static func key(
        for kind: CollaborationDisclosureAcknowledgementKind,
        accountID: UUID
    ) -> String {
        "collaboration.disclosure.\(kind.rawValue).\(ComplianceConfiguration.currentLegalVersion).\(accountID.uuidString)"
    }
}
