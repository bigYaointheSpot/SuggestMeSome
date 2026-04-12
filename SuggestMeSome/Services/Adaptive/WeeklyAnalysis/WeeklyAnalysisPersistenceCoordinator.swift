import Foundation
import SwiftData

enum WeeklyAnalysisPersistenceCoordinator {
    static func upsertAnalysis(
        for key: WeeklyAnalysisKey,
        context: ModelContext
    ) -> WeeklyTrainingAnalysis {
        switch key {
        case .program(let runID, let weekNumber):
            let analyses = (try? context.fetch(
                FetchDescriptor<WeeklyTrainingAnalysis>(
                    predicate: #Predicate<WeeklyTrainingAnalysis> {
                        $0.programRun?.id == runID && $0.programWeekNumber == weekNumber
                    }
                )
            )) ?? []
            if let existing = analyses.first {
                return existing
            }
        case .standalone(let weekStartDate):
            let analyses = (try? context.fetch(
                FetchDescriptor<WeeklyTrainingAnalysis>(
                    predicate: #Predicate<WeeklyTrainingAnalysis> {
                        $0.programRun == nil &&
                        $0.programWeekNumber == nil &&
                        $0.weekStartDate == weekStartDate
                    }
                )
            )) ?? []
            if let existing = analyses.first {
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

    static func configureBaseFields(
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
        analysis.focusSnapshot = nil
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

    static func applyAggregateFields(
        analysis: WeeklyTrainingAnalysis,
        aggregates: WeeklyAnalysisAggregates,
        plannedFatigueScore: Double?,
        plannedVolumeByMuscle: [ProgramVolumeMuscle: Double]
    ) {
        analysis.weightedPerformanceScore = aggregates.weightedPerformanceScore
        analysis.adherenceScore = aggregates.adherenceScore
        analysis.plannedFatigueScore = plannedFatigueScore
        analysis.observedFatigueScore = aggregates.observedFatigueScore
        analysis.fatigueStatus = aggregates.fatigueStatus
        analysis.totalCompletedHardSets = aggregates.totalCompletedHardSets
        analysis.totalCompletedTonnage = aggregates.totalCompletedTonnageLbs

        if plannedVolumeByMuscle.isEmpty {
            analysis.focusSnapshot = nil
        }
    }

    static func upsertVolumeMetrics(
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

    static func attachOutcomes(
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

    static func finalize(_ analysis: WeeklyTrainingAnalysis, at date: Date = .now) {
        analysis.isFinalized = true
        analysis.finalizedAt = date
    }
}
