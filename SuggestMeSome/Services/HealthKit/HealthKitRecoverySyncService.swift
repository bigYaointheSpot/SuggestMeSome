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

        let window = makeWindow(referenceDate: referenceDate)
        let windowStart = window.start
        let windowEnd = window.end
        let days = makeDayStarts(from: window.start, to: window.end)

        let sleepByDay = await fetchSleepByDay(start: window.start, end: window.end)
        let restingHeartRateByDay = await fetchDiscreteAverageByDay(
            type: HealthKitTypeCatalog.restingHeartRateType,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: window.start,
            end: window.end
        )
        let hrvByDay = await fetchDiscreteAverageByDay(
            type: HealthKitTypeCatalog.heartRateVariabilityType,
            unit: .secondUnit(with: .milli),
            start: window.start,
            end: window.end
        )
        let activeEnergyByDay = await fetchCumulativeSumByDay(
            type: HealthKitTypeCatalog.activeEnergyType,
            unit: .kilocalorie(),
            start: window.start,
            end: window.end
        )
        let stepsByDay = await fetchCumulativeSumByDay(
            type: HealthKitTypeCatalog.stepCountType,
            unit: .count(),
            start: window.start,
            end: window.end
        )
        let bodyMassByDay = await fetchDiscreteAverageByDay(
            type: HealthKitTypeCatalog.bodyMassType,
            unit: .gramUnit(with: .kilo),
            start: window.start,
            end: window.end
        )

        let snapshots = days.map { dayStart in
            let sleepTotals = sleepByDay[dayStart]
            return HealthKitDailySummarySnapshot(
                dayStart: dayStart,
                sleepDurationSeconds: sleepTotals.map { Int($0.sleepDurationSeconds.rounded()) },
                timeInBedSeconds: sleepTotals.map { Int($0.timeInBedSeconds.rounded()) },
                restingHeartRateBPM: restingHeartRateByDay[dayStart],
                heartRateVariabilityMS: hrvByDay[dayStart],
                activeEnergyKilocalories: activeEnergyByDay[dayStart],
                stepCount: stepsByDay[dayStart],
                bodyMassKilograms: bodyMassByDay[dayStart]
            )
        }

        _ = try upsertDailySummaries(
            context: context,
            snapshots: snapshots,
            rangeStart: windowStart,
            rangeEnd: windowEnd
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
        let targetDays = Set(snapshots.map { calendar.startOfDay(for: $0.dayStart) })

        let descriptor: FetchDescriptor<HealthKitDailySummary>
        if let rangeStart, let rangeEnd {
            descriptor = FetchDescriptor<HealthKitDailySummary>(
                predicate: #Predicate { summary in
                    summary.dayStart >= rangeStart && summary.dayStart <= rangeEnd
                }
            )
        } else if let minDay = targetDays.min(), let maxDay = targetDays.max() {
            descriptor = FetchDescriptor<HealthKitDailySummary>(
                predicate: #Predicate { summary in
                    summary.dayStart >= minDay && summary.dayStart <= maxDay
                }
            )
        } else {
            descriptor = FetchDescriptor<HealthKitDailySummary>()
        }

        let existingRows = (try? context.fetch(descriptor)) ?? []
        var existingByDayStart: [Date: HealthKitDailySummary] = [:]
        for row in existingRows {
            existingByDayStart[calendar.startOfDay(for: row.dayStart)] = row
        }

        var inserted = 0
        var updated = 0
        for snapshot in snapshots {
            let dayStart = calendar.startOfDay(for: snapshot.dayStart)
            if let row = existingByDayStart[dayStart] {
                row.sleepDurationSeconds = snapshot.sleepDurationSeconds
                row.timeInBedSeconds = snapshot.timeInBedSeconds
                row.restingHeartRateBPM = snapshot.restingHeartRateBPM
                row.heartRateVariabilityMS = snapshot.heartRateVariabilityMS
                row.activeEnergyKilocalories = snapshot.activeEnergyKilocalories
                row.stepCount = snapshot.stepCount
                row.bodyMassKilograms = snapshot.bodyMassKilograms
                row.sourceUpdatedAt = sourceUpdatedAt
                row.updatedAt = sourceUpdatedAt
                updated += 1
            } else {
                context.insert(
                    HealthKitDailySummary(
                        dayStart: dayStart,
                        sleepDurationSeconds: snapshot.sleepDurationSeconds,
                        timeInBedSeconds: snapshot.timeInBedSeconds,
                        restingHeartRateBPM: snapshot.restingHeartRateBPM,
                        heartRateVariabilityMS: snapshot.heartRateVariabilityMS,
                        activeEnergyKilocalories: snapshot.activeEnergyKilocalories,
                        stepCount: snapshot.stepCount,
                        bodyMassKilograms: snapshot.bodyMassKilograms,
                        sourceUpdatedAt: sourceUpdatedAt,
                        createdAt: sourceUpdatedAt,
                        updatedAt: sourceUpdatedAt
                    )
                )
                inserted += 1
            }
        }

        try context.save()
        return HealthKitDailySummaryUpsertResult(inserted: inserted, updated: updated)
    }

    private func makeWindow(referenceDate: Date) -> (start: Date, end: Date) {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -89, to: todayStart) ?? todayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return (start: start, end: tomorrowStart)
    }

    private func makeDayStarts(from start: Date, to end: Date) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while cursor < endDay {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private func fetchSleepByDay(start: Date, end: Date) async -> [Date: SleepTotals] {
        guard let type = HealthKitTypeCatalog.sleepAnalysisType else { return [:] }
        guard isAuthorizedToRead(type) else { return [:] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { [weak self] _, samples, _ in
                guard let self else {
                    continuation.resume(returning: [:])
                    return
                }
                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [:])
                    return
                }

                var totals: [Date: SleepTotals] = [:]
                for sample in categorySamples {
                    let sampleStart = max(sample.startDate, start)
                    let sampleEnd = min(sample.endDate, end)
                    guard sampleStart < sampleEnd else { continue }

                    var cursor = self.calendar.startOfDay(for: sampleStart)
                    while cursor < sampleEnd {
                        guard let nextDay = self.calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                        let overlapStart = max(sampleStart, cursor)
                        let overlapEnd = min(sampleEnd, nextDay)
                        let seconds = overlapEnd.timeIntervalSince(overlapStart)

                        if seconds > 0 {
                            let dayStart = self.calendar.startOfDay(for: cursor)
                            var dayTotals = totals[dayStart] ?? SleepTotals()
                            if self.isInBedSample(sample.value) {
                                dayTotals.timeInBedSeconds += seconds
                            }
                            if self.isAsleepSample(sample.value) {
                                dayTotals.sleepDurationSeconds += seconds
                            }
                            totals[dayStart] = dayTotals
                        }

                        cursor = nextDay
                    }
                }

                continuation.resume(returning: totals)
            }
            self.healthStore.execute(query)
        }
    }

    private func fetchCumulativeSumByDay(
        type: HKQuantityType?,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [Date: Double] {
        guard let type else { return [:] }
        guard isAuthorizedToRead(type) else { return [:] }
        return await fetchStatisticsByDay(type: type, options: .cumulativeSum, unit: unit, start: start, end: end)
    }

    private func fetchDiscreteAverageByDay(
        type: HKQuantityType?,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [Date: Double] {
        guard let type else { return [:] }
        guard isAuthorizedToRead(type) else { return [:] }
        return await fetchStatisticsByDay(type: type, options: .discreteAverage, unit: unit, start: start, end: end)
    }

    private func fetchStatisticsByDay(
        type: HKQuantityType,
        options: HKStatisticsOptions,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let interval = DateComponents(day: 1)
        let anchorDate = calendar.startOfDay(for: start)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { [weak self] _, collection, _ in
                guard self != nil, let collection else {
                    continuation.resume(returning: [:])
                    return
                }

                var values: [Date: Double] = [:]
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let dayStart = self?.calendar.startOfDay(for: statistics.startDate) ?? statistics.startDate
                    if options.contains(.cumulativeSum), let quantity = statistics.sumQuantity() {
                        values[dayStart] = quantity.doubleValue(for: unit)
                    } else if options.contains(.discreteAverage), let quantity = statistics.averageQuantity() {
                        values[dayStart] = quantity.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: values)
            }

            self.healthStore.execute(query)
        }
    }

    private func isAuthorizedToRead(_ type: HKObjectType) -> Bool {
        healthStore.authorizationStatus(for: type) != .sharingDenied
    }

    private func isInBedSample(_ rawValue: Int) -> Bool {
        HKCategoryValueSleepAnalysis(rawValue: rawValue) == .inBed
    }

    private func isAsleepSample(_ rawValue: Int) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: rawValue) else {
            return false
        }
        switch value {
        case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        default:
            return false
        }
    }
}

private struct SleepTotals {
    var sleepDurationSeconds: TimeInterval = 0
    var timeInBedSeconds: TimeInterval = 0
}
