import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt7ProgramDerivedStateTests {

    @Test func generatorDerivedStateSelectsBestPersonalRecordPerExercise() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let benchFive = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 5,
            weight: 225,
            unit: .lbs,
            dateAchieved: day(-10)
        )
        let benchFour = PersonalRecord(
            exerciseName: "Bench Press",
            repCount: 4,
            weight: 240,
            unit: .lbs,
            dateAchieved: day(-2)
        )
        let squatThree = PersonalRecord(
            exerciseName: "Back Squat",
            repCount: 3,
            weight: 315,
            unit: .lbs,
            dateAchieved: day(-4)
        )

        let state = ProgramGeneratorDerivedState.build(
            selectedFocus: nil,
            selectedLevel: nil,
            durationWeeks: 0,
            sessionsPerWeek: 0,
            steeringProfile: .balanced,
            carryForwardContext: nil,
            personalRecords: [benchFive, benchFour, squatThree],
            fallbackExplanationBundle: nil,
            context: context
        )

        #expect(state.adaptivePreview == nil)
        #expect(state.bestPRByExerciseName["Bench Press"]?.personalRecordID == benchFour.id)
        #expect(state.bestPRByExerciseName["Bench Press"]?.roundedOneRepMax == 270)
        #expect(state.bestPRByExerciseName["Back Squat"]?.roundedOneRepMax == 345)
    }

    @Test func generatorDerivedStateRefreshTokenChangesWhenAdaptiveInputsChange() {
        let personalRecords = [
            PersonalRecord(
                exerciseName: "Bench Press",
                repCount: 5,
                weight: 225,
                unit: .lbs,
                dateAchieved: day(-3)
            )
        ]
        let baseToken = ProgramGeneratorDerivedState.refreshToken(
            selectedFocus: .powerlifting,
            selectedLevel: .intermediate,
            durationWeeks: 8,
            sessionsPerWeek: 4,
            steeringProfile: .balanced,
            carryForwardContext: nil,
            personalRecords: personalRecords
        )
        let updatedToken = ProgramGeneratorDerivedState.refreshToken(
            selectedFocus: .powerlifting,
            selectedLevel: .intermediate,
            durationWeeks: 8,
            sessionsPerWeek: 4,
            steeringProfile: AdaptiveSteeringProfile(
                progressionBias: .push,
                recoveryBias: .balanced,
                continuityBias: .preserveAnchors
            ),
            carryForwardContext: ProgramGenerationCarryForwardContext(
                sourceProgramRunStableID: "prior-run",
                recommendationStableID: "rec-1",
                suggestedStyle: .dup,
                preservedExerciseNames: ["Bench Press"],
                rationaleText: "Keep the main anchor."
            ),
            personalRecords: personalRecords
        )

        #expect(baseToken != updatedToken)
    }

    @Test func programReviewDerivedStateMatchesWeeklySummariesAndProgramLogic() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Review Program",
            lengthInWeeks: 2,
            sessionsPerWeek: 1,
            source: .aiGenerated,
            progressionModel: .dup
        )
        let weekOne = ProgramWeekTemplate(weekNumber: 1, isDeloadWeek: false)
        let weekTwo = ProgramWeekTemplate(weekNumber: 2, isDeloadWeek: true)
        let sessionOne = ProgramSessionTemplate(
            sessionNumber: 1,
            sessionName: "Bench Priority",
            explainabilityReason: .specificityExposure
        )
        let sessionTwo = ProgramSessionTemplate(
            sessionNumber: 1,
            sessionName: "Deload Bench",
            explainabilityReason: .deloadRecovery
        )
        let warmup = ProgramSessionExercise(
            exerciseName: "Bench Press",
            orderIndex: 0,
            targetSets: 1,
            targetReps: 5,
            isWarmup: true
        )
        let topSet = ProgramSessionExercise(
            exerciseName: "Bench Press",
            orderIndex: 1,
            targetSets: 1,
            targetReps: 4,
            targetPercentage1RM: 0.85,
            prescribedWeight: 240,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            targetEffortType: .percentage1RM,
            usedMappedSourceLift: true
        )
        let backoff = ProgramSessionExercise(
            exerciseName: "Bench Press",
            orderIndex: 2,
            targetSets: 2,
            targetReps: 5,
            targetPercentage1RM: 0.78,
            prescribedWeight: 220,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .backoff,
            backoffPercentageDrop: 0.08,
            targetEffortType: .percentage1RM
        )
        let deloadWork = ProgramSessionExercise(
            exerciseName: "Bench Press",
            orderIndex: 0,
            targetSets: 2,
            targetReps: 5,
            targetRPE: 6.0,
            targetEffortType: .rpe
        )

        weekOne.program = program
        weekTwo.program = program
        program.weeks = [weekOne, weekTwo]
        sessionOne.week = weekOne
        sessionTwo.week = weekTwo
        weekOne.sessions = [sessionOne]
        weekTwo.sessions = [sessionTwo]
        warmup.session = sessionOne
        topSet.session = sessionOne
        backoff.session = sessionOne
        deloadWork.session = sessionTwo
        sessionOne.exercises = [warmup, topSet, backoff]
        sessionTwo.exercises = [deloadWork]

        context.insert(program)
        context.insert(weekOne)
        context.insert(weekTwo)
        context.insert(sessionOne)
        context.insert(sessionTwo)
        context.insert(warmup)
        context.insert(topSet)
        context.insert(backoff)
        context.insert(deloadWork)
        try context.save()

        let input = ProgramGenerationInput(
            focus: .powerlifting,
            level: .intermediate,
            durationWeeks: 6,
            sessionsPerWeek: 1,
            oneRepMaxes: ["Bench Press": (weight: 285, unit: "lbs")],
            steeringProfile: .balanced,
            explanationBundle: makeExplanationBundle(summary: "Bench-first block.")
        )
        let expectedWeeklySummaries = ProgramGenerationService().weeklySummary(for: program)
        let state = ProgramReviewDerivedState.build(
            program: program,
            input: input,
            context: context
        )

        #expect(state.phaseGroups.map(\.title) == ["Working Weeks", "Deload Weeks"])
        #expect(state.phaseGroups.map(\.weekRange) == ["Week 1", "Week 2"])
        #expect(state.programLogic.progressionModel == ProgramProgressionModel.dup.displayName)
        #expect(state.programLogic.usedLiftMapping)
        #expect(state.programLogic.usedTopSetBackoff)
        #expect(state.adaptiveExplanationBundle?.summary == "Bench-first block.")
        #expect(state.weeklySummariesByWeek.keys.sorted() == expectedWeeklySummaries.map(\.weekNumber).sorted())
        #expect(
            state.weeklySummariesByWeek[1]?.totalFatigueScore ==
            expectedWeeklySummaries.first(where: { $0.weekNumber == 1 })?.totalFatigueScore
        )
    }

    @Test func programReviewRefreshTokenChangesWhenProgramExercisesChange() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let program = TrainingProgram(
            name: "Token Program",
            lengthInWeeks: 1,
            sessionsPerWeek: 1,
            source: .aiGenerated
        )
        let week = ProgramWeekTemplate(weekNumber: 1)
        let session = ProgramSessionTemplate(sessionNumber: 1)
        let exercise = ProgramSessionExercise(
            exerciseName: "Bench Press",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            targetRPE: 7.5
        )

        week.program = program
        program.weeks = [week]
        session.week = week
        week.sessions = [session]
        exercise.session = session
        session.exercises = [exercise]

        let input = ProgramGenerationInput(
            focus: .powerlifting,
            level: .intermediate,
            durationWeeks: 6,
            sessionsPerWeek: 1,
            oneRepMaxes: ["Bench Press": (weight: 275, unit: "lbs")],
            steeringProfile: .balanced,
            explanationBundle: makeExplanationBundle(summary: "Token test.")
        )

        let initialToken = ProgramReviewDerivedState.refreshToken(program: program, input: input)
        exercise.targetReps = 6
        let updatedToken = ProgramReviewDerivedState.refreshToken(program: program, input: input)

        #expect(initialToken != updatedToken)
        _ = context
    }

    private func makeExplanationBundle(summary: String) -> AdaptiveExplanationBundle {
        AdaptiveExplanationBundle(
            category: .programGeneration,
            summary: summary,
            topReasons: [.highAdherence],
            adjustments: [],
            protectedConstraints: ["Keep the anchor lifts stable."],
            carryForwardSources: [],
            governance: .reviewRequired,
            steeringPreview: []
        )
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            PersonalRecord.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            ProgramRun.self,
            Workout.self,
            ExerciseEntry.self,
            SetEntry.self,
            ExercisePerformanceOutcome.self,
            MuscleGroup.self,
            Exercise.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            HealthKitDailySummary.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
