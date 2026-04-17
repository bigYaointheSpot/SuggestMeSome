//
//  HealthKitRecoveryInsightService.swift
//  SuggestMeSome
//
//  Feature 8 Prompt 4 — deterministic objective recovery status for Daily Coach.
//

import Foundation

@MainActor
struct HealthKitRecoveryInsightService {
    static let baselineWindowDays = 21
    static let minimumBaselineSamples = 10

    static func computeInsight(
        from summaries: [HealthKitDailySummary],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ObjectiveRecoveryInsight? {
        guard let current = currentDayComparableSummary(
            from: summaries,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            return nil
        }

        return buildInsight(
            current: current,
            allSummaries: summaries,
            calendar: calendar
        )
    }

    static func evaluate(
        from summaries: [HealthKitDailySummary],
        healthKitEnabled: Bool,
        useHealthKitInDailyCoach: Bool,
        hasSuccessfulRecoverySync: Bool,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ObjectiveRecoveryEvaluation {
        guard healthKitEnabled, useHealthKitInDailyCoach else {
            return .disabled()
        }

        guard hasSuccessfulRecoverySync, !summaries.isEmpty else {
            return .notYetSynced()
        }

        guard let current = currentDayComparableSummary(
            from: summaries,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            return .awaitingCurrentDayMetrics()
        }

        guard let insight = buildInsight(
            current: current,
            allSummaries: summaries,
            calendar: calendar
        ) else {
            return .insufficientBaseline()
        }

        return .ready(insight)
    }

    static func hasComparableCurrentDaySummary(
        from summaries: [HealthKitDailySummary],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        currentDayComparableSummary(
            from: summaries,
            referenceDate: referenceDate,
            calendar: calendar
        ) != nil
    }

    private static func buildInsight(
        current: HealthKitDailySummary,
        allSummaries: [HealthKitDailySummary],
        calendar: Calendar
    ) -> ObjectiveRecoveryInsight? {
        let assessments = buildAssessments(
            current: current,
            allSummaries: allSummaries,
            calendar: calendar
        )

        guard assessments.count >= 2 else {
            return nil
        }

        let cautionCount = assessments.filter(\.isCaution).count
        let goodCount = assessments.filter(\.isGood).count

        let status: ObjectiveRecoveryStatus
        if cautionCount >= 1 {
            status = .caution
        } else if goodCount >= 2 {
            status = .good
        } else {
            status = .neutral
        }

        let reasonSummary = compactReasonSummary(for: status, from: assessments)
        let detailSummary = detailReasonSummary(for: status, from: assessments)

        return ObjectiveRecoveryInsight(
            status: status,
            compactSummary: reasonSummary,
            detailSummary: detailSummary,
            evaluatedMetricsCount: assessments.count
        )
    }

    private static func currentDayComparableSummary(
        from summaries: [HealthKitDailySummary],
        referenceDate: Date,
        calendar: Calendar
    ) -> HealthKitDailySummary? {
        let today = calendar.startOfDay(for: referenceDate)
        return summaries
            .filter { calendar.startOfDay(for: $0.dayStart) == today }
            .first { hasAnyCoreMetric($0) }
    }

    private static func hasAnyCoreMetric(_ summary: HealthKitDailySummary) -> Bool {
        summary.sleepDurationSeconds != nil ||
        summary.heartRateVariabilityMS != nil ||
        summary.restingHeartRateBPM != nil ||
        summary.activeEnergyKilocalories != nil
    }

    private static func buildAssessments(
        current: HealthKitDailySummary,
        allSummaries: [HealthKitDailySummary],
        calendar: Calendar
    ) -> [MetricAssessment] {
        var output: [MetricAssessment] = []

        if let assessment = assessSleep(current: current, allSummaries: allSummaries, calendar: calendar) {
            output.append(assessment)
        }
        if let assessment = assessHRV(current: current, allSummaries: allSummaries, calendar: calendar) {
            output.append(assessment)
        }
        if let assessment = assessRestingHeartRate(current: current, allSummaries: allSummaries, calendar: calendar) {
            output.append(assessment)
        }
        if let assessment = assessActiveEnergy(current: current, allSummaries: allSummaries, calendar: calendar) {
            output.append(assessment)
        }

        return output
    }

    private static func assessSleep(
        current: HealthKitDailySummary,
        allSummaries: [HealthKitDailySummary],
        calendar: Calendar
    ) -> MetricAssessment? {
        guard let currentSleep = current.sleepDurationSeconds.map(Double.init) else { return nil }
        guard let baselineSleep = baselineAverage(
            allSummaries: allSummaries,
            currentDayStart: current.dayStart,
            calendar: calendar,
            metricValue: { $0.sleepDurationSeconds.map(Double.init) }
        ) else { return nil }

        let isCaution = currentSleep < (baselineSleep * 0.90) && (baselineSleep - currentSleep) >= 1800
        let isGood = currentSleep >= (baselineSleep * 1.05)

        return MetricAssessment(
            isCaution: isCaution,
            isGood: isGood,
            cautionDetail: "sleep was below your normal range",
            goodDetail: "sleep was above your normal range"
        )
    }

    private static func assessHRV(
        current: HealthKitDailySummary,
        allSummaries: [HealthKitDailySummary],
        calendar: Calendar
    ) -> MetricAssessment? {
        guard let currentHRV = current.heartRateVariabilityMS else { return nil }
        guard let baselineHRV = baselineAverage(
            allSummaries: allSummaries,
            currentDayStart: current.dayStart,
            calendar: calendar,
            metricValue: { $0.heartRateVariabilityMS }
        ) else { return nil }

        let isCaution = currentHRV < (baselineHRV * 0.90) && (baselineHRV - currentHRV) >= 5
        let isGood = currentHRV >= (baselineHRV * 1.08)

        return MetricAssessment(
            isCaution: isCaution,
            isGood: isGood,
            cautionDetail: "HRV was below baseline",
            goodDetail: "HRV was above baseline"
        )
    }

    private static func assessRestingHeartRate(
        current: HealthKitDailySummary,
        allSummaries: [HealthKitDailySummary],
        calendar: Calendar
    ) -> MetricAssessment? {
        guard let currentRHR = current.restingHeartRateBPM else { return nil }
        guard let baselineRHR = baselineAverage(
            allSummaries: allSummaries,
            currentDayStart: current.dayStart,
            calendar: calendar,
            metricValue: { $0.restingHeartRateBPM }
        ) else { return nil }

        let isCaution = currentRHR > (baselineRHR * 1.06) && (currentRHR - baselineRHR) >= 3
        let isGood = currentRHR <= (baselineRHR * 0.96)

        return MetricAssessment(
            isCaution: isCaution,
            isGood: isGood,
            cautionDetail: "resting heart rate was above baseline",
            goodDetail: "resting heart rate was below baseline"
        )
    }

    private static func assessActiveEnergy(
        current: HealthKitDailySummary,
        allSummaries: [HealthKitDailySummary],
        calendar: Calendar
    ) -> MetricAssessment? {
        guard let currentActive = current.activeEnergyKilocalories else { return nil }
        guard let baselineActive = baselineAverage(
            allSummaries: allSummaries,
            currentDayStart: current.dayStart,
            calendar: calendar,
            metricValue: { $0.activeEnergyKilocalories }
        ) else { return nil }

        let isCaution = currentActive > (baselineActive * 1.20) && (currentActive - baselineActive) >= 150
        let isGood = currentActive <= (baselineActive * 0.90)

        return MetricAssessment(
            isCaution: isCaution,
            isGood: isGood,
            cautionDetail: "active energy was higher than usual",
            goodDetail: "active energy was lower than usual"
        )
    }

    private static func baselineAverage(
        allSummaries: [HealthKitDailySummary],
        currentDayStart: Date,
        calendar: Calendar,
        metricValue: (HealthKitDailySummary) -> Double?
    ) -> Double? {
        let currentDay = calendar.startOfDay(for: currentDayStart)
        guard let baselineStart = calendar.date(byAdding: .day, value: -baselineWindowDays, to: currentDay) else {
            return nil
        }

        let values = allSummaries
            .filter {
                let day = calendar.startOfDay(for: $0.dayStart)
                return day < currentDay && day >= baselineStart
            }
            .sorted { $0.dayStart > $1.dayStart }
            .compactMap(metricValue)

        guard values.count >= minimumBaselineSamples else {
            return nil
        }

        let sum = values.reduce(0, +)
        return sum / Double(values.count)
    }

    private static func compactReasonSummary(
        for status: ObjectiveRecoveryStatus,
        from assessments: [MetricAssessment]
    ) -> String {
        let cautionDetails = assessments.filter(\.isCaution).map(\.cautionDetail)
        let goodDetails = assessments.filter(\.isGood).map(\.goodDetail)

        switch status {
        case .caution:
            return "Caution: " + joinReasons(cautionDetails)
        case .good:
            return "Good: " + joinReasons(goodDetails)
        case .neutral:
            return "Neutral: objective recovery is near your baseline"
        }
    }

    private static func detailReasonSummary(
        for status: ObjectiveRecoveryStatus,
        from assessments: [MetricAssessment]
    ) -> String {
        let cautionDetails = assessments.filter(\.isCaution).map(\.cautionDetail)
        let goodDetails = assessments.filter(\.isGood).map(\.goodDetail)

        switch status {
        case .caution:
            return "Objective recovery is slightly conservative today because " + joinReasons(cautionDetails) + "."
        case .good:
            return "Objective recovery looks favorable today because " + joinReasons(goodDetails) + "."
        case .neutral:
            return "Objective recovery is close to your recent baseline and does not materially change today's plan."
        }
    }

    private static func joinReasons(_ reasons: [String]) -> String {
        let distinct = Array(Set(reasons)).sorted()
        if distinct.isEmpty { return "signals were mixed" }
        if distinct.count == 1 { return distinct[0] }
        if distinct.count == 2 { return "\(distinct[0]) and \(distinct[1])" }

        let head = distinct.dropLast().joined(separator: ", ")
        return "\(head), and \(distinct.last ?? "signals were mixed")"
    }
}

private struct MetricAssessment {
    let isCaution: Bool
    let isGood: Bool
    let cautionDetail: String
    let goodDetail: String
}
