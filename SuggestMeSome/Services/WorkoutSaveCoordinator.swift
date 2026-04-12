//
//  WorkoutSaveCoordinator.swift
//  SuggestMeSome
//
//  Extracted non-UI workout save orchestration.
//

import Foundation
import SwiftData

struct WorkoutSaveProgramContext {
    let run: ProgramRun
    let weekNumber: Int
    let sessionNumber: Int
}

struct WorkoutSaveRequest {
    let startTime: Date
    let endTime: Date
    let caloriesText: String
    let comments: String
    let exerciseEntries: [DraftExerciseEntry]
    let programContext: WorkoutSaveProgramContext?
    let healthKitEnabled: Bool
    let healthKitWritebackEnabled: Bool
}

@MainActor
final class WorkoutSaveCoordinator {
    private let modelContext: ModelContext
    private let writebackCoordinator: WorkoutSaveHealthKitWritebackCoordinator

    init(
        modelContext: ModelContext,
        writebackCoordinator: WorkoutSaveHealthKitWritebackCoordinator? = nil
    ) {
        self.modelContext = modelContext
        self.writebackCoordinator = writebackCoordinator ?? WorkoutSaveHealthKitWritebackCoordinator()
    }

    @discardableResult
    func saveWorkout(using request: WorkoutSaveRequest) -> Workout {
        let workout = buildWorkout(using: request)
        modelContext.insert(workout)

        var personalRecords = TrainingContextQueryService.fetchPersonalRecords(context: modelContext)
        persistExerciseEntries(request.exerciseEntries, for: workout, at: request.endTime, personalRecords: &personalRecords)

        // Durably write the workout before any Feature 6 or Feature 8 service calls.
        try? modelContext.save()

        triggerHealthKitWritebackIfNeeded(for: workout, request: request)

        SessionOutcomeInferenceService.persistOutcomes(for: workout, context: modelContext)
        WeeklyTrainingAnalysisService.analyzeCompletedWeeks(triggeredBy: workout, context: modelContext)

        try? modelContext.save()

        if let run = request.programContext?.run {
            checkProgramCompletion(run: run)
        }

        return workout
    }

    private func buildWorkout(using request: WorkoutSaveRequest) -> Workout {
        let workout = Workout(
            date: request.endTime,
            startTime: request.startTime,
            durationSeconds: Int(request.endTime.timeIntervalSince(request.startTime)),
            caloriesBurned: Int(request.caloriesText),
            comments: request.comments.isEmpty ? nil : request.comments,
            programRun: request.programContext?.run,
            programWeekNumber: request.programContext?.weekNumber,
            programSessionNumber: request.programContext?.sessionNumber
        )
        workout.initializeSyncMetadataIfNeeded(at: request.endTime)
        return workout
    }

    private func persistExerciseEntries(
        _ drafts: [DraftExerciseEntry],
        for workout: Workout,
        at date: Date,
        personalRecords: inout [PersonalRecord]
    ) {
        for draftEntry in drafts {
            let entry = ExerciseEntry(
                exerciseName: draftEntry.exerciseName,
                unit: draftEntry.unit,
                orderIndex: draftEntry.orderIndex,
                isCardio: draftEntry.isCardio,
                cardioDurationSeconds: draftEntry.isCardio ? draftEntry.cardioDurationSeconds : nil,
                sourceProgramSessionExerciseID: draftEntry.sourceProgramSessionExerciseID,
                prescribedTargetSets: draftEntry.prescribedTargetSets,
                prescribedTargetReps: draftEntry.prescribedTargetReps,
                prescribedTargetPercentage1RM: draftEntry.prescribedTargetPercentage1RM,
                prescribedTargetRPE: draftEntry.prescribedTargetRPE,
                prescribedTargetRIR: draftEntry.prescribedTargetRIR,
                prescribedWeight: draftEntry.prescribedWeight,
                prescribedWeightUnit: draftEntry.prescribedWeightUnit,
                prescribedWorkingSetStyle: draftEntry.prescribedWorkingSetStyle,
                prescribedTargetEffortType: draftEntry.prescribedTargetEffortType
            )
            entry.effortFeedback = draftEntry.isCardio ? nil : draftEntry.effortFeedback
            entry.topSetRPE = draftEntry.isCardio ? nil : draftEntry.topSetRPE
            entry.workout = workout
            modelContext.insert(entry)

            guard !draftEntry.isCardio else { continue }

            for draftSet in draftEntry.sets {
                let reps = Int(draftSet.repsText) ?? 0
                let weight = Double(draftSet.weightText) ?? 0.0
                let setEntry = SetEntry(setNumber: draftSet.setNumber, reps: reps, weight: weight)
                setEntry.exerciseEntry = entry
                modelContext.insert(setEntry)

                guard reps > 0, weight > 0 else { continue }
                evaluatePR(
                    exerciseName: draftEntry.exerciseName,
                    unit: draftEntry.unit,
                    setEntry: setEntry,
                    date: date,
                    personalRecords: &personalRecords
                )
            }
        }
    }

    private func triggerHealthKitWritebackIfNeeded(for workout: Workout, request: WorkoutSaveRequest) {
        Task { @MainActor in
            await writebackCoordinator.performNonFatalWritebackIfEligible(
                for: workout,
                healthKitEnabled: request.healthKitEnabled,
                writebackEnabled: request.healthKitWritebackEnabled
            ) {
                try modelContext.save()
            }
        }
    }

    private func checkProgramCompletion(run: ProgramRun) {
        guard let program = run.program else { return }
        let expected = program.lengthInWeeks * program.sessionsPerWeek
        guard let completed = try? TrainingContextQueryService.completedWorkoutCount(for: run, context: modelContext) else {
            return
        }
        guard completed >= expected else { return }

        run.isCompleted = true
        run.endDate = Date.now
        run.markSyncUpdated(at: Date.now)
        try? modelContext.save()
    }

    /// Checks whether `setEntry` is a new personal record and updates the store accordingly.
    /// Weights are always compared in lbs to handle mixed-unit entries (1 kg = 2.20462 lbs).
    private func evaluatePR(
        exerciseName: String,
        unit: WeightUnit,
        setEntry: SetEntry,
        date: Date,
        personalRecords: inout [PersonalRecord]
    ) {
        let newWeightLbs = inLbs(setEntry.weight, unit: unit)

        if let existing = TrainingContextQueryService.personalRecord(
            exerciseName: exerciseName,
            repCount: setEntry.reps,
            in: personalRecords
        ) {
            guard newWeightLbs > inLbs(existing.weight, unit: existing.unit) else { return }
            existing.weight = setEntry.weight
            existing.unit = unit
            existing.dateAchieved = date
            existing.markSyncUpdated(at: date)
            setEntry.isPR = true
        } else {
            let pr = PersonalRecord(
                exerciseName: exerciseName,
                repCount: setEntry.reps,
                weight: setEntry.weight,
                unit: unit,
                dateAchieved: date
            )
            modelContext.insert(pr)
            personalRecords.append(pr)
            setEntry.isPR = true
        }
    }

    private func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }
}
