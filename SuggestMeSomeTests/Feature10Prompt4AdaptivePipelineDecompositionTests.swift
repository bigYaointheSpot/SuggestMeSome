import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature10Prompt4AdaptivePipelineDecompositionTests {

    @Test func weeklyAggregationComputesExpectedPerformanceAdherenceAndVolume() throws {
        let program = makeProgram(name: "Powerlifting Test", sessionsPerWeek: 2)
        let run = ProgramRun(startDate: day(0))
        run.program = program

        let programWorkoutA = makeWorkout(date: day(1), run: run, week: 1, session: 1, exerciseName: "Back Squats", reps: 5, weight: 315)
        let programWorkoutB = makeWorkout(date: day(3), run: run, week: 1, session: 2, exerciseName: "Bench Press", reps: 5, weight: 225)
        let standaloneWorkout = makeWorkout(date: day(4), run: nil, week: nil, session: nil, exerciseName: "Barbell Row", reps: 8, weight: 185)

        let outcomes = [
            makeOutcome(workout: programWorkoutA, entry: programWorkoutA.exerciseEntries[0], score: 10, completionRatio: 1.0, signalWeight: 1.0, fatigue: .manageable),
            makeOutcome(workout: programWorkoutB, entry: programWorkoutB.exerciseEntries[0], score: 0, completionRatio: 0.8, signalWeight: 1.0, fatigue: .low),
            makeOutcome(workout: standaloneWorkout, entry: standaloneWorkout.exerciseEntries[0], score: -5, completionRatio: 0.9, signalWeight: 0.6, fatigue: .elevated),
        ]

        let aggregates = WeeklyAnalysisAggregateScorer.aggregateWeekSignals(
            selectedWorkouts: [programWorkoutA, programWorkoutB, standaloneWorkout],
            selectedOutcomes: outcomes,
            plannedFatigueScore: 35
        )

        #expect(abs(aggregates.weightedPerformanceScore - 2.69230769) < 0.0001)
        #expect(abs(aggregates.adherenceScore - 0.96) < 0.0001)
        #expect(aggregates.totalCompletedHardSets == 3)
        #expect(aggregates.totalCompletedTonnageLbs > 0)
        #expect(aggregates.fatigueStatus != .critical)
    }

    @Test func dedupeBehaviorKeepsLatestProgramSessionWorkoutAndLatestOutcomeByEntry() {
        let run = ProgramRun(startDate: day(0))

        let staleSession = makeWorkout(date: day(1), run: run, week: 1, session: 1, exerciseName: "Back Squats", reps: 5, weight: 300)
        let latestSession = makeWorkout(date: day(2), run: run, week: 1, session: 1, exerciseName: "Back Squats", reps: 5, weight: 315)
        let noSession = makeWorkout(date: day(2), run: run, week: 1, session: nil, exerciseName: "Romanian Deadlift", reps: 8, weight: 225)

        let dedupedWorkouts = WeeklyAnalysisDedupeHelper.dedupeProgramWorkoutsBySession([staleSession, latestSession, noSession])
        #expect(dedupedWorkouts.count == 2)
        #expect(dedupedWorkouts.contains { $0.id == latestSession.id })
        #expect(dedupedWorkouts.contains { $0.id == noSession.id })
        #expect(!dedupedWorkouts.contains { $0.id == staleSession.id })

        let entry = latestSession.exerciseEntries[0]
        let staleOutcome = makeOutcome(
            workout: latestSession,
            entry: entry,
            score: 1,
            completionRatio: 0.8,
            signalWeight: 1.0,
            fatigue: .manageable,
            createdAt: day(2)
        )
        let latestOutcome = makeOutcome(
            workout: latestSession,
            entry: entry,
            score: 2,
            completionRatio: 1.0,
            signalWeight: 1.0,
            fatigue: .manageable,
            createdAt: day(3)
        )

        let dedupedOutcomes = WeeklyAnalysisDedupeHelper.dedupeOutcomes([staleOutcome, latestOutcome])
        #expect(dedupedOutcomes.count == 1)
        #expect(dedupedOutcomes.first?.id == latestOutcome.id)
    }

    @Test func fatigueAndAdherenceScoringContinuityMatchesThresholds() {
        let elevatedOutcomes = [
            makeOutcome(workout: makeWorkout(date: day(1), run: nil, week: nil, session: nil, exerciseName: "Deadlift", reps: 3, weight: 405), entry: nil, score: 0, completionRatio: nil, signalWeight: 1.0, fatigue: .high),
            makeOutcome(workout: makeWorkout(date: day(2), run: nil, week: nil, session: nil, exerciseName: "Deadlift", reps: 3, weight: 405), entry: nil, score: 0, completionRatio: nil, signalWeight: 1.0, fatigue: .critical)
        ]

        let observed = WeeklyAnalysisFatigueEvaluator.observedFatigueScore(outcomes: elevatedOutcomes)
        let status = WeeklyAnalysisFatigueEvaluator.inferWeeklyFatigueStatus(observedFatigueScore: observed, plannedFatigueScore: 6)
        #expect(observed > 0)
        #expect(status == .high || status == .critical)

        let standaloneWorkout = makeWorkout(date: day(1), run: nil, week: nil, session: nil, exerciseName: "Barbell Row", reps: 8, weight: 185)
        let adherence = WeeklyAnalysisAdherenceScorer.compute(
            selectedWorkouts: [standaloneWorkout],
            selectedOutcomes: []
        )
        #expect(adherence == 1.0)
    }

    @Test func proposalPipelineOrchestrationRespectsFocusMatrixAndProducesWeeklyReview() throws {
        let focusNames = [
            "Powerlifting",
            "Bodybuilding",
            "Powerbuilding",
            "General Fitness",
            "Full Body",
        ]

        for focusName in focusNames {
            let container = try makeInMemoryContainer()
            let context = container.mainContext

            let fixture = makeProgram(name: "\(focusName) Intermediate", sessionsPerWeek: 1)
            persistProgram(fixture, context: context)

            let run = ProgramRun(startDate: day(0))
            run.program = fixture
            context.insert(run)

            let analysis = WeeklyTrainingAnalysis(
                weekStartDate: day(0),
                weekEndDate: day(6),
                programRun: run,
                trainingProgram: fixture,
                programWeekNumber: 1,
                fatigueStatus: .manageable,
                isFinalized: true,
                finalizedAt: day(7)
            )
            context.insert(analysis)

            let outcome = ExercisePerformanceOutcome(
                analysis: analysis,
                programRun: run,
                workoutDate: day(3),
                programWeekNumber: 1,
                programSessionNumber: 1,
                sourceProgramSessionExerciseID: fixture.weeks[0].sessions[0].exercises[0].id,
                exerciseName: "Back Squats",
                canonicalLiftKey: CanonicalLift.squat.rawValue,
                signalSource: .programLinked,
                signalConfidence: .high,
                signalWeight: 1.0,
                actualSetCount: 3,
                actualAverageReps: 5,
                actualAverageWeight: 335,
                actualTopSetReps: 5,
                actualTopSetWeight: 335,
                actualTopSetEstimated1RM: 390,
                completionRatio: 1.0,
                performanceScoreValue: 10,
                performanceScore: .overperformance,
                inferredFatigueStatus: .manageable,
                isTopSetSignal: true,
                notes: "focus-matrix"
            )
            analysis.outcomes.append(outcome)
            context.insert(outcome)

            WeeklyAnalysisProposalPipelineCoordinator.finalizeProgramWeek(from: analysis, context: context)
            try context.save()

            let proposals = try fetchAll(AdaptationProposal.self, context)
            #expect(proposals.allSatisfy { $0.proposalStatus != .confirmed && $0.proposalStatus != .rejected })

            let reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
            #expect(reviews.contains { $0.programRun?.id == run.id && $0.weekStart == day(0) })
        }
    }

    @Test func workoutSaveDurabilityIsMaintainedWhenAdaptiveSideEffectsThrow() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let coordinator = WorkoutSaveCoordinator(
            modelContext: context,
            outcomePersistor: { _, _ in
                throw TestInjectedError.sideEffectFailure
            },
            weeklyAnalyzer: { _, _ in
                throw TestInjectedError.sideEffectFailure
            }
        )

        let start = day(1)
        let end = start.addingTimeInterval(1800)
        let request = WorkoutSaveRequest(
            startTime: start,
            endTime: end,
            caloriesText: "350",
            comments: "durability",
            exerciseEntries: [
                DraftExerciseEntry(
                    exerciseName: "Back Squats",
                    unit: .lbs,
                    orderIndex: 0,
                    sets: [DraftSet(setNumber: 1, repsText: "5", weightText: "315")]
                )
            ],
            programContext: nil,
            healthKitEnabled: false,
            healthKitWritebackEnabled: false
        )

        let workout = coordinator.saveWorkout(using: request)

        let workouts = try fetchAll(Workout.self, context)
        let entries = try fetchAll(ExerciseEntry.self, context)
        let sets = try fetchAll(SetEntry.self, context)

        #expect(workouts.contains { $0.id == workout.id })
        #expect(entries.count == 1)
        #expect(sets.count == 1)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Workout.self,
            ProgramRun.self,
            TrainingProgram.self,
            ProgramWeekTemplate.self,
            ProgramSessionTemplate.self,
            ProgramSessionExercise.self,
            AdaptationProposal.self,
            AppliedProgramOverlay.self,
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            WeeklyTrainingAnalysis.self,
            WeeklyVolumeMetric.self,
            ExercisePerformanceOutcome.self,
            LiftPerformanceTrend.self,
            LiftTrendSnapshot.self,
            ExerciseEntry.self,
            SetEntry.self,
            Exercise.self,
            MuscleGroup.self,
            PersonalRecord.self,
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
            HealthKitDailySummary.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func day(_ offset: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12, minute: 0, second: 0)) ?? Date()
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }

    private func persistProgram(_ program: TrainingProgram, context: ModelContext) {
        for week in program.weeks {
            week.program = program
            for session in week.sessions {
                session.week = week
                for exercise in session.exercises {
                    exercise.session = session
                }
            }
        }
        context.insert(program)
    }

    private func makeProgram(name: String, sessionsPerWeek: Int) -> TrainingProgram {
        let week1Main = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            targetPercentage1RM: 0.80,
            prescribedWeight: 315,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )
        let week2Main = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 4,
            targetPercentage1RM: 0.82,
            prescribedWeight: 325,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )

        let week1 = ProgramWeekTemplate(weekNumber: 1)
        week1.sessions = (0..<sessionsPerWeek).map { index in
            let session = ProgramSessionTemplate(sessionNumber: index + 1)
            session.exercises = [week1Main]
            return session
        }

        let week2 = ProgramWeekTemplate(weekNumber: 2)
        week2.sessions = (0..<sessionsPerWeek).map { index in
            let session = ProgramSessionTemplate(sessionNumber: index + 1)
            session.exercises = [week2Main]
            return session
        }

        let program = TrainingProgram(
            name: name,
            lengthInWeeks: 2,
            sessionsPerWeek: sessionsPerWeek,
            source: .aiGenerated
        )
        program.weeks = [week1, week2]
        return program
    }

    private func makeWorkout(
        date: Date,
        run: ProgramRun?,
        week: Int?,
        session: Int?,
        exerciseName: String,
        reps: Int,
        weight: Double
    ) -> Workout {
        let workout = Workout(
            date: date,
            startTime: date.addingTimeInterval(-1800),
            durationSeconds: 1800,
            programRun: run,
            programWeekNumber: week,
            programSessionNumber: session
        )
        let entry = ExerciseEntry(exerciseName: exerciseName, unit: .lbs, orderIndex: 0)
        entry.workout = workout
        workout.exerciseEntries = [entry]

        let setEntry = SetEntry(setNumber: 1, reps: reps, weight: weight)
        setEntry.exerciseEntry = entry
        entry.sets = [setEntry]

        return workout
    }

    private func makeOutcome(
        workout: Workout,
        entry: ExerciseEntry?,
        score: Double,
        completionRatio: Double?,
        signalWeight: Double,
        fatigue: FatigueStatus,
        createdAt: Date = .now
    ) -> ExercisePerformanceOutcome {
        ExercisePerformanceOutcome(
            createdAt: createdAt,
            workout: workout,
            exerciseEntry: entry,
            workoutDate: workout.date,
            programWeekNumber: workout.programWeekNumber,
            programSessionNumber: workout.programSessionNumber,
            exerciseName: entry?.exerciseName ?? "Unknown",
            canonicalLiftKey: CanonicalLift.deadlift.rawValue,
            signalSource: workout.programRun == nil ? .standalone : .programLinked,
            signalConfidence: .medium,
            signalWeight: signalWeight,
            actualSetCount: 1,
            actualAverageReps: Double(entry?.sets.first?.reps ?? 0),
            actualAverageWeight: entry?.sets.first?.weight,
            actualTopSetReps: entry?.sets.first?.reps,
            actualTopSetWeight: entry?.sets.first?.weight,
            actualTopSetEstimated1RM: 350,
            completionRatio: completionRatio,
            performanceScoreValue: score,
            performanceScore: .onTarget,
            inferredFatigueStatus: fatigue,
            isTopSetSignal: true,
            notes: "prompt4"
        )
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }
}

private enum TestInjectedError: Error {
    case sideEffectFailure
}
