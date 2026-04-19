import Foundation
import Observation

enum AppDeepLinkRoute: Codable, Equatable, Hashable, Identifiable {
    case collaborationHub
    case coachInvite(stableID: String)
    case relationship(stableID: String)
    case assignment(stableID: String)
    case coachNote(stableID: String)
    case weeklyDigest(stableID: String)
    case insightSnapshot(stableID: String)
    case blueprint(stableID: String)
    case programShare(stableID: String)
    case progressShare(stableID: String)
    case coachRoster
    case notificationPreferences

    var id: String {
        switch self {
        case .collaborationHub:
            return "collaborationHub"
        case .coachInvite(let stableID):
            return "coachInvite::\(stableID)"
        case .relationship(let stableID):
            return "relationship::\(stableID)"
        case .assignment(let stableID):
            return "assignment::\(stableID)"
        case .coachNote(let stableID):
            return "coachNote::\(stableID)"
        case .weeklyDigest(let stableID):
            return "weeklyDigest::\(stableID)"
        case .insightSnapshot(let stableID):
            return "insightSnapshot::\(stableID)"
        case .blueprint(let stableID):
            return "blueprint::\(stableID)"
        case .programShare(let stableID):
            return "programShare::\(stableID)"
        case .progressShare(let stableID):
            return "progressShare::\(stableID)"
        case .coachRoster:
            return "coachRoster"
        case .notificationPreferences:
            return "notificationPreferences"
        }
    }

    var targetTab: MainTab {
        switch self {
        case .coachNote, .weeklyDigest:
            return .dailyCoach
        case .insightSnapshot, .progressShare:
            return .dashboard
        case .collaborationHub, .coachInvite, .relationship, .assignment, .blueprint, .programShare, .coachRoster:
            return .programs
        case .notificationPreferences:
            return .settings
        }
    }

    init?(url: URL) {
        guard let host = url.host else { return nil }
        let stableID = url.lastPathComponent

        switch host {
        case "collaboration":
            self = .collaborationHub
        case "invite":
            self = .coachInvite(stableID: stableID)
        case "relationship":
            self = .relationship(stableID: stableID)
        case "assignment":
            self = .assignment(stableID: stableID)
        case "note":
            self = .coachNote(stableID: stableID)
        case "digest":
            self = .weeklyDigest(stableID: stableID)
        case "insight":
            self = .insightSnapshot(stableID: stableID)
        case "blueprint":
            self = .blueprint(stableID: stableID)
        case "program-share":
            self = .programShare(stableID: stableID)
        case "progress-share":
            self = .progressShare(stableID: stableID)
        case "roster":
            self = .coachRoster
        case "notification-preferences":
            self = .notificationPreferences
        default:
            return nil
        }
    }

    static func fromNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> AppDeepLinkRoute? {
        if let rawURL = userInfo["deepLinkURL"] as? String,
           let url = URL(string: rawURL) {
            return AppDeepLinkRoute(url: url)
        }

        guard let target = userInfo["deepLinkTarget"] as? String else {
            return nil
        }

        let stableID = userInfo["stableID"] as? String ?? ""
        switch target {
        case "collaboration":
            return .collaborationHub
        case "invite":
            return .coachInvite(stableID: stableID)
        case "relationship":
            return .relationship(stableID: stableID)
        case "assignment":
            return .assignment(stableID: stableID)
        case "note":
            return .coachNote(stableID: stableID)
        case "digest":
            return .weeklyDigest(stableID: stableID)
        case "insight":
            return .insightSnapshot(stableID: stableID)
        case "blueprint":
            return .blueprint(stableID: stableID)
        case "programShare":
            return .programShare(stableID: stableID)
        case "progressShare":
            return .progressShare(stableID: stableID)
        case "roster":
            return .coachRoster
        case "notificationPreferences":
            return .notificationPreferences
        default:
            return nil
        }
    }
}

@MainActor
@Observable
final class AppRouteCoordinator {
    static let shared = AppRouteCoordinator()

    private(set) var activeRoute: AppDeepLinkRoute?

    func present(_ route: AppDeepLinkRoute) {
        activeRoute = route
    }

    func clearIfMatching(_ route: AppDeepLinkRoute?) {
        guard activeRoute == route else { return }
        activeRoute = nil
    }

    func clear() {
        activeRoute = nil
    }
}
