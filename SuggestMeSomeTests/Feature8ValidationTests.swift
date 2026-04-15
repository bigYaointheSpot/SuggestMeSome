//
//  Feature8ValidationTests.swift
//  SuggestMeSomeTests
//
//  Feature 8 — HealthKit + watch foundation validation and hardening coverage.
//

import Foundation
import HealthKit
import SwiftData
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature8ValidationTests {

    @Test func healthKitAuthorizationTreatsCompletedFlowAsConnectedEvenWhenOptionalWriteIsDenied() {
        let snapshot = HealthKitAuthorizationSnapshot(
            availability: .available,
            readStatuses: [.notDetermined],
            workoutWriteStatus: .sharingDenied,
            requestStatus: .unnecessary,
            hasRequestedAuthorization: true
        )

        #expect(snapshot.isConnected)
        #expect(snapshot.isWorkoutWriteDenied)
        #expect(!snapshot.isDenied)
        #expect(!snapshot.canPresentAuthorizationPrompt)
    }

    @Test func healthKitAuthorizationCanStillPromptBeforeSystemMarksRequestUnnecessary() {
        let snapshot = HealthKitAuthorizationSnapshot(
            availability: .available,
            readStatuses: [.notDetermined],
            workoutWriteStatus: .notDetermined,
            requestStatus: .shouldRequest,
            hasRequestedAuthorization: false
        )

        #expect(!snapshot.isConnected)
        #expect(!snapshot.isDenied)
        #expect(snapshot.canPresentAuthorizationPrompt)
    }

    @Test func healthKitDailySummaryUpsertUpdatesByDayWithoutDupes() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let calendar = utcCalendar()

        let service = HealthKitRecoverySyncService(calendar: calendar)

        let day1 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 18))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 9))!
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 6))!

        let first = try service.upsertDailySummaries(
            context: context,
            snapshots: [
                HealthKitDailySummarySnapshot(
                    dayStart: day1,
                    sleepDurationSeconds: 26_000,
                    timeInBedSeconds: 28_000,
                    restingHeartRateBPM: 56,
                    heartRateVariabilityMS: nil,
                    activeEnergyKilocalories: nil,
                    stepCount: nil,
                    bodyMassKilograms: nil
                ),
                HealthKitDailySummarySnapshot(
                    dayStart: day2,
                    sleepDurationSeconds: 24_000,
                    timeInBedSeconds: 27_000,
                    restingHeartRateBPM: 58,
                    heartRateVariabilityMS: nil,
                    activeEnergyKilocalories: nil,
                    stepCount: nil,
                    bodyMassKilograms: nil
                )
            ]
        )
        #expect(first.inserted == 2)
        #expect(first.updated == 0)

        let second = try service.upsertDailySummaries(
            context: context,
            snapshots: [
                HealthKitDailySummarySnapshot(
                    dayStart: day1,
                    sleepDurationSeconds: 27_500,
                    timeInBedSeconds: 29_000,
                    restingHeartRateBPM: 54,
                    heartRateVariabilityMS: nil,
                    activeEnergyKilocalories: nil,
                    stepCount: nil,
                    bodyMassKilograms: nil
                ),
                HealthKitDailySummarySnapshot(
                    dayStart: day3,
                    sleepDurationSeconds: 23_000,
                    timeInBedSeconds: 25_000,
                    restingHeartRateBPM: 59,
                    heartRateVariabilityMS: nil,
                    activeEnergyKilocalories: nil,
                    stepCount: nil,
                    bodyMassKilograms: nil
                )
            ]
        )
        #expect(second.inserted == 1)
        #expect(second.updated == 1)

        let rows = try fetchAll(HealthKitDailySummary.self, context)
        #expect(rows.count == 3)

        let normalizedDay1 = calendar.startOfDay(for: day1)
        let day1Rows = rows.filter { calendar.startOfDay(for: $0.dayStart) == normalizedDay1 }
        #expect(day1Rows.count == 1)
        #expect(day1Rows[0].sleepDurationSeconds == 27_500)
        #expect(day1Rows[0].restingHeartRateBPM == 54)
    }

    @Test func recommendationBlendFallsBackWhenNoObjectiveRecoveryInsight() {
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

        #expect(rec.recommendationSources.contains(.trainingHistory))
        #expect(rec.recommendationSources.contains(.manualCheckIn))
        #expect(rec.recommendationSources.contains(.healthData) == false)
        #expect(rec.sourceAttributionDetails.contains("Health data was unavailable or not enabled"))
    }

    @Test func recommendationBlendIncludesHealthDataWhenInsightExists() {
        let checkIn = DailyCoachCheckIn(date: Date(), sleepQuality: 5, soreness: 1, energy: 5, stress: 1)
        let run = makeDetachedRun()
        let objective = ObjectiveRecoveryInsight(
            status: .caution,
            compactSummary: "Caution signal",
            detailSummary: "Recovery is below baseline.",
            evaluatedMetricsCount: 3
        )

        let rec = DailyCoachRecommendationService.generate(
            checkIn: checkIn,
            activeRun: run,
            latestAnalysis: nil,
            pendingProposalCount: 0,
            recentWorkouts: [],
            objectiveRecoveryInsight: objective
        )

        #expect(rec.recommendationSources.contains(.healthData))
        #expect(rec.primarySuggestion.type == .trimOneBackoffSet)
    }

    @Test func importedWorkoutUpsertDedupesByExternalIdentifier() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let service = HealthKitWorkoutImportService()
        let first = try service.upsertImportedWorkouts(
            context: context,
            snapshots: [
                HealthKitImportedWorkoutSnapshot(
                    externalIdentifier: "hk-001",
                    startDate: day(0),
                    durationSeconds: 1800,
                    caloriesBurned: 250,
                    sourceDisplayName: "Apple Watch",
                    activityTypeIdentifier: "37",
                    activityTypeDisplayName: "Traditional Strength Training"
                )
            ],
            importedAt: day(1)
        )
        #expect(first.inserted == 1)
        #expect(first.updated == 0)

        let second = try service.upsertImportedWorkouts(
            context: context,
            snapshots: [
                HealthKitImportedWorkoutSnapshot(
                    externalIdentifier: "hk-001",
                    startDate: day(0),
                    durationSeconds: 1900,
                    caloriesBurned: 260,
                    sourceDisplayName: "Health",
                    activityTypeIdentifier: "13",
                    activityTypeDisplayName: "Running"
                )
            ],
            importedAt: day(2)
        )
        #expect(second.inserted == 0)
        #expect(second.updated == 1)

        let workouts = try fetchAll(Workout.self, context)
        #expect(workouts.count == 1)
        #expect(workouts[0].sourceType == .healthKitImported)
        #expect(workouts[0].sourceWorkoutTypeDisplayName == "Running")
    }

    @Test func importedWorkoutLimitedEditGuardIsEnforcedBySourceType() {
        let imported = Workout(
            date: day(0),
            startTime: day(0),
            durationSeconds: 1200,
            sourceType: .healthKitImported
        )
        let native = Workout(
            date: day(0),
            startTime: day(0),
            durationSeconds: 1200,
            sourceType: .loggedInApp
        )

        #expect(imported.allowsFullStructureEditing == false)
        #expect(native.allowsFullStructureEditing == true)
    }

    @Test func writebackGuardSkipsImportedWorkouts() {
        let service = HealthKitWorkoutWriteService()
        let imported = Workout(
            date: day(0),
            startTime: day(0),
            durationSeconds: 1800,
            sourceType: .healthKitImported
        )

        let shouldWriteImported = service.shouldAttemptWriteback(
            for: imported,
            healthKitEnabled: true,
            writebackEnabled: true
        )
        #expect(shouldWriteImported == false)
    }

    @Test func workoutSaveRemainsPersistedWhenWritebackFails() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let workout = Workout(
            date: day(0),
            startTime: day(0),
            durationSeconds: 1800,
            sourceType: .loggedInApp
        )
        context.insert(workout)
        try context.save()

        let coordinator = WorkoutSaveHealthKitWritebackCoordinator(
            writer: FailingWritebackWriter()
        )

        await coordinator.performNonFatalWritebackIfEligible(
            for: workout,
            healthKitEnabled: true,
            writebackEnabled: true
        ) {
            try context.save()
        }

        let workouts = try fetchAll(Workout.self, context)
        #expect(workouts.count == 1)
        #expect(workouts[0].healthKitExportedAt == nil)
        #expect(workouts[0].healthKitWritebackIdentifier == nil)
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
            HealthKitDailySummary.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func day(_ offset: Int) -> Date {
        let calendar = utcCalendar()
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 12, minute: 0, second: 0))!
        return calendar.date(byAdding: .day, value: offset, to: anchor) ?? anchor
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

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
}

@MainActor
private struct FailingWritebackWriter: HealthKitWorkoutWriting {
    func shouldAttemptWriteback(
        for workout: Workout,
        healthKitEnabled: Bool,
        writebackEnabled: Bool
    ) -> Bool {
        workout.sourceType == .loggedInApp && healthKitEnabled && writebackEnabled
    }

    func writeWorkoutSummary(_ workout: Workout) async throws -> HealthKitWorkoutWriteResult {
        _ = workout
        throw HealthKitWorkoutWriteError.healthDataUnavailable
    }
}
