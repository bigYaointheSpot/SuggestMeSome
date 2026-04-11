//
//  Feature7ValidationTests.swift
//  SuggestMeSomeTests
//
//  Feature 7 — Daily Coach validation coverage.
//  Tests cover check-in create/update, recommendation engine paths,
//  draft-only preparation, effort feedback persistence, weekly review
//  upsert, and the workout-save regression guard.
//

import Foundation
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature7ValidationTests {

    // MARK: - Check-In Create vs Update

    @Test func checkInSameDayCreateThenUpdatePreservesOneRecord() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let today = Calendar.current.startOfDay(for: Date())

        let first = DailyCoachCheckIn(date: today, sleepQuality: 3, soreness: 2, energy: 3, stress: 2)
        context.insert(first)
        try context.save()

        var fetched = try fetchAll(DailyCoachCheckIn.self, context)
        #expect(fetched.count == 1)
        #expect(fetched[0].sleepQuality == 3)

        // Simulate in-place update of the same-day record
        fetched[0].sleepQuality = 5
        fetched[0].energy = 4
        fetched[0].updatedAt = Date()
        try context.save()

        let afterUpdate = try fetchAll(DailyCoachCheckIn.self, context)
        #expect(afterUpdate.count == 1, "Same-day check-in must remain a single record")
        #expect(afterUpdate[0].sleepQuality == 5)
        #expect(afterUpdate[0].energy == 4)
    }

    @Test func checkInDifferentDaysCreatesTwoRecords() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        let today     = Calendar.current.startOfDay(for: Date())

        context.insert(DailyCoachCheckIn(date: yesterday, sleepQuality: 3, soreness: 2, energy: 3, stress: 2))
        context.insert(DailyCoachCheckIn(date: today,     sleepQuality: 4, soreness: 1, energy: 4, stress: 1))
        try context.save()

        let fetched = try fetchAll(DailyCoachCheckIn.self, context)
        #expect(fetched.count == 2)
    }

    // MARK: - Recommendation Engine — Program Path

    @Test func recommendationNeutralReadinessProducesRunAsPlanned() {
        // Composite = (3 + 3 + (6-2) + (6-2)) / 4 = 3.5 → .neutral
        let checkIn = DailyCoachCheckIn(date: Date(), sleepQuality: 3, soreness: 2, energy: 3, stress: 2)
        let run = makeDetachedRun()

        let rec = DailyCoachRecommendationService.generate(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(rec.readinessTier == .neutral)
        #expect(rec.primarySuggestion.type == .runAsPlanned)
        #expect(rec.hasPainFlag == false)
    }

    @Test func recommendationLowReadinessProducesTrimOrReduce() {
        // Composite = (1 + 1 + (6-5) + (6-5)) / 4 = 1.0 → .low
        let checkIn = DailyCoachCheckIn(date: Date(), sleepQuality: 1, soreness: 5, energy: 1, stress: 5)
        let run = makeDetachedRun()

        let rec = DailyCoachRecommendationService.generate(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(rec.readinessTier == .low)
        let primaryType = rec.primarySuggestion.type
        #expect(
            primaryType == .trimOneBackoffSet || primaryType == .reduceWorkingLoadsSlightly,
            "Low readiness should produce a conservative modification, got \(primaryType)"
        )
    }

    @Test func recommendationLowAvailableTimeProducesTrimAccessories() {
        let checkIn = DailyCoachCheckIn(
            date: Date(), sleepQuality: 3, soreness: 2, energy: 3, stress: 2,
            availableTimeMinutes: 20
        )
        let run = makeDetachedRun()

        let rec = DailyCoachRecommendationService.generate(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(rec.primarySuggestion.type == .trimAccessories)
        #expect(rec.compactSummary.contains("20 min"))
    }

    @Test func recommendationPainFlagProducesSuggestManualVariationSwap() {
        let checkIn = DailyCoachCheckIn(
            date: Date(), sleepQuality: 3, soreness: 2, energy: 3, stress: 2,
            hasPainOrDiscomfort: true, painNotes: "Left knee ache"
        )
        let run = makeDetachedRun()

        let rec = DailyCoachRecommendationService.generate(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(rec.primarySuggestion.type == .suggestManualVariationSwap)
        #expect(rec.hasPainFlag == true)
    }

    @Test func recommendationNoActiveProgramProducesStandaloneSessionType() {
        let checkIn = DailyCoachCheckIn(date: Date(), sleepQuality: 3, soreness: 2, energy: 3, stress: 2)

        let rec = DailyCoachRecommendationService.generate(
            checkIn: checkIn,
            activeRun: nil,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: nil
        )

        #expect(rec.nextProgramSession == nil)
        #expect(rec.standaloneSessionType != nil)
        let primaryType = rec.primarySuggestion.type
        #expect(
            primaryType == .standaloneShortStrengthSession || primaryType == .standaloneRecoverySession,
            "Standalone path should produce a standalone suggestion type, got \(primaryType)"
        )
    }

    // MARK: - Readiness Tier Computation

    @Test func readinessTierStrongForHighScores() {
        // Composite = (5 + 5 + (6-1) + (6-1)) / 4 = 5.0 → .strong
        let checkIn = DailyCoachCheckIn(date: Date(), sleepQuality: 5, soreness: 1, energy: 5, stress: 1)
        let tier = DailyCoachRecommendationService.computeReadinessTier(from: checkIn)
        #expect(tier == .strong)
    }

    @Test func readinessTierUnknownWhenNoCheckIn() {
        let tier = DailyCoachRecommendationService.computeReadinessTier(from: nil)
        #expect(tier == .unknown)
    }

    // MARK: - Prepared Draft — Draft-Only Enforcement

    @Test func preparedDraftAdjustmentIsDraftOnlyAndDoesNotPersistExercises() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let exercise = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 4,
            targetReps: 5,
            prescribedWeight: 315,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )
        let accessory = ProgramSessionExercise(
            exerciseName: "Leg Press",
            orderIndex: 1,
            targetSets: 3,
            targetReps: 10,
            workingSetStyle: .straight,
            baseLiftUsed: "Leg Press"
        )

        let draft = DailyCoachWorkoutPreparationService.prepare(
            exercises: [exercise, accessory],
            suggestionType: .trimAccessories
        )

        #expect(draft.adjustmentType == .trimAccessories)

        // No ProgramSessionExercise objects should have been written to SwiftData
        let persisted = try fetchAll(ProgramSessionExercise.self, context)
        #expect(persisted.isEmpty, "Preparation service must not write exercises to the store")

        // Base exercises are not mutated by the preparation service
        #expect(exercise.exerciseName == "Back Squats")
        #expect(exercise.targetSets == 4)
        #expect(accessory.exerciseName == "Leg Press")
    }

    // MARK: - Effort Feedback Persistence

    @Test func effortFeedbackPersistsOnExerciseEntry() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let workout = Workout(date: day(0), startTime: day(0), durationSeconds: 3600)
        context.insert(workout)

        let entry = ExerciseEntry(exerciseName: "Back Squats", unit: .lbs, orderIndex: 0)
        entry.workout = workout
        entry.effortFeedback = .onTarget
        entry.topSetRPE = 8.0
        workout.exerciseEntries.append(entry)
        context.insert(entry)
        try context.save()

        let fetched = try fetchAll(ExerciseEntry.self, context)
        #expect(fetched.count == 1)
        #expect(fetched[0].effortFeedback == .onTarget)
        #expect(fetched[0].topSetRPE == 8.0)
    }

    @Test func effortFeedbackAllVariantsPersist() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let workout = Workout(date: day(0), startTime: day(0), durationSeconds: 3600)
        context.insert(workout)

        let variants: [WorkoutEffortFeedback] = [.tooEasy, .onTarget, .tooHard]
        for (index, feedback) in variants.enumerated() {
            let entry = ExerciseEntry(exerciseName: "Exercise \(index)", unit: .lbs, orderIndex: index)
            entry.workout = workout
            entry.effortFeedback = feedback
            workout.exerciseEntries.append(entry)
            context.insert(entry)
        }
        try context.save()

        let fetched = try fetchAll(ExerciseEntry.self, context).sorted { $0.orderIndex < $1.orderIndex }
        #expect(fetched[0].effortFeedback == .tooEasy)
        #expect(fetched[1].effortFeedback == .onTarget)
        #expect(fetched[2].effortFeedback == .tooHard)
    }

    // MARK: - Weekly Review Upsert

    @Test func weeklyReviewUpsertCreatesOneReviewPerAnalysis() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let analysis = makeStandaloneAnalysis(context: context, weekOffset: 0, workoutCount: 3)
        try context.save()

        // First call creates
        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis, context: context)
        try context.save()

        var reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
        #expect(reviews.count == 1)
        let firstHeadline = reviews[0].headline

        // Second call on same analysis upserts, does not duplicate
        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis, context: context)
        try context.save()

        reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
        #expect(reviews.count == 1, "Upsert must not create a duplicate review for the same analysis")
        #expect(reviews[0].sourceWeeklyAnalysisIDText == analysis.id.uuidString)
        #expect(reviews[0].headline == firstHeadline, "Deterministic text must be stable across identical re-runs")
    }

    @Test func weeklyReviewUpsertPreservesHasBeenSeenFlag() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let analysis = makeStandaloneAnalysis(context: context, weekOffset: 0, workoutCount: 2)
        try context.save()

        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis, context: context)
        try context.save()

        // Simulate user viewing the review
        let review = try fetchAll(DailyCoachWeeklyReview.self, context).first!
        review.hasBeenSeen = true
        try context.save()

        // Re-generate (analysis re-run scenario)
        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis, context: context)
        try context.save()

        let updated = try fetchAll(DailyCoachWeeklyReview.self, context)
        #expect(updated.count == 1)
        #expect(updated[0].hasBeenSeen == true, "Re-generating a review must not reset hasBeenSeen")
    }

    @Test func weeklyReviewProgramWeekContainsExpectedFields() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeProgramFixture()
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: day(0),
            weekEndDate: day(6),
            programRun: run,
            trainingProgram: fixture.program,
            programWeekNumber: 1,
            programWorkoutCount: 1,
            totalOutcomeCount: 1,
            totalSignalWeight: 1.0,
            programSignalWeight: 1.0,
            fatigueStatus: .manageable,
            isFinalized: true,
            finalizedAt: day(7)
        )
        context.insert(analysis)
        try context.save()

        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis, context: context)
        try context.save()

        let reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
        #expect(reviews.count == 1)
        let r = reviews[0]
        #expect(r.isProgramWeek == true)
        #expect(!r.headline.isEmpty)
        #expect(!r.winText.isEmpty)
        #expect(!r.watchoutText.isEmpty)
        #expect(!r.nextActionText.isEmpty)
        #expect(r.sourceWeeklyAnalysisIDText == analysis.id.uuidString)
    }

    @Test func weeklyReviewStandaloneWeekContainsExpectedFields() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let analysis = makeStandaloneAnalysis(context: context, weekOffset: -7, workoutCount: 3)
        try context.save()

        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis, context: context)
        try context.save()

        let reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
        #expect(reviews.count == 1)
        let r = reviews[0]
        #expect(r.isProgramWeek == false)
        #expect(!r.headline.isEmpty)
        #expect(!r.winText.isEmpty)
        #expect(!r.watchoutText.isEmpty)
        #expect(!r.nextActionText.isEmpty)
        #expect(r.programRun == nil)
    }

    @Test func weeklyReviewTwoDistinctAnalysesProduceTwoReviews() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let analysis1 = makeStandaloneAnalysis(context: context, weekOffset: -14, workoutCount: 2)
        let analysis2 = makeStandaloneAnalysis(context: context, weekOffset: -7,  workoutCount: 3)
        try context.save()

        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis1, context: context)
        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis2, context: context)
        try context.save()

        let reviews = try fetchAll(DailyCoachWeeklyReview.self, context)
        #expect(reviews.count == 2, "Each distinct analysis must produce its own review")
        let keys = Set(reviews.compactMap(\.sourceWeeklyAnalysisIDText))
        #expect(keys.contains(analysis1.id.uuidString))
        #expect(keys.contains(analysis2.id.uuidString))
    }

    // MARK: - Workout Save Regression Guard

    @Test func workoutSaveSucceedsWhenDailyCoachDataExists() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        // Pre-populate Daily Coach data
        context.insert(DailyCoachCheckIn(date: day(0), sleepQuality: 3, soreness: 2, energy: 3, stress: 2))
        context.insert(DailyCoachWeeklyReview(
            weekStart: day(-7),
            weekEnd: day(-1),
            isProgramWeek: false,
            headline: "Previous week review",
            winText: "Trained consistently.",
            watchoutText: "Fatigue is manageable.",
            nextActionText: "Keep going."
        ))
        try context.save()

        // Save a new workout — must succeed regardless of Daily Coach data
        let workout = Workout(date: day(0), startTime: day(0), durationSeconds: 3600)
        context.insert(workout)

        let entry = ExerciseEntry(exerciseName: "Back Squats", unit: .lbs, orderIndex: 0)
        entry.workout = workout
        entry.effortFeedback = .onTarget
        workout.exerciseEntries.append(entry)
        context.insert(entry)

        let setEntry = SetEntry(setNumber: 1, reps: 5, weight: 315)
        setEntry.exerciseEntry = entry
        entry.sets.append(setEntry)
        context.insert(setEntry)

        #expect(throws: Never.self) { try context.save() }

        let workouts = try fetchAll(Workout.self, context)
        let entries  = try fetchAll(ExerciseEntry.self, context)
        let sets     = try fetchAll(SetEntry.self, context)

        #expect(workouts.count == 1)
        #expect(entries.count == 1)
        #expect(sets.count == 1)
        #expect(entries[0].effortFeedback == .onTarget)

        // Daily Coach data untouched
        #expect((try fetchAll(DailyCoachCheckIn.self, context)).count == 1)
        #expect((try fetchAll(DailyCoachWeeklyReview.self, context)).count == 1)
    }

    @Test func workoutSaveWithAnalysisPipelineAndDailyCoachRemainsClean() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let fixture = makeProgramFixture()
        persistProgram(fixture.program, context: context)

        let run = ProgramRun(startDate: day(0))
        run.program = fixture.program
        context.insert(run)

        context.insert(DailyCoachCheckIn(date: day(1), sleepQuality: 4, soreness: 1, energy: 4, stress: 1))

        let workout = Workout(
            date: day(1), startTime: day(1), durationSeconds: 3600,
            programRun: run, programWeekNumber: 1, programSessionNumber: 1
        )
        context.insert(workout)

        let entry = ExerciseEntry(
            exerciseName: "Back Squats",
            unit: .lbs,
            orderIndex: 0,
            sourceProgramSessionExerciseID: fixture.week1Main.id,
            prescribedTargetSets: 3,
            prescribedTargetReps: 5,
            prescribedWeight: 315,
            prescribedWeightUnit: "lbs",
            prescribedWorkingSetStyle: .topSet
        )
        entry.workout = workout
        entry.effortFeedback = .tooHard
        workout.exerciseEntries.append(entry)
        context.insert(entry)

        let set1 = SetEntry(setNumber: 1, reps: 5, weight: 315)
        set1.exerciseEntry = entry
        entry.sets.append(set1)
        context.insert(set1)

        // Run the analysis pipeline (mirrors what WorkoutView does on save)
        SessionOutcomeInferenceService.persistOutcomes(for: workout, context: context)
        WeeklyTrainingAnalysisService.analyzeCompletedWeeks(triggeredBy: workout, context: context)

        #expect(throws: Never.self) { try context.save() }

        let workouts = try fetchAll(Workout.self, context)
        #expect(workouts.count == 1)
        #expect(workouts[0].programRun?.id == run.id)

        let savedEntries = try fetchAll(ExerciseEntry.self, context)
        #expect(savedEntries[0].effortFeedback == .tooHard)
    }

    // MARK: - Helpers

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
            AppliedOverlayAdjustment.self,
            AdaptationEventHistory.self,
            DailyCoachCheckIn.self,
            DailyCoachWeeklyReview.self,
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

    private func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    /// Builds a detached ProgramRun + program without inserting into any context.
    private func makeDetachedRun() -> ProgramRun {
        let exercise = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            prescribedWeight: 315,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )
        let session = ProgramSessionTemplate(sessionNumber: 1)
        session.exercises = [exercise]
        let week = ProgramWeekTemplate(weekNumber: 1)
        week.sessions = [session]
        let program = TrainingProgram(name: "Test", lengthInWeeks: 4, sessionsPerWeek: 1, source: .aiGenerated)
        program.weeks = [week]
        let run = ProgramRun(startDate: day(-7))
        run.program = program
        return run
    }

    private func makeProgramFixture() -> ProgramFixture {
        let week1Main = ProgramSessionExercise(
            exerciseName: "Back Squats",
            orderIndex: 0,
            targetSets: 3,
            targetReps: 5,
            prescribedWeight: 315,
            prescribedWeightUnit: "lbs",
            workingSetStyle: .topSet,
            baseLiftUsed: "Back Squats"
        )
        let session = ProgramSessionTemplate(sessionNumber: 1)
        session.exercises = [week1Main]
        let week = ProgramWeekTemplate(weekNumber: 1)
        week.sessions = [session]
        let program = TrainingProgram(name: "Test Program", lengthInWeeks: 2, sessionsPerWeek: 1, source: .aiGenerated)
        program.weeks = [week]
        return ProgramFixture(program: program, week1Main: week1Main)
    }

    private func persistProgram(_ program: TrainingProgram, context: ModelContext) {
        for week in program.weeks {
            week.program = program
            for session in week.sessions {
                session.week = week
                for exercise in session.exercises { exercise.session = session }
            }
        }
        context.insert(program)
    }

    private func makeStandaloneAnalysis(
        context: ModelContext,
        weekOffset: Int,
        workoutCount: Int
    ) -> WeeklyTrainingAnalysis {
        let analysis = WeeklyTrainingAnalysis(
            weekStartDate: day(weekOffset),
            weekEndDate: day(weekOffset + 6),
            programRun: nil,
            trainingProgram: nil,
            programWeekNumber: nil,
            standaloneWorkoutCount: workoutCount,
            totalOutcomeCount: 0,
            fatigueStatus: .manageable,
            isFinalized: true,
            finalizedAt: day(weekOffset + 7)
        )
        context.insert(analysis)
        return analysis
    }
}

// MARK: - Supporting Types

private struct ProgramFixture {
    let program: TrainingProgram
    let week1Main: ProgramSessionExercise
}
