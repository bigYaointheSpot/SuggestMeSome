//
//  HealthKitAuthorizationService.swift
//  SuggestMeSome
//
//  Feature 8 — Explicit HealthKit availability and authorization flow.
//

import Foundation
import HealthKit

struct HealthKitAuthorizationSnapshot {
    enum Availability {
        case available
        case unavailable
    }

    let availability: Availability
    let readStatuses: [HKAuthorizationStatus]
    let workoutWriteStatus: HKAuthorizationStatus
    let requestStatus: HKAuthorizationRequestStatus?
    let hasRequestedAuthorization: Bool

    var hasAnyAuthorizedRead: Bool {
        readStatuses.contains(.sharingAuthorized)
    }

    var isWriteAuthorized: Bool {
        workoutWriteStatus == .sharingAuthorized
    }

    var isWorkoutWriteDenied: Bool {
        workoutWriteStatus == .sharingDenied
    }

    var hasCompletedAuthorizationFlow: Bool {
        hasRequestedAuthorization && requestStatus == .unnecessary
    }

    var hasAnyDeniedScope: Bool {
        isWorkoutWriteDenied && !isConnected
    }

    var isConnected: Bool {
        availability == .available && (hasAnyAuthorizedRead || isWriteAuthorized || hasCompletedAuthorizationFlow)
    }

    var isDenied: Bool {
        guard availability == .available else { return false }
        guard hasRequestedAuthorization else { return false }
        return !isConnected && (requestStatus == .unnecessary || isWorkoutWriteDenied)
    }

    var canPresentAuthorizationPrompt: Bool {
        availability == .available && requestStatus != .unnecessary
    }
}

final class HealthKitAuthorizationService {
    private let healthStore = HKHealthStore()

    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization(hasRequestedAuthorization: Bool) async -> HealthKitAuthorizationSnapshot {
        guard isHealthDataAvailable() else {
            return HealthKitAuthorizationSnapshot(
                availability: .unavailable,
                readStatuses: [],
                workoutWriteStatus: .notDetermined,
                requestStatus: nil,
                hasRequestedAuthorization: hasRequestedAuthorization
            )
        }

        _ = await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(
                toShare: HealthKitTypeCatalog.workoutWriteTypes,
                read: HealthKitTypeCatalog.recoveryReadTypes
            ) { _, _ in
                continuation.resume(returning: ())
            }
        }

        return await refreshAuthorizationStatus(hasRequestedAuthorization: true)
    }

    func refreshAuthorizationStatus(hasRequestedAuthorization: Bool) async -> HealthKitAuthorizationSnapshot {
        guard isHealthDataAvailable() else {
            return HealthKitAuthorizationSnapshot(
                availability: .unavailable,
                readStatuses: [],
                workoutWriteStatus: .notDetermined,
                requestStatus: nil,
                hasRequestedAuthorization: hasRequestedAuthorization
            )
        }

        let readStatuses = HealthKitTypeCatalog.recoveryReadTypes.map { type in
            healthStore.authorizationStatus(for: type)
        }
        let workoutWriteStatus = healthStore.authorizationStatus(for: HealthKitTypeCatalog.workoutType)

        let requestStatus = await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: HealthKitTypeCatalog.workoutWriteTypes,
                read: HealthKitTypeCatalog.recoveryReadTypes
            ) { status, _ in
                continuation.resume(returning: status)
            }
        }

        return HealthKitAuthorizationSnapshot(
            availability: .available,
            readStatuses: readStatuses,
            workoutWriteStatus: workoutWriteStatus,
            requestStatus: requestStatus,
            hasRequestedAuthorization: hasRequestedAuthorization
        )
    }
}
