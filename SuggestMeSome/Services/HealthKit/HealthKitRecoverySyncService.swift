//
//  HealthKitRecoverySyncService.swift
//  SuggestMeSome
//
//  Feature 8 — Import HealthKit recovery metrics into local daily summaries.
//

import Foundation
import SwiftData
import HealthKit

enum HealthKitRecoverySyncError: Error {
    case healthDataUnavailable
}

struct HealthKitDailySummarySnapshot {
    let dayStart: Date
    let sleepDurationSeconds: Int?
    let timeInBedSeconds: Int?
    let restingHeartRateBPM: Double?
    let heartRateVariabilityMS: Double?
    let activeEnergyKilocalories: Double?
    let stepCount: Double?
    let bodyMassKilograms: Double?
}

struct HealthKitDailySummaryUpsertResult {
    let inserted: Int
    let updated: Int
}

final class HealthKitRecoverySyncService {
    private let healthStore: HKHealthStore
    private let calendar: Calendar

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        calendar: Calendar = .current
    ) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    @MainActor
    func syncLast90Days(context: ModelContext, referenceDate: Date = Date()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitRecoverySyncError.healthDataUnavailable
        }

        let window = HealthKitRecoveryWindow.makeLast90Days(
            referenceDate: referenceDate,
            calendar: calendar
        )
        let days = HealthKitRecoveryWindow.makeDayStarts(
            from: window.start,
            to: window.end,
            calendar: calendar
        )
        let queryClient = HealthKitRecoveryQueryClient(
            healthStore: healthStore,
            calendar: calendar
        )

        async let sleepByDay = queryClient.fetchSleepByDay(start: window.start, end: window.end)
        async let restingHeartRateByDay = queryClient.fetchDiscreteAverageByDay(
            type: HealthKitTypeCatalog.restingHeartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: window.start,
            end: window.end
        )
        async let hrvByDay = queryClient.fetchDiscreteAverageByDay(
            type: HealthKitTypeCatalog.heartRateVariabilityType,
            unit: .secondUnit(with: .milli),
            start: window.start,
            end: window.end
        )
        async let activeEnergyByDay = queryClient.fetchCumulativeSumByDay(
            type: HealthKitTypeCatalog.activeEnergyType,
            unit: .kilocalorie(),
            start: window.start,
            end: window.end
        )
        async let stepsByDay = queryClient.fetchCumulativeSumByDay(
            type: HealthKitTypeCatalog.stepCountType,
            unit: .count(),
            start: window.start,
            end: window.end
        )
        async let bodyMassByDay = queryClient.fetchDiscreteAverageByDay(
            type: HealthKitTypeCatalog.bodyMassType,
            unit: .gramUnit(with: .kilo),
            start: window.start,
            end: window.end
        )

        let snapshots = await HealthKitRecoverySnapshotBuilder.makeSnapshots(
            days: days,
            sleepByDay: sleepByDay,
            restingHeartRateByDay: restingHeartRateByDay,
            heartRateVariabilityByDay: hrvByDay,
            activeEnergyByDay: activeEnergyByDay,
            stepsByDay: stepsByDay,
            bodyMassByDay: bodyMassByDay
        )

        _ = try upsertDailySummaries(
            context: context,
            snapshots: snapshots,
            rangeStart: window.start,
            rangeEnd: window.end
        )
    }

    @MainActor
    @discardableResult
    func upsertDailySummaries(
        context: ModelContext,
        snapshots: [HealthKitDailySummarySnapshot],
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil,
        sourceUpdatedAt: Date = Date()
    ) throws -> HealthKitDailySummaryUpsertResult {
        try HealthKitRecoveryPersistence.upsertDailySummaries(
            context: context,
            snapshots: snapshots,
            calendar: calendar,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            sourceUpdatedAt: sourceUpdatedAt
        )
    }
}
