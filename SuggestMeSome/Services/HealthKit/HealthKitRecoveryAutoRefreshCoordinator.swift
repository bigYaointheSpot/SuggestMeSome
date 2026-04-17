//
//  HealthKitRecoveryAutoRefreshCoordinator.swift
//  SuggestMeSome
//
//  Foreground/Daily Coach recovery refresh policy + coordination.
//

import Foundation
import SwiftData

enum HealthKitSettingsStorage {
    static let healthKitEnabledKey = "healthkit.enabled"
    static let dailyCoachEnabledKey = "healthkit.dailyCoachEnabled"
    static let recoveryLastSyncTimestampKey = "healthkit.recoveryLastSyncTimestamp"
    static let workoutImportLastSyncTimestampKey = "healthkit.workoutImportLastSyncTimestamp"
    static let recoveryLastAutoRefreshTimestampKey = "healthkit.recoveryLastAutoRefreshTimestamp"
    static let legacyLastSyncTimestampKey = "healthkit.lastSyncTimestamp"

    static func bool(forKey key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func date(forKey key: String, defaults: UserDefaults = .standard) -> Date? {
        let timestamp = defaults.double(forKey: key)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func setDate(_ date: Date?, forKey key: String, defaults: UserDefaults = .standard) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    @MainActor
    static func migrateLegacyRecoverySyncTimestampIfNeeded(
        defaults: UserDefaults = .standard,
        context: ModelContext
    ) {
        guard defaults.object(forKey: recoveryLastSyncTimestampKey) == nil else {
            return
        }

        guard let legacyDate = date(forKey: legacyLastSyncTimestampKey, defaults: defaults) else {
            return
        }

        var descriptor = FetchDescriptor<HealthKitDailySummary>()
        descriptor.fetchLimit = 1
        let hasRecoverySummaries = ((try? context.fetch(descriptor)) ?? []).isEmpty == false
        guard hasRecoverySummaries else { return }

        setDate(legacyDate, forKey: recoveryLastSyncTimestampKey, defaults: defaults)
    }
}

enum HealthKitRecoveryRefreshTrigger: Equatable {
    case appDidBecomeActive
    case dailyCoachOpened
    case authorizationStatusUpdated
}

enum HealthKitRecoveryAutoRefreshSkipReason: Equatable {
    case disabled
    case alreadyFresh
    case waitingForRetryWindow
    case refreshInProgress
    case syncFailed
}

enum HealthKitRecoveryAutoRefreshAction: Equatable {
    case skip(HealthKitRecoveryAutoRefreshSkipReason)
    case syncLastDays(Int)
}

struct HealthKitRecoveryAutoRefreshDecisionInput: Equatable {
    let trigger: HealthKitRecoveryRefreshTrigger
    let now: Date
    let healthKitEnabled: Bool
    let useHealthKitInDailyCoach: Bool
    let hasLocalSummaries: Bool
    let hasComparableCurrentDaySummary: Bool
    let lastSuccessfulRecoverySyncAt: Date?
    let lastAutoRefreshAt: Date?
}

enum HealthKitRecoveryAutoRefreshPolicy {
    static let bootstrapDayCount = 90
    static let foregroundRefreshDayCount = 30
    static let dailyCoachRetryInterval: TimeInterval = 4 * 60 * 60

    static func decide(
        _ input: HealthKitRecoveryAutoRefreshDecisionInput,
        calendar: Calendar = .current
    ) -> HealthKitRecoveryAutoRefreshAction {
        guard input.healthKitEnabled, input.useHealthKitInDailyCoach else {
            return .skip(.disabled)
        }

        guard input.hasLocalSummaries, input.lastSuccessfulRecoverySyncAt != nil else {
            return .syncLastDays(bootstrapDayCount)
        }

        let nowDay = calendar.startOfDay(for: input.now)
        let lastSyncDay = input.lastSuccessfulRecoverySyncAt.map { calendar.startOfDay(for: $0) }

        switch input.trigger {
        case .appDidBecomeActive, .authorizationStatusUpdated:
            if lastSyncDay == nil || lastSyncDay! < nowDay {
                return .syncLastDays(foregroundRefreshDayCount)
            }
            return .skip(.alreadyFresh)

        case .dailyCoachOpened:
            if lastSyncDay == nil || lastSyncDay! < nowDay {
                return .syncLastDays(foregroundRefreshDayCount)
            }
            if input.hasComparableCurrentDaySummary {
                return .skip(.alreadyFresh)
            }
            if let lastAutoRefreshAt = input.lastAutoRefreshAt,
               input.now.timeIntervalSince(lastAutoRefreshAt) < dailyCoachRetryInterval {
                return .skip(.waitingForRetryWindow)
            }
            return .syncLastDays(foregroundRefreshDayCount)
        }
    }
}

enum HealthKitRecoveryAutoRefreshOutcome: Equatable {
    case skipped(HealthKitRecoveryAutoRefreshSkipReason)
    case synced(dayCount: Int, syncedAt: Date)
    case failed

    var didSync: Bool {
        if case .synced(_, _) = self {
            return true
        }
        return false
    }
}

@MainActor
protocol HealthKitRecoverySyncing {
    func syncLastDays(
        context: ModelContext,
        days: Int,
        referenceDate: Date
    ) async throws
}

@MainActor
final class HealthKitRecoveryAutoRefreshCoordinator {
    static let shared = HealthKitRecoveryAutoRefreshCoordinator()

    private let syncService: HealthKitRecoverySyncing
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private var refreshTask: Task<HealthKitRecoveryAutoRefreshOutcome, Never>?

    init(
        syncService: HealthKitRecoverySyncing = HealthKitRecoverySyncService(),
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.syncService = syncService
        self.userDefaults = userDefaults
        self.calendar = calendar
    }

    func refreshIfNeeded(
        trigger: HealthKitRecoveryRefreshTrigger,
        context: ModelContext,
        now: Date = Date()
    ) async -> HealthKitRecoveryAutoRefreshOutcome {
        if let refreshTask {
            return await refreshTask.value
        }

        let decision = HealthKitRecoveryAutoRefreshPolicy.decide(
            HealthKitRecoveryAutoRefreshDecisionInput(
                trigger: trigger,
                now: now,
                healthKitEnabled: HealthKitSettingsStorage.bool(
                    forKey: HealthKitSettingsStorage.healthKitEnabledKey,
                    defaults: userDefaults
                ),
                useHealthKitInDailyCoach: HealthKitSettingsStorage.bool(
                    forKey: HealthKitSettingsStorage.dailyCoachEnabledKey,
                    defaults: userDefaults
                ),
                hasLocalSummaries: hasAnyRecoverySummaries(context: context),
                hasComparableCurrentDaySummary: hasComparableCurrentDaySummary(
                    context: context,
                    referenceDate: now
                ),
                lastSuccessfulRecoverySyncAt: HealthKitSettingsStorage.date(
                    forKey: HealthKitSettingsStorage.recoveryLastSyncTimestampKey,
                    defaults: userDefaults
                ),
                lastAutoRefreshAt: HealthKitSettingsStorage.date(
                    forKey: HealthKitSettingsStorage.recoveryLastAutoRefreshTimestampKey,
                    defaults: userDefaults
                )
            ),
            calendar: calendar
        )

        switch decision {
        case .skip(let reason):
            return HealthKitRecoveryAutoRefreshOutcome.skipped(reason)
        case .syncLastDays(let dayCount):
            let task = Task<HealthKitRecoveryAutoRefreshOutcome, Never> { @MainActor in
                do {
                    try await syncService.syncLastDays(
                        context: context,
                        days: dayCount,
                        referenceDate: now
                    )
                    let syncedAt = Date()
                    HealthKitSettingsStorage.setDate(
                        syncedAt,
                        forKey: HealthKitSettingsStorage.recoveryLastSyncTimestampKey,
                        defaults: userDefaults
                    )
                    HealthKitSettingsStorage.setDate(
                        syncedAt,
                        forKey: HealthKitSettingsStorage.recoveryLastAutoRefreshTimestampKey,
                        defaults: userDefaults
                    )
                    return HealthKitRecoveryAutoRefreshOutcome.synced(
                        dayCount: dayCount,
                        syncedAt: syncedAt
                    )
                } catch {
                    return HealthKitRecoveryAutoRefreshOutcome.failed
                }
            }

            refreshTask = task
            let outcome = await task.value
            refreshTask = nil
            return outcome
        }
    }

    private func hasAnyRecoverySummaries(context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<HealthKitDailySummary>()
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    private func hasComparableCurrentDaySummary(
        context: ModelContext,
        referenceDate: Date
    ) -> Bool {
        let descriptor = FetchDescriptor<HealthKitDailySummary>(
            sortBy: [SortDescriptor(\.dayStart, order: .reverse)]
        )
        let summaries = (try? context.fetch(descriptor)) ?? []
        return HealthKitRecoveryInsightService.hasComparableCurrentDaySummary(
            from: summaries,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }
}
