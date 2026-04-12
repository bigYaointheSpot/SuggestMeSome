import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature10Prompt2RepositoryQueryHardeningTests {

    @Test func recentWorkoutQueryRespectsLimitAndSortOrder() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        for dayOffset in 0..<20 {
            let date = day(dayOffset)
            let workout = Workout(
                date: date,
                startTime: date,
                durationSeconds: 1200
            )
            context.insert(workout)
        }
        try context.save()

        let recent = ReadQueryRepository.recentWorkouts(limit: 5, context: context)

        #expect(recent.count == 5)
        #expect(recent[0].date > recent[4].date)
        #expect(recent.map(\.date) == recent.map(\.date).sorted(by: >))
    }

    @Test func pendingProposalQueriesStayRunScopedAndPendingOnly() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let runA = ProgramRun(startDate: day(0))
        let runB = ProgramRun(startDate: day(1))

        let pendingA = AdaptationProposal(
            programRun: runA,
            proposalType: .deload,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            confidenceScore: 0.8,
            priority: 90,
            targetWeekStart: 2,
            adjustmentReason: .fatigueAccumulation,
            summaryText: "Pending A"
        )

        let confirmedA = AdaptationProposal(
            programRun: runA,
            proposalType: .decreaseVolume,
            proposalStatus: .confirmed,
            requiresUserConfirmation: true,
            confidenceScore: 0.6,
            priority: 40,
            targetWeekStart: 3,
            adjustmentReason: .accessoryUnderperformance,
            summaryText: "Confirmed A"
        )

        let pendingB = AdaptationProposal(
            programRun: runB,
            proposalType: .decreaseLoad,
            proposalStatus: .pendingUserConfirmation,
            requiresUserConfirmation: true,
            confidenceScore: 0.7,
            priority: 80,
            targetWeekStart: 1,
            adjustmentReason: .fatigueAccumulation,
            summaryText: "Pending B"
        )

        context.insert(runA)
        context.insert(runB)
        context.insert(pendingA)
        context.insert(confirmedA)
        context.insert(pendingB)
        try context.save()

        let scoped = ReadQueryRepository.pendingUserProposals(for: runA, context: context)
        #expect(scoped.count == 1)
        #expect(scoped.first?.summaryText == "Pending A")

        let global = ReadQueryRepository.pendingUserProposals(context: context)
        #expect(global.count == 2)
        #expect(Set(global.map(\.summaryText)) == Set(["Pending A", "Pending B"]))
    }

    @Test func adaptationHistorySnapshotUsesRunScopedBoundedReads() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let runA = ProgramRun(startDate: day(0))
        let runB = ProgramRun(startDate: day(1))
        context.insert(runA)
        context.insert(runB)

        for index in 0..<5 {
            let analysis = WeeklyTrainingAnalysis(
                weekStartDate: day(index),
                weekEndDate: day(index),
                programRun: runA,
                programWeekNumber: index + 1,
                isFinalized: true
            )
            analysis.createdAt = day(index)
            context.insert(analysis)

            let trend = LiftTrendSnapshot(
                programRun: runA,
                canonicalLiftKey: CanonicalLift.bench.rawValue,
                liftDisplayName: CanonicalLift.bench.displayName,
                weekStartDate: day(index),
                weekEndDate: day(index)
            )
            trend.createdAt = day(index)
            context.insert(trend)

            let event = AdaptationEventHistory(
                timestamp: day(index),
                programRun: runA,
                eventType: .weeklyAnalysisFinalized,
                analysisWeekNumber: index + 1,
                message: "event-\(index)"
            )
            context.insert(event)
        }

        // Noise from another run should not be returned.
        context.insert(WeeklyTrainingAnalysis(weekStartDate: day(10), weekEndDate: day(10), programRun: runB))
        context.insert(AdaptationEventHistory(timestamp: day(10), programRun: runB, eventType: .weeklyAnalysisFinalized, message: "other-run"))
        try context.save()

        let snapshot = ReadQueryRepository.adaptationHistorySnapshot(
            for: runA,
            context: context,
            analysisLimit: 3,
            trendLimit: 2,
            proposalLimit: 4,
            overlayLimit: 4,
            eventLimit: 2
        )

        #expect(snapshot.analyses.count == 3)
        #expect(snapshot.trendSnapshots.count == 2)
        #expect(snapshot.events.count == 2)
        #expect(snapshot.analyses.allSatisfy { $0.programRun?.id == runA.id })
        #expect(snapshot.events.allSatisfy { $0.programRun?.id == runA.id })
    }

    @Test func appearancePreferenceResolverMapsStoredValue() {
        #expect(AppAppearancePreferenceService.preferredColorScheme(for: "light") == .light)
        #expect(AppAppearancePreferenceService.preferredColorScheme(for: "dark") == .dark)
        #expect(AppAppearancePreferenceService.preferredColorScheme(for: "system") == nil)
        #expect(AppAppearancePreferenceService.preferredColorScheme(for: "") == nil)
    }

    @Test func deferredNavigationLaunchesOnlyWhenPendingDestinationExists() async {
        var launched = false

        DeferredNavigationService.launchAfterSheetDismissIfNeeded(hasPendingDestination: false) {
            launched = true
        }
        await Task.yield()
        #expect(launched == false)

        DeferredNavigationService.launchAfterSheetDismissIfNeeded(hasPendingDestination: true) {
            launched = true
        }
        await Task.yield()
        await Task.yield()
        #expect(launched == true)
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
        Calendar.current.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_710_000_000)) ?? Date(timeIntervalSince1970: 1_710_000_000)
    }
}
