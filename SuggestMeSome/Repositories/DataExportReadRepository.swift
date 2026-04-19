//
//  DataExportReadRepository.swift
//  SuggestMeSome
//
//  Feature 16 Prompt 8 — lazy export summary and CSV read snapshots.
//

import Foundation
import SwiftData

struct DataExportSummarySnapshot {
    static let placeholder = DataExportSummarySnapshot(
        muscleGroupCount: 0,
        exerciseCount: 0,
        workoutCount: 0,
        exerciseEntryCount: 0,
        setCount: 0,
        personalRecordCount: 0,
        trainingProgramCount: 0,
        programRunCount: 0,
        dailyCoachCheckInCount: 0,
        weeklyTrainingAnalysisCount: 0,
        adaptationProposalCount: 0,
        healthKitDailySummaryCount: 0
    )

    let muscleGroupCount: Int
    let exerciseCount: Int
    let workoutCount: Int
    let exerciseEntryCount: Int
    let setCount: Int
    let personalRecordCount: Int
    let trainingProgramCount: Int
    let programRunCount: Int
    let dailyCoachCheckInCount: Int
    let weeklyTrainingAnalysisCount: Int
    let adaptationProposalCount: Int
    let healthKitDailySummaryCount: Int

    var coachAndAdaptiveCount: Int {
        dailyCoachCheckInCount + weeklyTrainingAnalysisCount + adaptationProposalCount
    }
}

struct WorkoutCSVExportRow: Sendable {
    let dateString: String
    let duration: String
    let exerciseName: String
    let muscleGroupName: String
    let setNumber: Int
    let weightValue: String
    let unitValue: String
    let repsValue: String
    let isPersonalRecord: Bool
}

struct WorkoutCSVExportData: Sendable {
    let workoutCount: Int
    let exerciseEntryCount: Int
    let setCount: Int
    let rows: [WorkoutCSVExportRow]
}

enum DataExportReadRepository {
    static func summarySnapshot(context: ModelContext) -> DataExportSummarySnapshot {
        DataExportSummarySnapshot(
            muscleGroupCount: count(FetchDescriptor<MuscleGroup>(), context: context),
            exerciseCount: count(FetchDescriptor<Exercise>(), context: context),
            workoutCount: count(FetchDescriptor<Workout>(), context: context),
            exerciseEntryCount: count(FetchDescriptor<ExerciseEntry>(), context: context),
            setCount: count(FetchDescriptor<SetEntry>(), context: context),
            personalRecordCount: count(FetchDescriptor<PersonalRecord>(), context: context),
            trainingProgramCount: count(FetchDescriptor<TrainingProgram>(), context: context),
            programRunCount: count(FetchDescriptor<ProgramRun>(), context: context),
            dailyCoachCheckInCount: count(FetchDescriptor<DailyCoachCheckIn>(), context: context),
            weeklyTrainingAnalysisCount: count(FetchDescriptor<WeeklyTrainingAnalysis>(), context: context),
            adaptationProposalCount: count(FetchDescriptor<AdaptationProposal>(), context: context),
            healthKitDailySummaryCount: count(FetchDescriptor<HealthKitDailySummary>(), context: context)
        )
    }

    static func workoutCSVExportData(context: ModelContext) -> WorkoutCSVExportData {
        let workouts = (try? context.fetch(
            FetchDescriptor<Workout>(
                sortBy: [SortDescriptor(\Workout.date, order: .forward)]
            )
        )) ?? []
        let exercises = (try? context.fetch(
            FetchDescriptor<Exercise>(
                sortBy: [SortDescriptor(\Exercise.name, order: .forward)]
            )
        )) ?? []
        let exerciseGroupLookup = exercises.reduce(into: [String: String]()) { partialResult, exercise in
            partialResult[exercise.name] = exercise.muscleGroup?.name ?? ""
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var rows: [WorkoutCSVExportRow] = []
        var exerciseEntryCount = 0
        var setCount = 0

        for workout in workouts {
            let dateString = formatter.string(from: workout.date)
            let duration = workout.formattedDuration
            let entries = workout.exerciseEntries.sorted { $0.orderIndex < $1.orderIndex }
            exerciseEntryCount += entries.count

            for entry in entries {
                let muscleGroupName = exerciseGroupLookup[entry.exerciseName] ?? ""
                if entry.isCardio {
                    rows.append(
                        WorkoutCSVExportRow(
                            dateString: dateString,
                            duration: duration,
                            exerciseName: entry.exerciseName,
                            muscleGroupName: muscleGroupName,
                            setNumber: 1,
                            weightValue: "\(entry.cardioDurationSeconds ?? 0)",
                            unitValue: "sec",
                            repsValue: "1",
                            isPersonalRecord: false
                        )
                    )
                    continue
                }

                let sortedSets = entry.sets.sorted(by: { $0.setNumber < $1.setNumber })
                setCount += sortedSets.count
                for set in sortedSets {
                    rows.append(
                        WorkoutCSVExportRow(
                            dateString: dateString,
                            duration: duration,
                            exerciseName: entry.exerciseName,
                            muscleGroupName: muscleGroupName,
                            setNumber: set.setNumber,
                            weightValue: "\(set.weight)",
                            unitValue: entry.unit.rawValue,
                            repsValue: "\(set.reps)",
                            isPersonalRecord: set.isPR
                        )
                    )
                }
            }
        }

        return WorkoutCSVExportData(
            workoutCount: workouts.count,
            exerciseEntryCount: exerciseEntryCount,
            setCount: setCount,
            rows: rows
        )
    }

    private static func count<Model: PersistentModel>(
        _ descriptor: FetchDescriptor<Model>,
        context: ModelContext
    ) -> Int {
        (try? context.fetchCount(descriptor)) ?? 0
    }
}
