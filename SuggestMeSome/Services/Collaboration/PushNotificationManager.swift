import Foundation
import Observation
import UIKit
import UserNotifications

final class CollaborationPushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRegistrationError(error)
        }
    }
}

@MainActor
@Observable
final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    private weak var collaborationCoordinator: CollaborationCoordinator?
    private weak var routeCoordinator: AppRouteCoordinator?

    private(set) var authorizationState: CollaborationPushAuthorizationState = .notDetermined
    private(set) var deviceTokenHex: String?
    private(set) var lastErrorMessage: String?
    private(set) var lastNudgeExplanation: CollaborationNudgeExplanationDTO?

    func configure(
        collaborationCoordinator: CollaborationCoordinator,
        routeCoordinator: AppRouteCoordinator
    ) {
        guard !AppBuildEnvironment.isLocalDevicePersonalTeam else {
            return
        }
        self.collaborationCoordinator = collaborationCoordinator
        self.routeCoordinator = routeCoordinator
        UNUserNotificationCenter.current().delegate = self

        Task {
            await refreshAuthorizationStatus()
            await collaborationCoordinator.handlePushAuthorizationStateChange(
                authorizationState,
                deviceToken: deviceTokenHex
            )
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationState = CollaborationPushAuthorizationState(settings.authorizationStatus)
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard !AppBuildEnvironment.isLocalDevicePersonalTeam else {
            lastErrorMessage = "Push notifications are disabled in Local Device builds."
            return false
        }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await refreshAuthorizationStatus()
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await collaborationCoordinator?.handlePushAuthorizationStateChange(
                authorizationState,
                deviceToken: deviceTokenHex
            )
            return granted
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        deviceTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastErrorMessage = nil
        Task {
            await collaborationCoordinator?.handlePushAuthorizationStateChange(
                authorizationState,
                deviceToken: deviceTokenHex
            )
        }
    }

    func handleRegistrationError(_ error: Error) {
        lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        Task {
            await collaborationCoordinator?.recordPushRegistrationError(lastErrorMessage ?? "Push registration failed.")
        }
    }

    fileprivate func handleNotificationPayload(_ userInfo: [AnyHashable: Any]) {
        if let route = AppDeepLinkRoute.fromNotificationUserInfo(userInfo) {
            routeCoordinator?.present(route)
        }
        lastNudgeExplanation = Self.decodeNudgeExplanation(from: userInfo)
    }

    private static func decodeNudgeExplanation(
        from userInfo: [AnyHashable: Any]
    ) -> CollaborationNudgeExplanationDTO? {
        if let raw = userInfo["nudgeExplanationJSON"] as? String,
           let data = raw.data(using: .utf8),
           let dto = try? JSONDecoder.iso8601.decode(CollaborationNudgeExplanationDTO.self, from: data) {
            return dto
        }

        guard let category = userInfo["nudgeCategory"] as? String,
              let title = userInfo["nudgeTitle"] as? String,
              let explanation = userInfo["nudgeExplanation"] as? String else {
            return nil
        }

        return CollaborationNudgeExplanationDTO(
            categoryRawValue: category,
            title: title,
            explanation: explanation,
            triggeredAt: .now,
            anchorStableID: userInfo["stableID"] as? String
        )
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            handleNotificationPayload(notification.request.content.userInfo)
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            handleNotificationPayload(response.notification.request.content.userInfo)
        }
    }
}

private extension CollaborationPushAuthorizationState {
    init(_ authorizationStatus: UNAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .notDetermined
        }
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
