import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature15Prompt2DailyGenerationAdaptiveTests {

    @Test func recommendationCarriesAdaptiveProgramContextIntoBuildRequest() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let groups = makeSeededMuscleGroups(context: context)
        seedActiveProgram(context: context)

        let service = SuggestMeSomeRecommendationService(context: context)
        let configuration = SuggestMeSomeSessionConfiguration(
            mode: .push,
            goal: .strength,
            equipmentProfile: .fullGym,
            durationMinutes: 50,
            intensity: 4
        )

        let recommendation = service.recommendSession(
            configuration: configuration,
            allMuscleGroups: groups
        )

        #expect(recommendation.request?.activeProgramContext?.shouldSupportActiveProgram == true)
        #expect(recommendation.request?.stateSnapshotOverride != nil)
    }

    @Test func generationIsDeterministicForIdenticalAdaptiveRequests() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let groups = makeSeededMuscleGroups(context: context)
        let service = SuggestMeSomeGenerationService(context: context)

        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 50,
            intensity: 4,
            selectedMuscleGroups: groups.filter { ["Chest", "Back", "Shoulders", "Legs"].contains($0.name) },
            selectedExercises: [],
            goal: .strength,
            equipmentProfile: .fullGym,
            sessionMode: .fullBody,
            activeProgramContext: DailyProgramContext(
                shouldSupportActiveProgram: true,
                activeProgramName: "Powerlifting",
                nextSessionName: "Bench Day",
                nextSessionMode: .push,
                nextSessionAnchorExercises: ["Bench Press"],
                missedMovementFamilies: ["horizontalPull"],
                blockedCanonicalLifts: [.bench],
                interferenceScore: 0.85
            ),
            stateSnapshotOverride: makeSnapshot()
        )

        let workout1 = service.generateWorkout(request: request)
        let workout2 = service.generateWorkout(request: request)

        #expect(workout1.exercises.map { $0.exercise.name } == workout2.exercises.map { $0.exercise.name })
    }

    @Test func activeProgramContextPreventsInterferingAnchorLiftSelection() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let groups = makeSeededMuscleGroups(context: context)
        let service = SuggestMeSomeGenerationService(context: context)

        let request = SuggestMeSomeGenerationRequest(
            generationType: .custom,
            durationMinutes: 45,
            intensity: 4,
            selectedMuscleGroups: groups.filter { ["Chest", "Shoulders", "Arms", "Back"].contains($0.name) },
            selectedExercises: [],
            goal: .strength,
            equipmentProfile: .fullGym,
            sessionMode: .push,
            activeProgramContext: DailyProgramContext(
                shouldSupportActiveProgram: true,
                activeProgramName: "Powerlifting",
                nextSessionName: "Bench Priority",
                nextSessionMode: .push,
                nextSessionAnchorExercises: ["Bench Press"],
                missedMovementFamilies: ["horizontalPull"],
                blockedCanonicalLifts: [.bench],
                interferenceScore: 0.90
            ),
            stateSnapshotOverride: makeSnapshot()
        )

        let workout = service.generateWorkout(request: request)
        let names = workout.exercises.map { $0.exercise.name }

        #expect(!names.contains("Bench Press"))
        #expect(names.contains("Barbell Row") || names.contains("Pull-ups"))
    }

    @Test func strengthPrescriptionUsesLowerRepWorkThanHypertrophy() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let chest = MuscleGroup(name: "Chest")
        let bench = Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest)
        context.insert(chest)
        context.insert(bench)
        context.insert(
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 8,
                weight: 205,
                unit: .lbs,
                dateAchieved: Date()
            )
        )
        try context.save()

        let service = SuggestMeSomeWorkoutPrescriptionService(
            personalRecordLookupService: SuggestMeSomePersonalRecordLookupService(context: context),
            timeBudgetService: SuggestMeSomeTimeBudgetService()
        )

        let strength = service.prescribeStrengthExercise(
            bench,
            intensity: 4,
            goal: .strength,
            prescriptionStyle: .strengthTopSetBackoff
        )
        let hypertrophy = service.prescribeStrengthExercise(
            bench,
            intensity: 4,
            goal: .hypertrophy,
            prescriptionStyle: .hypertrophyDoubleProgression
        )

        let strengthWorking = strength.sets.filter { !$0.isWarmup }
        let hypertrophyWorking = hypertrophy.sets.filter { !$0.isWarmup }

        #expect((strengthWorking.first?.suggestedReps ?? 99) < (hypertrophyWorking.first?.suggestedReps ?? 0))
    }

    private func makeSnapshot() -> TrainingStateSnapshot {
        TrainingStateSnapshot(
            historyWindowWorkoutCount: 12,
            hasSparseHistory: false,
            adherenceTier: .moderate,
            recentVolumeCompletionRate: 0.82,
            fatigueStatus: .manageable,
            recoveryPressure: .neutral,
            liftMomentumByCanonicalLift: [.bench: .stable],
            perMuscleStressSaturation: [:],
            preferredAnchorExerciseNames: ["Bench Press", "Back Squats"],
            underusedExerciseNames: ["Barbell Row"],
            activeProgramInterferenceRisk: 0.85,
            equipmentReliabilityScore: 0.90,
            continuityBias: 0.45,
            blockedCanonicalLifts: [.bench]
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            MuscleGroup.self,
            Exercise.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSeededMuscleGroups(context: ModelContext) -> [MuscleGroup] {
        let chest = MuscleGroup(name: "Chest")
        chest.exercises = [
            Exercise(name: "Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Dumbbell Bench Press", exerciseType: .compound, muscleGroup: chest),
            Exercise(name: "Push-ups", exerciseType: .accessory, muscleGroup: chest),
        ]

        let back = MuscleGroup(name: "Back")
        back.exercises = [
            Exercise(name: "Barbell Row", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Pull-ups", exerciseType: .compound, muscleGroup: back),
            Exercise(name: "Deadlift", exerciseType: .compound, muscleGroup: back),
        ]

        let shoulders = MuscleGroup(name: "Shoulders")
        shoulders.exercises = [
            Exercise(name: "Overhead Press", exerciseType: .compound, muscleGroup: shoulders),
            Exercise(name: "DB Shoulder Press", exerciseType: .accessory, muscleGroup: shoulders),
            Exercise(name: "Cable Lateral Raise", exerciseType: .isolation, muscleGroup: shoulders),
        ]

        let arms = MuscleGroup(name: "Arms")
        arms.exercises = [
            Exercise(name: "Dips", exerciseType: .compound, muscleGroup: arms),
            Exercise(name: "Barbell Curl", exerciseType: .isolation, muscleGroup: arms),
        ]

        let legs = MuscleGroup(name: "Legs")
        legs.exercises = [
            Exercise(name: "Back Squats", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Romanian Deadlift", exerciseType: .compound, muscleGroup: legs),
            Exercise(name: "Bulgarian Split Squat", exerciseType: .compound, muscleGroup: legs),
        ]

        let core = MuscleGroup(name: "Core")
        core.exercises = [
            Exercise(name: "Plank", exerciseType: .accessory, muscleGroup: core),
            Exercise(name: "Dead Bug", exerciseType: .accessory, muscleGroup: core),
        ]

        let cardio = MuscleGroup(name: "Cardio")
        cardio.exercises = [
            Exercise(name: "Exercise Bike", exerciseType: .cardio, muscleGroup: cardio),
            Exercise(name: "Rowing Machine", exerciseType: .cardio, muscleGroup: cardio),
            Exercise(name: "Jump Rope", exerciseType: .cardio, muscleGroup: cardio),
        ]

        let groups = [chest, back, shoulders, arms, legs, core, cardio]
        for group in groups {
            context.insert(group)
            for exercise in group.exercises {
                context.insert(exercise)
            }
        }
        return groups
    }

    private func seedActiveProgram(context: ModelContext) {
        let program = TrainingProgram(
            name: "Powerlifting",
            lengthInWeeks: 8,
            sessionsPerWeek: 4,
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: Date())
        run.program = program

        let week = ProgramWeekTemplate(weekNumber: 1)
        week.program = program
        let session = ProgramSessionTemplate(sessionNumber: 1, sessionName: "Bench Priority")
        session.week = week
        let bench = ProgramSessionExercise(exerciseName: "Bench Press", orderIndex: 0)
        bench.session = session
        session.exercises = [bench]
        week.sessions = [session]
        program.weeks = [week]

        context.insert(program)
        context.insert(run)
        context.insert(week)
        context.insert(session)
        context.insert(bench)
    }
}
