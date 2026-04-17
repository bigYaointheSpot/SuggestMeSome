import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature15Prompt2AdaptiveStateEngineTests {

    @Test func sparseHistoryFallsBackToConservativeAdaptiveSnapshot() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let engine = AdaptiveTrainingStateEngine(context: context)

        let snapshot = engine.buildSnapshot(
            focus: .fullBody,
            level: .intermediate,
            sessionsPerWeek: 3
        )

        #expect(snapshot.hasSparseHistory)
        #expect(snapshot.adherenceTier == .sparseHistory)
        #expect(snapshot.preferredAnchorExerciseNames.isEmpty)
        #expect(snapshot.blockedCanonicalLifts.isEmpty)
        #expect(snapshot.recentVolumeCompletionRate <= 0.60)
    }

    @Test func richHistoryDerivesMomentumPreferencesAndContinuityBias() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let program = TrainingProgram(
            name: "Powerlifting",
            lengthInWeeks: 8,
            sessionsPerWeek: 4,
            source: .aiGenerated
        )
        let run = ProgramRun(startDate: daysAgo(14))
        run.program = program
        run.continuitySnapshot = ProgramBlockContinuitySnapshot(
            sourceProgramRunStableID: "source-run",
            sourceTrainingProgramStableID: program.syncStableID,
            reviewStableID: "review-1",
            sourceProgramName: "Prior Block",
            snapshotRecordedAt: Date(),
            recommendationSnapshots: [],
            selectedRecommendationStableID: "rec-1",
            selectedRecommendationSnapshot: nil,
            declinedRecommendationStableIDs: [],
            decisionEvents: [],
            carriedForwardContext: ProgramGenerationCarryForwardContext(
                sourceProgramRunStableID: "source-run",
                recommendationStableID: "rec-1",
                suggestedStyle: .dup,
                preservedExerciseNames: ["Bench Press", "Back Squats"],
                rationaleText: "Carry forward strong anchors.",
                valueSources: [],
                intensityContext: nil
            ),
            editedPrefillSnapshot: nil,
            userEditedFields: []
        )
        context.insert(program)
        context.insert(run)

        let weekly = WeeklyTrainingAnalysis(
            weekStartDate: daysAgo(7),
            weekEndDate: Date(),
            programRun: run,
            trainingProgram: program,
            focusSnapshot: .powerlifting,
            programWorkoutCount: 4,
            totalOutcomeCount: 8,
            weightedPerformanceScore: 0.86,
            adherenceScore: 0.92,
            observedFatigueScore: 18,
            fatigueStatus: .manageable,
            totalCompletedHardSets: 52,
            isFinalized: true,
            finalizedAt: Date()
        )
        let benchTrend = LiftPerformanceTrend(
            programRun: run,
            trainingProgram: program,
            canonicalLiftKey: CanonicalLift.bench.rawValue,
            liftDisplayName: CanonicalLift.bench.displayName,
            totalDataPoints: 6,
            weightedSignalCount: 6,
            confidenceScore: 0.9,
            firstObservationDate: daysAgo(30),
            lastObservationDate: daysAgo(2),
            currentEstimated1RM: 250,
            previousEstimated1RM: 240,
            rollingBestEstimated1RM: 250,
            fourWeekChangePercent: 0.04,
            trendStatus: .improving,
            fatigueStatus: .manageable
        )
        context.insert(weekly)
        context.insert(benchTrend)

        seedRichWorkoutHistory(context: context, run: run)
        try context.save()

        let engine = AdaptiveTrainingStateEngine(context: context)
        let snapshot = engine.buildSnapshot(
            focus: .powerlifting,
            level: .intermediate,
            sessionsPerWeek: 4,
            activeRunOverride: run
        )

        #expect(!snapshot.hasSparseHistory)
        #expect(snapshot.adherenceTier == .high)
        #expect(snapshot.preferredAnchorExerciseNames.contains("Bench Press"))
        #expect(snapshot.underusedExerciseNames.contains("Overhead Press"))
        #expect(snapshot.liftMomentumByCanonicalLift[.bench] == .improving)
        #expect(snapshot.continuityBias > 0.40)
        #expect(snapshot.equipmentReliabilityScore > 0.45)
    }

    @Test func doseTargetProfileStepsBackWhenFatigueAndInterferenceRise() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let engine = AdaptiveTrainingStateEngine(context: context)
        let snapshot = TrainingStateSnapshot(
            historyWindowWorkoutCount: 18,
            hasSparseHistory: false,
            adherenceTier: .low,
            recentVolumeCompletionRate: 0.58,
            fatigueStatus: .high,
            recoveryPressure: .elevated,
            liftMomentumByCanonicalLift: [.squat: .declining],
            perMuscleStressSaturation: [.quads: 1.1],
            preferredAnchorExerciseNames: ["Back Squats"],
            underusedExerciseNames: [],
            activeProgramInterferenceRisk: 0.82,
            equipmentReliabilityScore: 0.80,
            continuityBias: 0.25,
            blockedCanonicalLifts: [.squat]
        )

        let dose = engine.buildDoseTargetProfile(
            focus: .powerlifting,
            level: .intermediate,
            sessionsPerWeek: 4,
            snapshot: snapshot
        )

        #expect(dose.weeklyVolumeScale < 1.0)
        #expect(dose.sessionStressScale < 1.0)
        #expect(dose.rirOffset > 0.0)
        #expect(dose.deloadIntervalOverride != nil)
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
            ExercisePerformanceOutcome.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AdaptationEventHistory.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedRichWorkoutHistory(context: ModelContext, run: ProgramRun) {
        let workoutSpecs: [[String]] = [
            ["Overhead Press", "Pull-ups"],
            ["Overhead Press", "Deadlift"],
            ["Bench Press", "Barbell Row"],
            ["Bench Press", "Back Squats"],
            ["Bench Press", "Push-ups"],
            ["Bench Press", "Romanian Deadlift"],
            ["Bench Press", "Back Squats"],
            ["Bench Press", "Barbell Row"],
            ["Bench Press", "Push-ups"],
            ["Bench Press", "Back Squats"],
        ]

        for (offset, names) in workoutSpecs.enumerated() {
            let workoutDate = daysAgo(18 - offset)
            let workout = Workout(
                date: workoutDate,
                startTime: workoutDate,
                durationSeconds: 3_600,
                sourceType: .loggedInApp
            )
            workout.programRun = run
            context.insert(workout)

            var entries: [ExerciseEntry] = []
            for (index, name) in names.enumerated() {
                let entry = ExerciseEntry(
                    exerciseName: name,
                    unit: .lbs,
                    orderIndex: index
                )
                let set = SetEntry(setNumber: 1, reps: 5, weight: 185 + Double(index * 20))
                entry.sets = [set]
                entry.topSetRPE = 8.5
                entry.workout = workout
                entries.append(entry)
                context.insert(entry)
                context.insert(set)
            }
            workout.exerciseEntries = entries
        }
    }

    private func daysAgo(_ value: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -value, to: Date()) ?? Date()
    }
}
