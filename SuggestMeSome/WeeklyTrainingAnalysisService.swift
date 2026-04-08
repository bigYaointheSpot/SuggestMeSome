//
//  WeeklyTrainingAnalysisService.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation
import SwiftData

/// Weekly aggregation engine for Feature 6.
/// - Analyzes one completed week at a time.
/// - Blends program and standalone signals (program stays higher confidence).
/// - Persists weekly rollups, volume metrics, trend updates, and explainability events.
enum WeeklyTrainingAnalysisService {
    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601) // Monday-anchored
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    static func analyzeCompletedWeeks(triggeredBy workout: Workout, context: ModelContext) {
        let allRuns = (try? context.fetch(FetchDescriptor<ProgramRun>())) ?? []

        if let run = workout.programRun {
            analyzePendingProgramWeeks(for: run, referenceDate: workout.date, context: context)
        }

        analyzePendingStandaloneWeeks(referenceDate: workout.date, allRuns: allRuns, context: context)
    }

    // MARK: - Program Weeks

    private static func analyzePendingProgramWeeks(
        for run: ProgramRun,
        referenceDate: Date,
        context: ModelContext
    ) {
        guard let program = run.program else { return }
        let maxWeek = min(
            program.lengthInWeeks,
            max(1, inferredProgramWeekNumber(for: referenceDate, runStartDate: run.startDate))
        )

        let allWorkouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []

        for weekNumber in 1...maxWeek {
            let window = programWeekWindow(runStartDate: run.startDate, weekNumber: weekNumber)
            let runWeekWorkouts = allWorkouts.filter {
                $0.programRun?.id == run.id &&
                resolvedProgramWeekNumber(for: $0, runStartDate: run.startDate) == weekNumber
            }
            let uniqueCompletedSessions = Set(runWeekWorkouts.compactMap(\.programSessionNumber)).count
            let weekEnded = referenceDate > window.weekEndDate
            let weekComplete = uniqueCompletedSessions >= program.sessionsPerWeek || weekEnded

            guard weekComplete else { continue }
            _ = analyzeProgramWeek(run: run, weekNumber: weekNumber, context: context)
        }
    }

    @discardableResult
    static func analyzeProgramWeek(
        run: ProgramRun,
        weekNumber: Int,
        context: ModelContext
    ) -> WeeklyTrainingAnalysis? {
        guard let program = run.program else { return nil }

        let allWorkouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let allOutcomes = (try? context.fetch(FetchDescriptor<ExercisePerformanceOutcome>())) ?? []
        let window = programWeekWindow(runStartDate: run.startDate, weekNumber: weekNumber)

        let runWeekWorkouts = allWorkouts.filter {
            $0.programRun?.id == run.id &&
            resolvedProgramWeekNumber(for: $0, runStartDate: run.startDate) == weekNumber
        }
        let selectedProgramWorkouts = dedupeProgramWorkoutsBySession(runWeekWorkouts)
        let standaloneWorkouts = allWorkouts.filter {
            $0.programRun == nil &&
            $0.date >= window.weekStartDate &&
            $0.date <= window.weekEndDate
        }

        let selectedWorkoutIDs = Set((selectedProgramWorkouts + standaloneWorkouts).map(\.id))
        let selectedOutcomes = dedupeOutcomes(
            allOutcomes.filter { outcome in
                guard let workoutID = outcome.workout?.id else { return false }
                return selectedWorkoutIDs.contains(workoutID)
            }
        )

        let analysis = upsertAnalysis(
            for: .program(runID: run.id, weekNumber: weekNumber),
            context: context
        )

        configureAnalysisBaseFields(
            analysis: analysis,
            weekStartDate: window.weekStartDate,
            weekEndDate: window.weekEndDate,
            programRun: run,
            trainingProgram: program,
            programWeekNumber: weekNumber,
            selectedProgramWorkouts: selectedProgramWorkouts,
            standaloneWorkouts: standaloneWorkouts,
            selectedOutcomes: selectedOutcomes
        )

        let aggregates = aggregateWeekSignals(
            selectedWorkouts: selectedProgramWorkouts + standaloneWorkouts,
            selectedOutcomes: selectedOutcomes
        )
        let plannedVolumeByMuscle = plannedVolumeByMuscleForProgramWeek(
            program: program,
            weekNumber: weekNumber
        )

        applyAggregateFields(
            analysis: analysis,
            aggregates: aggregates,
            plannedFatigueScore: plannedFatigueForProgramWeek(program: program, weekNumber: weekNumber),
            plannedVolumeByMuscle: plannedVolumeByMuscle
        )
        upsertVolumeMetrics(
            analysis: analysis,
            completedByMuscle: aggregates.completedHardSetsByMuscle,
            weightedByMuscle: aggregates.weightedHardSetsByMuscle,
            plannedByMuscle: plannedVolumeByMuscle,
            context: context
        )
        attachOutcomes(selectedOutcomes, to: analysis)

        analysis.isFinalized = true
        analysis.finalizedAt = Date.now

        let liftKeys = Set(selectedOutcomes.compactMap(\.canonicalLiftKey))
        let trendSummary = updateLiftTrends(
            liftKeys: liftKeys,
            scope: .program(run: run),
            analysisWeekEndDate: window.weekEndDate,
            context: context
        )

        upsertHistoryEvent(
            for: analysis,
            programRun: run,
            programWeekNumber: weekNumber,
            topSetSummary: aggregates.mainLiftTopSetE1RM,
            trendSummary: trendSummary,
            skippedProgramDuplicateWorkouts: max(0, runWeekWorkouts.count - selectedProgramWorkouts.count),
            context: context
        )
        // Feature 6: generate weekly top-set-driven load proposals as non-destructive overlays.
        AdaptiveLoadProgressionService.generateProposals(from: analysis, context: context)
        // Feature 6: generate weekly accessory-volume proposals (user-confirmed before apply).
        AdaptiveVolumeProgressionService.generateProposals(from: analysis, context: context)

        return analysis
    }

    // MARK: - Standalone Weeks

    private static func analyzePendingStandaloneWeeks(
        referenceDate: Date,
        allRuns: [ProgramRun],
        context: ModelContext
    ) {
        let allWorkouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let standaloneWorkouts = allWorkouts.filter { $0.programRun == nil }
        guard !standaloneWorkouts.isEmpty else { return }

        guard let currentWeekInterval = isoCalendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return }
        let currentWeekStart = currentWeekInterval.start

        let endedWeekStarts: Set<Date> = Set(
            standaloneWorkouts.compactMap { workout in
                guard let weekInterval = isoCalendar.dateInterval(of: .weekOfYear, for: workout.date) else { return nil }
                return weekInterval.start < currentWeekStart ? weekInterval.start : nil
            }
        )

        for weekStart in endedWeekStarts.sorted() {
            let window = weekWindowFromStart(weekStart)
            if overlapsAnyProgramRun(window: window, allRuns: allRuns) {
                continue
            }
            _ = analyzeStandaloneWeek(startingAt: weekStart, context: context)
        }
    }

    @discardableResult
    static func analyzeStandaloneWeek(
        startingAt weekStartDate: Date,
        context: ModelContext
    ) -> WeeklyTrainingAnalysis? {
        let allWorkouts = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let allOutcomes = (try? context.fetch(FetchDescriptor<ExercisePerformanceOutcome>())) ?? []
        let window = weekWindowFromStart(weekStartDate)

        let standaloneWorkouts = allWorkouts.filter {
            $0.programRun == nil &&
            $0.date >= window.weekStartDate &&
            $0.date <= window.weekEndDate
        }

        guard !standaloneWorkouts.isEmpty else { return nil }

        let selectedWorkoutIDs = Set(standaloneWorkouts.map(\.id))
        let selectedOutcomes = dedupeOutcomes(
            allOutcomes.filter { outcome in
                guard let workoutID = outcome.workout?.id else { return false }
                return selectedWorkoutIDs.contains(workoutID)
            }
        )

        let analysis = upsertAnalysis(
            for: .standalone(weekStartDate: window.weekStartDate),
            context: context
        )
        configureAnalysisBaseFields(
            analysis: analysis,
            weekStartDate: window.weekStartDate,
            weekEndDate: window.weekEndDate,
            programRun: nil,
            trainingProgram: nil,
            programWeekNumber: nil,
            selectedProgramWorkouts: [],
            standaloneWorkouts: standaloneWorkouts,
            selectedOutcomes: selectedOutcomes
        )

        let aggregates = aggregateWeekSignals(
            selectedWorkouts: standaloneWorkouts,
            selectedOutcomes: selectedOutcomes
        )
        applyAggregateFields(
            analysis: analysis,
            aggregates: aggregates,
            plannedFatigueScore: nil,
            plannedVolumeByMuscle: [:]
        )
        upsertVolumeMetrics(
            analysis: analysis,
            completedByMuscle: aggregates.completedHardSetsByMuscle,
            weightedByMuscle: aggregates.weightedHardSetsByMuscle,
            plannedByMuscle: [:],
            context: context
        )
        attachOutcomes(selectedOutcomes, to: analysis)

        analysis.isFinalized = true
        analysis.finalizedAt = Date.now

        let liftKeys = Set(selectedOutcomes.compactMap(\.canonicalLiftKey))
        let trendSummary = updateLiftTrends(
            liftKeys: liftKeys,
            scope: .standalone,
            analysisWeekEndDate: window.weekEndDate,
            context: context
        )
        upsertHistoryEvent(
            for: analysis,
            programRun: nil,
            programWeekNumber: nil,
            topSetSummary: aggregates.mainLiftTopSetE1RM,
            trendSummary: trendSummary,
            skippedProgramDuplicateWorkouts: 0,
            context: context
        )

        return analysis
    }

    // MARK: - Analysis Base

    private static func configureAnalysisBaseFields(
        analysis: WeeklyTrainingAnalysis,
        weekStartDate: Date,
        weekEndDate: Date,
        programRun: ProgramRun?,
        trainingProgram: TrainingProgram?,
        programWeekNumber: Int?,
        selectedProgramWorkouts: [Workout],
        standaloneWorkouts: [Workout],
        selectedOutcomes: [ExercisePerformanceOutcome]
    ) {
        analysis.createdAt = Date.now
        analysis.weekStartDate = weekStartDate
        analysis.weekEndDate = weekEndDate
        analysis.programRun = programRun
        analysis.trainingProgram = trainingProgram
        analysis.programWeekNumber = programWeekNumber
        analysis.focusSnapshot = nil // populated when focus metadata becomes persisted on TrainingProgram.
        analysis.programWorkoutCount = selectedProgramWorkouts.count
        analysis.standaloneWorkoutCount = standaloneWorkouts.count
        analysis.totalOutcomeCount = selectedOutcomes.count

        let programSignalWeight = selectedOutcomes
            .filter { $0.signalSource == .programLinked }
            .reduce(0.0) { $0 + $1.signalWeight }
        let standaloneSignalWeight = selectedOutcomes
            .filter { $0.signalSource == .standalone }
            .reduce(0.0) { $0 + $1.signalWeight }

        analysis.programSignalWeight = programSignalWeight
        analysis.standaloneSignalWeight = standaloneSignalWeight
        analysis.totalSignalWeight = programSignalWeight + standaloneSignalWeight
    }

    private static func applyAggregateFields(
        analysis: WeeklyTrainingAnalysis,
        aggregates: WeekAggregates,
        plannedFatigueScore: Double?,
        plannedVolumeByMuscle: [ProgramVolumeMuscle: Double]
    ) {
        analysis.weightedPerformanceScore = aggregates.weightedPerformanceScore
        analysis.adherenceScore = aggregates.adherenceScore
        analysis.plannedFatigueScore = plannedFatigueScore
        analysis.observedFatigueScore = aggregates.observedFatigueScore
        analysis.fatigueStatus = inferWeeklyFatigueStatus(
            observedFatigueScore: aggregates.observedFatigueScore,
            plannedFatigueScore: plannedFatigueScore
        )
        analysis.totalCompletedHardSets = aggregates.totalCompletedHardSets
        analysis.totalCompletedTonnage = aggregates.totalCompletedTonnageLbs

        // Keep the relationship deterministic even when planned volume is missing.
        if plannedVolumeByMuscle.isEmpty {
            analysis.focusSnapshot = nil
        }
    }

    // MARK: - Aggregation

    private static func aggregateWeekSignals(
        selectedWorkouts: [Workout],
        selectedOutcomes: [ExercisePerformanceOutcome]
    ) -> WeekAggregates {
        let weightedPerformanceScore = weightedAverage(
            values: selectedOutcomes.map { ($0.performanceScoreValue, max(0.01, $0.signalWeight)) }
        ) ?? 0

        let adherenceScore = computeAdherenceScore(
            selectedWorkouts: selectedWorkouts,
            selectedOutcomes: selectedOutcomes
        )

        var completedHardSetsByMuscle = Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })
        var weightedHardSetsByMuscle = Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })
        var totalCompletedHardSets = 0.0
        var totalCompletedTonnageLbs = 0.0

        for workout in selectedWorkouts {
            let sourceWeight = workout.programRun == nil
                ? AdaptiveSignalWeights.standaloneWorkout
                : AdaptiveSignalWeights.programWorkout

            for entry in workout.exerciseEntries where !entry.isCardio {
                let validSets = entry.sets.filter { $0.reps > 0 && $0.weight > 0 }
                guard !validSets.isEmpty else { continue }

                let hardSets = Double(validSets.count)
                totalCompletedHardSets += hardSets
                totalCompletedTonnageLbs += validSets.reduce(0.0) { partial, set in
                    partial + (Double(set.reps) * inLbs(set.weight, unit: entry.unit))
                }

                let contributions = ProgramExerciseMetadataService.metadata(for: entry.exerciseName).muscleContributions
                for (muscle, contribution) in contributions {
                    let setsForMuscle = hardSets * contribution
                    completedHardSetsByMuscle[muscle, default: 0] += setsForMuscle
                    weightedHardSetsByMuscle[muscle, default: 0] += setsForMuscle * sourceWeight
                }
            }
        }

        let observedFatigueScore = computeObservedFatigueScore(outcomes: selectedOutcomes)
        let mainLiftTopSetE1RM = summarizeMainLiftTopSets(outcomes: selectedOutcomes)

        return WeekAggregates(
            weightedPerformanceScore: weightedPerformanceScore,
            adherenceScore: adherenceScore,
            observedFatigueScore: observedFatigueScore,
            completedHardSetsByMuscle: completedHardSetsByMuscle,
            weightedHardSetsByMuscle: weightedHardSetsByMuscle,
            totalCompletedHardSets: totalCompletedHardSets,
            totalCompletedTonnageLbs: totalCompletedTonnageLbs,
            mainLiftTopSetE1RM: mainLiftTopSetE1RM
        )
    }

    private static func computeAdherenceScore(
        selectedWorkouts: [Workout],
        selectedOutcomes: [ExercisePerformanceOutcome]
    ) -> Double {
        let anyProgramWorkout = selectedWorkouts.contains { $0.programRun != nil }
        guard anyProgramWorkout else {
            // Standalone weeks have no prescribed schedule in v1; keep neutral adherence.
            return 1.0
        }

        let programWorkouts = selectedWorkouts.filter { $0.programRun != nil }
        guard let program = programWorkouts.first?.programRun?.program else { return 1.0 }

        let uniqueProgramSessions = Set(programWorkouts.compactMap(\.programSessionNumber)).count
        let sessionCompletion = Double(uniqueProgramSessions) / Double(max(1, program.sessionsPerWeek))
        let avgCompletionRatio = average(selectedOutcomes.compactMap(\.completionRatio)) ?? sessionCompletion

        // 60% session adherence + 40% set-level completion quality.
        let mixed = (sessionCompletion * 0.60) + (avgCompletionRatio * 0.40)
        return min(1.25, max(0.0, mixed))
    }

    private static func computeObservedFatigueScore(outcomes: [ExercisePerformanceOutcome]) -> Double {
        guard !outcomes.isEmpty else { return 0 }

        var total = 0.0
        for outcome in outcomes {
            let fatigueScalar: Double = {
                switch outcome.inferredFatigueStatus {
                case .low: return 0.80
                case .manageable: return 1.00
                case .elevated: return 1.30
                case .high: return 1.70
                case .critical: return 2.20
                }
            }()
            let setFactor = max(0.50, min(2.0, Double(max(1, outcome.actualSetCount)) / 4.0))
            let topSetFactor = outcome.isTopSetSignal ? 1.20 : 1.0
            total += outcome.signalWeight * fatigueScalar * setFactor * topSetFactor * 4.0
        }

        return total
    }

    private static func inferWeeklyFatigueStatus(
        observedFatigueScore: Double,
        plannedFatigueScore: Double?
    ) -> FatigueStatus {
        if let plannedFatigueScore, plannedFatigueScore > 0 {
            let ratio = observedFatigueScore / plannedFatigueScore
            if ratio < 0.75 { return .low }
            if ratio < 1.05 { return .manageable }
            if ratio < 1.25 { return .elevated }
            if ratio < 1.50 { return .high }
            return .critical
        }

        if observedFatigueScore < 20 { return .low }
        if observedFatigueScore < 40 { return .manageable }
        if observedFatigueScore < 60 { return .elevated }
        if observedFatigueScore < 80 { return .high }
        return .critical
    }

    private static func summarizeMainLiftTopSets(
        outcomes: [ExercisePerformanceOutcome]
    ) -> [String: Double] {
        let mainKeys: Set<String> = ["squat", "bench", "deadlift"]
        var summary: [String: Double] = [:]

        for outcome in outcomes {
            guard
                let liftKey = outcome.canonicalLiftKey,
                mainKeys.contains(liftKey),
                let e1rm = outcome.actualTopSetEstimated1RM
            else { continue }

            summary[liftKey] = max(summary[liftKey] ?? 0, e1rm)
        }

        return summary
    }

    // MARK: - Planned Week Targets

    private static func plannedFatigueForProgramWeek(
        program: TrainingProgram,
        weekNumber: Int
    ) -> Double? {
        program.weeks.first { $0.weekNumber == weekNumber }?.plannedFatigueScore
    }

    private static func plannedVolumeByMuscleForProgramWeek(
        program: TrainingProgram,
        weekNumber: Int
    ) -> [ProgramVolumeMuscle: Double] {
        guard let week = program.weeks.first(where: { $0.weekNumber == weekNumber }) else { return [:] }

        var totals = Dictionary(uniqueKeysWithValues: ProgramVolumeMuscle.allCases.map { ($0, 0.0) })

        for session in week.sessions {
            for exercise in session.exercises where !exercise.isWarmup {
                let setCount = Double(max(0, exercise.targetSets ?? 0))
                guard setCount > 0 else { continue }

                let contributions = ProgramExerciseMetadataService.metadata(for: exercise.exerciseName).muscleContributions
                for (muscle, contribution) in contributions {
                    totals[muscle, default: 0] += setCount * contribution
                }
            }
        }

        return totals
    }

    // MARK: - Volume Metric Persistence

    private static func upsertVolumeMetrics(
        analysis: WeeklyTrainingAnalysis,
        completedByMuscle: [ProgramVolumeMuscle: Double],
        weightedByMuscle: [ProgramVolumeMuscle: Double],
        plannedByMuscle: [ProgramVolumeMuscle: Double],
        context: ModelContext
    ) {
        for metric in analysis.volumeMetrics {
            context.delete(metric)
        }
        analysis.volumeMetrics.removeAll()

        for muscle in ProgramVolumeMuscle.allCases {
            let completed = completedByMuscle[muscle] ?? 0
            let planned = plannedByMuscle[muscle]
            let weighted = weightedByMuscle[muscle] ?? 0
            guard completed > 0 || planned != nil else { continue }

            let metric = WeeklyVolumeMetric(
                analysis: analysis,
                muscle: muscle,
                plannedHardSets: planned,
                completedHardSets: completed,
                weightedCompletedHardSets: weighted,
                deltaHardSets: completed - (planned ?? 0)
            )
            context.insert(metric)
            analysis.volumeMetrics.append(metric)
        }
    }

    // MARK: - Lift Trend Persistence

    private static func updateLiftTrends(
        liftKeys: Set<String>,
        scope: TrendScope,
        analysisWeekEndDate: Date,
        context: ModelContext
    ) -> [String: LiftTrendStatus] {
        guard !liftKeys.isEmpty else { return [:] }

        let analyses = (try? context.fetch(FetchDescriptor<WeeklyTrainingAnalysis>())) ?? []
        let trends = (try? context.fetch(FetchDescriptor<LiftPerformanceTrend>())) ?? []
        let scopedAnalyses: [WeeklyTrainingAnalysis] = analyses.filter {
            guard $0.isFinalized else { return false }
            guard $0.weekStartDate <= analysisWeekEndDate else { return false }
            switch scope {
            case .program(let run):
                return $0.programRun?.id == run.id
            case .standalone:
                return $0.programRun == nil
            }
        }

        var summary: [String: LiftTrendStatus] = [:]

        for liftKey in liftKeys {
            let points = scopedAnalyses
                .flatMap(\.outcomes)
                .filter { $0.canonicalLiftKey == liftKey && $0.actualTopSetEstimated1RM != nil }
                .sorted {
                    if $0.workoutDate == $1.workoutDate { return $0.id.uuidString < $1.id.uuidString }
                    return $0.workoutDate < $1.workoutDate
                }
            guard !points.isEmpty else { continue }

            let trend = upsertTrend(
                for: liftKey,
                scope: scope,
                existing: trends,
                context: context
            )

            let weightedSignalCount = points.reduce(0.0) { $0 + $1.signalWeight }
            trend.updatedAt = Date.now
            trend.totalDataPoints = points.count
            trend.programLinkedDataPoints = points.filter { $0.signalSource == .programLinked }.count
            trend.standaloneDataPoints = points.filter { $0.signalSource == .standalone }.count
            trend.weightedSignalCount = weightedSignalCount
            trend.confidenceScore = min(1.0, weightedSignalCount / 8.0)
            trend.firstObservationDate = points.first?.workoutDate ?? Date.now
            trend.lastObservationDate = points.last?.workoutDate ?? Date.now

            let latestPoints = Array(points.suffix(min(3, points.count)))
            let previousPoints = Array(points.dropLast(latestPoints.count).suffix(3))
            let currentE1RM = weightedAverage(
                values: latestPoints.compactMap { point in
                    guard let e1rm = point.actualTopSetEstimated1RM else { return nil }
                    return (e1rm, max(0.01, point.signalWeight))
                }
            )
            let previousE1RM = weightedAverage(
                values: previousPoints.compactMap { point in
                    guard let e1rm = point.actualTopSetEstimated1RM else { return nil }
                    return (e1rm, max(0.01, point.signalWeight))
                }
            )

            trend.currentEstimated1RM = currentE1RM
            trend.previousEstimated1RM = previousE1RM
            trend.rollingBestEstimated1RM = points.compactMap(\.actualTopSetEstimated1RM).max()

            let currentWindowStart = isoCalendar.date(byAdding: .day, value: -27, to: analysisWeekEndDate) ?? analysisWeekEndDate
            let priorWindowEnd = isoCalendar.date(byAdding: .day, value: -28, to: analysisWeekEndDate) ?? analysisWeekEndDate
            let priorWindowStart = isoCalendar.date(byAdding: .day, value: -55, to: analysisWeekEndDate) ?? analysisWeekEndDate

            let currentWindowPoints = points.filter {
                $0.workoutDate >= currentWindowStart && $0.workoutDate <= analysisWeekEndDate
            }
            let priorWindowPoints = points.filter {
                $0.workoutDate >= priorWindowStart && $0.workoutDate <= priorWindowEnd
            }

            let currentWindowE1RM = weightedAverage(values: currentWindowPoints.compactMap { point in
                guard let e1rm = point.actualTopSetEstimated1RM else { return nil }
                return (e1rm, max(0.01, point.signalWeight))
            })
            let priorWindowE1RM = weightedAverage(values: priorWindowPoints.compactMap { point in
                guard let e1rm = point.actualTopSetEstimated1RM else { return nil }
                return (e1rm, max(0.01, point.signalWeight))
            })

            if let currentWindowE1RM, let priorWindowE1RM, priorWindowE1RM > 0 {
                trend.fourWeekChangePercent = ((currentWindowE1RM - priorWindowE1RM) / priorWindowE1RM) * 100.0
            } else if let currentE1RM, let previousE1RM, previousE1RM > 0 {
                trend.fourWeekChangePercent = ((currentE1RM - previousE1RM) / previousE1RM) * 100.0
            } else {
                trend.fourWeekChangePercent = nil
            }

            trend.trendStatus = inferLiftTrendStatus(
                sampleCount: points.count,
                fourWeekChangePercent: trend.fourWeekChangePercent,
                latestValues: latestPoints.compactMap(\.actualTopSetEstimated1RM)
            )
            trend.fatigueStatus = inferLiftFatigueStatus(points: points)

            if let latest = points.last {
                trend.latestTopSetWeight = latest.actualTopSetWeight
                trend.latestTopSetReps = latest.actualTopSetReps
                trend.latestPerformanceScoreValue = latest.performanceScoreValue
                trend.lastPerformanceScore = latest.performanceScore
            }

            summary[liftKey] = trend.trendStatus
        }

        return summary
    }

    private static func upsertTrend(
        for liftKey: String,
        scope: TrendScope,
        existing: [LiftPerformanceTrend],
        context: ModelContext
    ) -> LiftPerformanceTrend {
        if let found = existing.first(where: {
            $0.canonicalLiftKey == liftKey &&
            (
                (scope.runID == nil && $0.programRun == nil) ||
                (scope.runID != nil && $0.programRun?.id == scope.runID)
            )
        }) {
            return found
        }

        let trend = LiftPerformanceTrend(
            programRun: scope.run,
            trainingProgram: scope.run?.program,
            canonicalLiftKey: liftKey,
            liftDisplayName: liftDisplayName(for: liftKey)
        )
        context.insert(trend)
        return trend
    }

    private static func inferLiftTrendStatus(
        sampleCount: Int,
        fourWeekChangePercent: Double?,
        latestValues: [Double]
    ) -> LiftTrendStatus {
        guard sampleCount >= 2 else { return .insufficientData }
        guard let fourWeekChangePercent else { return .stable }

        if latestValues.count >= 3 {
            let mean = latestValues.reduce(0, +) / Double(latestValues.count)
            let variance = latestValues.reduce(0.0) { partial, value in
                partial + pow(value - mean, 2)
            } / Double(latestValues.count)
            if variance > 25 {
                return .volatile
            }
        }

        if abs(fourWeekChangePercent) < 1.0 { return .stable }
        return fourWeekChangePercent > 0 ? .improving : .declining
    }

    private static func inferLiftFatigueStatus(points: [ExercisePerformanceOutcome]) -> FatigueStatus {
        let recent = Array(points.suffix(min(6, points.count)))
        let score = weightedAverage(values: recent.map { point in
            let scalar: Double = {
                switch point.inferredFatigueStatus {
                case .low: return 0.8
                case .manageable: return 1.0
                case .elevated: return 1.3
                case .high: return 1.8
                case .critical: return 2.3
                }
            }()
            return (scalar, max(0.01, point.signalWeight))
        }) ?? 1.0

        if score < 0.9 { return .low }
        if score < 1.15 { return .manageable }
        if score < 1.45 { return .elevated }
        if score < 1.90 { return .high }
        return .critical
    }

    // MARK: - Explainability Event

    private static func upsertHistoryEvent(
        for analysis: WeeklyTrainingAnalysis,
        programRun: ProgramRun?,
        programWeekNumber: Int?,
        topSetSummary: [String: Double],
        trendSummary: [String: LiftTrendStatus],
        skippedProgramDuplicateWorkouts: Int,
        context: ModelContext
    ) {
        let events = (try? context.fetch(FetchDescriptor<AdaptationEventHistory>())) ?? []
        let event = events.first(where: {
            $0.eventType == .weeklyAnalysisFinalized &&
            $0.programRun?.id == programRun?.id &&
            $0.analysisWeekNumber == programWeekNumber &&
            (
                (programRun != nil && $0.analysis?.id == analysis.id) ||
                (programRun == nil && $0.analysis?.weekStartDate == analysis.weekStartDate)
            )
        }) ?? {
            let newEvent = AdaptationEventHistory(
                programRun: programRun,
                trainingProgram: programRun?.program,
                analysis: analysis,
                eventType: .weeklyAnalysisFinalized,
                analysisWeekNumber: programWeekNumber,
                message: ""
            )
            context.insert(newEvent)
            return newEvent
        }()

        let title = {
            if let programWeekNumber {
                return "Week \(programWeekNumber) analysis finalized"
            }
            return "Standalone week analysis finalized"
        }()

        var explanationParts: [String] = []
        explanationParts.append("weighted_performance=\(fmt1(analysis.weightedPerformanceScore))")
        explanationParts.append("fatigue=\(analysis.fatigueStatus.rawValue)")
        explanationParts.append("adherence=\(fmt2(analysis.adherenceScore))")
        explanationParts.append("signals=program:\(fmt1(analysis.programSignalWeight)),standalone:\(fmt1(analysis.standaloneSignalWeight))")
        if skippedProgramDuplicateWorkouts > 0 {
            explanationParts.append("dedupe_skipped_program_workouts=\(skippedProgramDuplicateWorkouts)")
        }
        if !topSetSummary.isEmpty {
            let text = topSetSummary
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(fmt1($0.value))lbs_e1rm" }
                .joined(separator: ", ")
            explanationParts.append("main_lift_top_sets=[\(text)]")
        }
        if !trendSummary.isEmpty {
            let text = trendSummary
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.rawValue)" }
                .joined(separator: ", ")
            explanationParts.append("lift_trends=[\(text)]")
        }

        event.timestamp = Date.now
        event.programRun = programRun
        event.trainingProgram = programRun?.program
        event.analysis = analysis
        event.eventType = .weeklyAnalysisFinalized
        event.analysisWeekNumber = programWeekNumber
        event.message = title
        event.explanation = explanationParts.joined(separator: "; ")
        event.adjustmentReason = nil
        event.performanceScoreSnapshot = classifyAggregatePerformance(analysis.weightedPerformanceScore)
        event.fatigueStatusSnapshot = analysis.fatigueStatus
        event.liftTrendStatusSnapshot = dominantTrendStatus(from: trendSummary)
        event.confidenceSnapshot = min(1.0, analysis.totalSignalWeight / 8.0)
        event.requiresUserAction = false
        event.userActionTaken = false
    }

    // MARK: - Relationship / Upsert Helpers

    private static func attachOutcomes(
        _ selectedOutcomes: [ExercisePerformanceOutcome],
        to analysis: WeeklyTrainingAnalysis
    ) {
        let selectedIDs = Set(selectedOutcomes.map(\.id))

        for existing in analysis.outcomes where !selectedIDs.contains(existing.id) {
            existing.analysis = nil
        }
        for outcome in selectedOutcomes {
            outcome.analysis = analysis
        }
        analysis.outcomes = selectedOutcomes.sorted {
            if $0.workoutDate == $1.workoutDate { return $0.id.uuidString < $1.id.uuidString }
            return $0.workoutDate < $1.workoutDate
        }
    }

    private static func upsertAnalysis(
        for key: AnalysisKey,
        context: ModelContext
    ) -> WeeklyTrainingAnalysis {
        let analyses = (try? context.fetch(FetchDescriptor<WeeklyTrainingAnalysis>())) ?? []

        switch key {
        case .program(let runID, let weekNumber):
            if let existing = analyses.first(where: {
                $0.programRun?.id == runID && $0.programWeekNumber == weekNumber
            }) {
                return existing
            }
        case .standalone(let weekStartDate):
            if let existing = analyses.first(where: {
                $0.programRun == nil && $0.programWeekNumber == nil && $0.weekStartDate == weekStartDate
            }) {
                return existing
            }
        }

        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: Date.now,
            weekEndDate: Date.now
        )
        context.insert(analysis)
        return analysis
    }

    private static func dedupeProgramWorkoutsBySession(_ workouts: [Workout]) -> [Workout] {
        var latestBySession: [Int: Workout] = [:]
        var noSessionWorkouts: [Workout] = []

        for workout in workouts {
            guard let session = workout.programSessionNumber else {
                noSessionWorkouts.append(workout)
                continue
            }
            if let existing = latestBySession[session] {
                if workout.date > existing.date {
                    latestBySession[session] = workout
                }
            } else {
                latestBySession[session] = workout
            }
        }

        return (Array(latestBySession.values) + noSessionWorkouts).sorted {
            if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
            return $0.date < $1.date
        }
    }

    private static func dedupeOutcomes(_ outcomes: [ExercisePerformanceOutcome]) -> [ExercisePerformanceOutcome] {
        var byKey: [UUID: ExercisePerformanceOutcome] = [:]
        var noEntry: [ExercisePerformanceOutcome] = []

        for outcome in outcomes {
            if let entryID = outcome.exerciseEntry?.id {
                if let existing = byKey[entryID] {
                    if outcome.createdAt > existing.createdAt {
                        byKey[entryID] = outcome
                    }
                } else {
                    byKey[entryID] = outcome
                }
            } else {
                noEntry.append(outcome)
            }
        }

        return (Array(byKey.values) + noEntry).sorted {
            if $0.workoutDate == $1.workoutDate { return $0.id.uuidString < $1.id.uuidString }
            return $0.workoutDate < $1.workoutDate
        }
    }

    // MARK: - Week Anchors

    private static func programWeekWindow(
        runStartDate: Date,
        weekNumber: Int
    ) -> AnalysisWeekWindow {
        let startOfRun = isoCalendar.startOfDay(for: runStartDate)
        let weekStart = isoCalendar.date(byAdding: .day, value: max(0, (weekNumber - 1) * 7), to: startOfRun) ?? startOfRun
        return weekWindowFromStart(weekStart)
    }

    private static func weekWindowFromStart(_ weekStartDate: Date) -> AnalysisWeekWindow {
        let weekStart = isoCalendar.startOfDay(for: weekStartDate)
        let weekEndStart = isoCalendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let weekEnd = weekEndStart.addingTimeInterval(-1)
        return AnalysisWeekWindow(weekStartDate: weekStart, weekEndDate: weekEnd)
    }

    private static func inferredProgramWeekNumber(
        for date: Date,
        runStartDate: Date
    ) -> Int {
        let start = isoCalendar.startOfDay(for: runStartDate)
        let target = isoCalendar.startOfDay(for: date)
        let days = max(0, isoCalendar.dateComponents([.day], from: start, to: target).day ?? 0)
        return (days / 7) + 1
    }

    private static func resolvedProgramWeekNumber(
        for workout: Workout,
        runStartDate: Date
    ) -> Int {
        workout.programWeekNumber ?? inferredProgramWeekNumber(for: workout.date, runStartDate: runStartDate)
    }

    private static func overlapsAnyProgramRun(
        window: AnalysisWeekWindow,
        allRuns: [ProgramRun]
    ) -> Bool {
        allRuns.contains { run in
            let runStart = isoCalendar.startOfDay(for: run.startDate)
            let runEnd = run.endDate ?? .distantFuture
            return runStart <= window.weekEndDate && runEnd >= window.weekStartDate
        }
    }

    // MARK: - Shared Helpers

    private static func weightedAverage(values: [(Double, Double)]) -> Double? {
        let valid = values.filter { $0.1 > 0 }
        guard !valid.isEmpty else { return nil }
        let numerator = valid.reduce(0.0) { $0 + ($1.0 * $1.1) }
        let denominator = valid.reduce(0.0) { $0 + $1.1 }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }

    private static func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }

    private static func liftDisplayName(for key: String) -> String {
        switch key {
        case "squat": return "Squat"
        case "bench": return "Bench Press"
        case "deadlift": return "Deadlift"
        case "overheadPress": return "Overhead Press"
        case "row": return "Row"
        default: return key
        }
    }

    private static func dominantTrendStatus(
        from summary: [String: LiftTrendStatus]
    ) -> LiftTrendStatus? {
        guard !summary.isEmpty else { return nil }
        let counts = Dictionary(grouping: summary.values, by: { $0 }).mapValues(\.count)
        return counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key.rawValue > rhs.key.rawValue }
            return lhs.value < rhs.value
        })?.key
    }

    private static func classifyAggregatePerformance(_ score: Double) -> PerformanceScore {
        if score <= -12 { return .severeUnderperformance }
        if score <= -4 { return .underperformance }
        if score < 4 { return .onTarget }
        if score < 12 { return .overperformance }
        return .exceptionalPerformance
    }

    private static func fmt1(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f", value)
    }

    private static func fmt2(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }
}

private struct WeekAggregates {
    let weightedPerformanceScore: Double
    let adherenceScore: Double
    let observedFatigueScore: Double
    let completedHardSetsByMuscle: [ProgramVolumeMuscle: Double]
    let weightedHardSetsByMuscle: [ProgramVolumeMuscle: Double]
    let totalCompletedHardSets: Double
    let totalCompletedTonnageLbs: Double
    let mainLiftTopSetE1RM: [String: Double]
}

private enum AnalysisKey {
    case program(runID: UUID, weekNumber: Int)
    case standalone(weekStartDate: Date)
}

private enum TrendScope {
    case program(run: ProgramRun)
    case standalone

    var run: ProgramRun? {
        switch self {
        case .program(let run): return run
        case .standalone: return nil
        }
    }

    var runID: UUID? {
        run?.id
    }
}
