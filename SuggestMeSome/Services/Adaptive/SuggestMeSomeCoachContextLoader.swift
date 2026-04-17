import Foundation
import SwiftData

/// Builds a `SuggestMeSomeCoachContext` by reading relevant SwiftData models.
///
/// This service is read-only and non-destructive. It produces a value-type snapshot
/// of the coaching state at the moment of the call. All fields degrade gracefully to
/// nil/empty when data is absent.
struct SuggestMeSomeCoachContextLoader {

    private let context: ModelContext
    private let preferenceLearner: SuggestMeSomePreferenceLearnerService

    init(context: ModelContext, preferenceLearner: SuggestMeSomePreferenceLearnerService = SuggestMeSomePreferenceLearnerService()) {
        self.context = context
        self.preferenceLearner = preferenceLearner
    }

    // MARK: - Public API

    func loadContext(
        todayCheckIn: DailyCoachCheckIn?,
        objectiveRecoveryInsight: ObjectiveRecoveryInsight? = nil,
        activeRun: ProgramRun? = nil
    ) -> SuggestMeSomeCoachContext {
        let snapshot = TrainingReadRepository.coachContextSnapshot(
            focusRun: activeRun,
            context: context
        )
        let readinessTier = todayCheckIn.map { DailyCoachRecommendationService.computeReadinessTier(from: $0) }
        let hasPain = todayCheckIn?.hasPainOrDiscomfort ?? false

        let preferences = learnPreferences(from: snapshot.recentWorkouts)

        return SuggestMeSomeCoachContext(
            fatigueStatus: snapshot.latestFatigueStatus,
            readinessTier: readinessTier,
            hasPainOrDiscomfort: hasPain,
            activeOverlaySummaries: snapshot.activeOverlaySummaries,
            pendingProposals: snapshot.pendingProposals.map { proposal in
                SuggestMeSomeCoachContextProposal(
                    proposalType: proposal.proposalType,
                    targetLiftKey: proposal.targetLiftKey,
                    summaryText: proposal.summaryText
                )
            },
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            exercisePreferences: preferences
        )
    }

    private func learnPreferences(from workouts: [Workout]) -> SuggestMeSomeExercisePreferences? {
        guard !workouts.isEmpty else { return nil }
        return preferenceLearner.learnPreferences(from: workouts)
    }
}
