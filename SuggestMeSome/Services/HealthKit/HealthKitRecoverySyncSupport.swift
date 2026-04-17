import Foundation
import SwiftData
import HealthKit

enum HealthKitRecoveryWindow {
    static func makeTrailingDays(
        _ dayCount: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let normalizedDayCount = max(1, dayCount)
        let todayStart = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -(normalizedDayCount - 1), to: todayStart) ?? todayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return (start: start, end: tomorrowStart)
    }

    static func makeLast90Days(
        referenceDate: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        makeTrailingDays(90, referenceDate: referenceDate, calendar: calendar)
    }

    static func makeDayStarts(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [Date] {
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
}

struct HealthKitRecoveryQueryClient {
    let healthStore: HKHealthStore
    let calendar: Calendar

    func fetchSleepByDay(start: Date, end: Date) async -> [Date: SleepTotals] {
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
            ) { _, samples, _ in
                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [:])
                    return
                }

                var totals: [Date: SleepTotals] = [:]
                for sample in categorySamples {
                    let sampleStart = max(sample.startDate, start)
                    let sampleEnd = min(sample.endDate, end)
                    guard sampleStart < sampleEnd else { continue }

                    var cursor = calendar.startOfDay(for: sampleStart)
                    while cursor < sampleEnd {
                        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                        let overlapStart = max(sampleStart, cursor)
                        let overlapEnd = min(sampleEnd, nextDay)
                        let seconds = overlapEnd.timeIntervalSince(overlapStart)

                        if seconds > 0 {
                            let dayStart = calendar.startOfDay(for: cursor)
                            var dayTotals = totals[dayStart] ?? SleepTotals()
                            if isInBedSample(sample.value) {
                                dayTotals.timeInBedSeconds += seconds
                            }
                            if isAsleepSample(sample.value) {
                                dayTotals.sleepDurationSeconds += seconds
                            }
                            totals[dayStart] = dayTotals
                        }

                        cursor = nextDay
                    }
                }

                continuation.resume(returning: totals)
            }
            healthStore.execute(query)
        }
    }

    func fetchCumulativeSumByDay(
        type: HKQuantityType?,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [Date: Double] {
        guard let type else { return [:] }
        guard isAuthorizedToRead(type) else { return [:] }
        return await fetchStatisticsByDay(
            type: type,
            options: .cumulativeSum,
            unit: unit,
            start: start,
            end: end
        )
    }

    func fetchDiscreteAverageByDay(
        type: HKQuantityType?,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> [Date: Double] {
        guard let type else { return [:] }
        guard isAuthorizedToRead(type) else { return [:] }
        return await fetchStatisticsByDay(
            type: type,
            options: .discreteAverage,
            unit: unit,
            start: start,
            end: end
        )
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

            query.initialResultsHandler = { _, collection, _ in
                guard let collection else {
                    continuation.resume(returning: [:])
                    return
                }

                var values: [Date: Double] = [:]
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let dayStart = calendar.startOfDay(for: statistics.startDate)
                    if options.contains(.cumulativeSum), let quantity = statistics.sumQuantity() {
                        values[dayStart] = quantity.doubleValue(for: unit)
                    } else if options.contains(.discreteAverage), let quantity = statistics.averageQuantity() {
                        values[dayStart] = quantity.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: values)
            }

            healthStore.execute(query)
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

enum HealthKitRecoverySnapshotBuilder {
    static func makeSnapshots(
        days: [Date],
        sleepByDay: [Date: SleepTotals],
        restingHeartRateByDay: [Date: Double],
        heartRateVariabilityByDay: [Date: Double],
        activeEnergyByDay: [Date: Double],
        stepsByDay: [Date: Double],
        bodyMassByDay: [Date: Double]
    ) -> [HealthKitDailySummarySnapshot] {
        days.map { dayStart in
            let sleepTotals = sleepByDay[dayStart]
            return HealthKitDailySummarySnapshot(
                dayStart: dayStart,
                sleepDurationSeconds: sleepTotals.map { Int($0.sleepDurationSeconds.rounded()) },
                timeInBedSeconds: sleepTotals.map { Int($0.timeInBedSeconds.rounded()) },
                restingHeartRateBPM: restingHeartRateByDay[dayStart],
                heartRateVariabilityMS: heartRateVariabilityByDay[dayStart],
                activeEnergyKilocalories: activeEnergyByDay[dayStart],
                stepCount: stepsByDay[dayStart],
                bodyMassKilograms: bodyMassByDay[dayStart]
            )
        }
    }
}

enum HealthKitRecoveryPersistence {
    @MainActor
    static func upsertDailySummaries(
        context: ModelContext,
        snapshots: [HealthKitDailySummarySnapshot],
        calendar: Calendar,
        rangeStart: Date?,
        rangeEnd: Date?,
        sourceUpdatedAt: Date
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
                row.markSyncUpdated(at: sourceUpdatedAt)
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
}

struct SleepTotals {
    var sleepDurationSeconds: TimeInterval = 0
    var timeInBedSeconds: TimeInterval = 0
}
