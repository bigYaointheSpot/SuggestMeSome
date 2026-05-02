//
//  DailyCoachDerivedState.swift
//  SuggestMeSome
//
//  Pure value types that derive Daily Coach today-plan state from queries.
//  Extracted from DailyCoachView in Feature 22 Prompt 1.
//

import Foundation
import SwiftData

struct DailyCoachCompletedBlockInsights {
    let latestCompletedRun: ProgramRun?
    let latestCompletedReviewSnapshot: MesocycleReviewSnapshot?
    let longHorizonSummary: LongHorizonAdaptationSummary?

    static let placeholder = DailyCoachCompletedBlockInsights(
        latestCompletedRun: nil,
        latestCompletedReviewSnapshot: nil,
        longHorizonSummary: nil
    )

    /// Full fingerprint over the completed-block inputs. Correctness-first:
    /// touching any workout, completed run, or PR row updates the token.
    static func refreshToken(
        recentWorkouts: [Workout],
        completedRuns: [ProgramRun],
        personalRecords: [PersonalRecord]
    ) -> Int {
        var hasher = Hasher()
        ViewRefreshFingerprinting.combineSyncBacked(
            completedRuns,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            recentWorkouts,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            personalRecords,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        return hasher.finalize()
    }
}

struct DailyCoachDerivedState {
    let focusRun: ProgramRun?
    let pendingProposals: [AdaptationProposal]
    let latestAnalysis: WeeklyTrainingAnalysis?
    let latestReview: DailyCoachWeeklyReview?
    let objectiveRecoveryEvaluation: ObjectiveRecoveryEvaluation
    let todayCheckIn: DailyCoachCheckIn?
    let todayPlan: TodayPlan
    let relevantProposalForTodayPlan: AdaptationProposal?
    let overlaysAffectTodaySession: Bool
    let latestCompletedRun: ProgramRun?
    let latestCompletedReviewSnapshot: MesocycleReviewSnapshot?
    let longHorizonSummary: LongHorizonAdaptationSummary?

    var isBetweenBlocks: Bool {
        focusRun == nil && latestCompletedRun != nil
    }

    static let placeholder = build(
        activeRuns: [],
        recentWorkouts: [],
        weeklyAnalyses: [],
        allProposals: [],
        allOverlays: [],
        checkIns: [],
        weeklyReviews: [],
        healthKitDailySummaries: [],
        healthKitEnabled: false,
        useHealthKitInDailyCoach: false,
        recoveryLastSyncTimestamp: 0,
        completedBlockInsights: .placeholder,
        now: .distantPast
    )

    static func build(
        activeRuns: [ProgramRun],
        recentWorkouts: [Workout],
        weeklyAnalyses: [WeeklyTrainingAnalysis],
        allProposals: [AdaptationProposal],
        allOverlays: [AppliedProgramOverlay],
        checkIns: [DailyCoachCheckIn],
        weeklyReviews: [DailyCoachWeeklyReview],
        healthKitDailySummaries: [HealthKitDailySummary],
        healthKitEnabled: Bool,
        useHealthKitInDailyCoach: Bool,
        recoveryLastSyncTimestamp: Double,
        completedBlockInsights: DailyCoachCompletedBlockInsights = .placeholder,
        now: Date = .now
    ) -> DailyCoachDerivedState {
        let focusRun = TrainingContextQueryService.activeProgramRuns(from: activeRuns).first
        let pendingProposals = TrainingContextQueryService.pendingUserProposals(
            for: focusRun,
            proposals: allProposals
        )
        .filter { AdaptationProposalConfirmationService.isPendingUserProposal($0) }
        let latestAnalysis = TrainingContextQueryService.latestWeeklyAnalysis(
            for: focusRun,
            in: weeklyAnalyses
        )
        let latestReview = weeklyReviews.first
        let objectiveRecoveryEvaluation = HealthKitRecoveryInsightService.evaluate(
            from: Array(healthKitDailySummaries.prefix(90)),
            healthKitEnabled: healthKitEnabled,
            useHealthKitInDailyCoach: useHealthKitInDailyCoach,
            hasSuccessfulRecoverySync: recoveryLastSyncTimestamp > 0
        )
        let today = Calendar.current.startOfDay(for: now)
        let todayCheckIn = checkIns.first { Calendar.current.startOfDay(for: $0.date) == today }
        let activeOverlaysForRun = focusRun.map { run in
            allOverlays.filter { $0.programRun?.id == run.id && $0.overlayStatus == .active }
        } ?? []
        let completedWorkoutCountForRun = focusRun.map { run in
            TrainingContextQueryService.runScopedWorkouts(for: run, in: recentWorkouts).count
        } ?? 0
        let completedSessionKeysForRun = focusRun.map { run in
            Set(recentWorkouts.compactMap { workout -> ProgramSessionCompletionKey? in
                guard workout.programRun?.id == run.id,
                      let weekNumber = workout.programWeekNumber,
                      let sessionNumber = workout.programSessionNumber else {
                    return nil
                }
                return ProgramSessionCompletionKey(
                    weekNumber: weekNumber,
                    sessionNumber: sessionNumber
                )
            })
        }
        let todayPlan = TodayPlanEngine.buildPlan(
            checkIn: todayCheckIn,
            activeRun: focusRun,
            latestAnalysis: latestAnalysis,
            pendingProposalCount: pendingProposals.count,
            pendingProposals: pendingProposals,
            activeOverlays: activeOverlaysForRun,
            recentWorkouts: TrainingContextQueryService.recentWorkouts(from: recentWorkouts, limit: 20),
            objectiveRecoveryEvaluation: objectiveRecoveryEvaluation,
            completedSessions: completedSessionKeysForRun,
            completedWorkoutCountForRun: completedWorkoutCountForRun
        )
        let relevantProposalForTodayPlan = TodayPlanActionCoordinator.relevantProposalForTodayPlan(
            pendingProposals: pendingProposals,
            plan: todayPlan
        )
        let overlaysAffectTodaySession: Bool = {
            guard let session = todayPlan.recommendation.nextProgramSession else { return false }
            let context = TodayPlanExplanationAssembler.overlayContext(
                activeRun: focusRun,
                activeOverlays: activeOverlaysForRun,
                nextSession: session
            )
            return context.overlaysAffectingTodayCount > 0
        }()
        return DailyCoachDerivedState(
            focusRun: focusRun,
            pendingProposals: pendingProposals,
            latestAnalysis: latestAnalysis,
            latestReview: latestReview,
            objectiveRecoveryEvaluation: objectiveRecoveryEvaluation,
            todayCheckIn: todayCheckIn,
            todayPlan: todayPlan,
            relevantProposalForTodayPlan: relevantProposalForTodayPlan,
            overlaysAffectTodaySession: overlaysAffectTodaySession,
            latestCompletedRun: completedBlockInsights.latestCompletedRun,
            latestCompletedReviewSnapshot: completedBlockInsights.latestCompletedReviewSnapshot,
            longHorizonSummary: completedBlockInsights.longHorizonSummary
        )
    }

    /// Correctness-first fingerprint across every query the derived state reads.
    /// We still mix in the scalar config flags and local day-start so the token
    /// turns over when settings or the calendar day changes.
    static func refreshToken(
        activeRuns: [ProgramRun],
        recentWorkouts: [Workout],
        weeklyAnalyses: [WeeklyTrainingAnalysis],
        allProposals: [AdaptationProposal],
        allOverlays: [AppliedProgramOverlay],
        checkIns: [DailyCoachCheckIn],
        weeklyReviews: [DailyCoachWeeklyReview],
        healthKitDailySummaries: [HealthKitDailySummary],
        healthKitEnabled: Bool,
        useHealthKitInDailyCoach: Bool,
        recoveryLastSyncTimestamp: Double,
        now: Date = .now
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(Calendar.current.startOfDay(for: now))
        hasher.combine(healthKitEnabled)
        hasher.combine(useHealthKitInDailyCoach)
        hasher.combine(recoveryLastSyncTimestamp)
        ViewRefreshFingerprinting.combineSyncBacked(
            activeRuns,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            recentWorkouts,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            weeklyAnalyses,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            allProposals,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            allOverlays,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            checkIns,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            weeklyReviews,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        ViewRefreshFingerprinting.combineSyncBacked(
            healthKitDailySummaries,
            into: &hasher,
            stableID: { $0.syncStableID },
            id: { $0.id },
            version: { $0.syncVersion },
            modifiedAt: { $0.syncLastModifiedAt }
        )
        return hasher.finalize()
    }

    func replacingCompletedBlockInsights(
        _ insights: DailyCoachCompletedBlockInsights
    ) -> DailyCoachDerivedState {
        DailyCoachDerivedState(
            focusRun: focusRun,
            pendingProposals: pendingProposals,
            latestAnalysis: latestAnalysis,
            latestReview: latestReview,
            objectiveRecoveryEvaluation: objectiveRecoveryEvaluation,
            todayCheckIn: todayCheckIn,
            todayPlan: todayPlan,
            relevantProposalForTodayPlan: relevantProposalForTodayPlan,
            overlaysAffectTodaySession: overlaysAffectTodaySession,
            latestCompletedRun: insights.latestCompletedRun,
            latestCompletedReviewSnapshot: insights.latestCompletedReviewSnapshot,
            longHorizonSummary: insights.longHorizonSummary
        )
    }
}
