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
        objectiveRecoveryInsight: ObjectiveRecoveryInsight? = nil
    ) -> SuggestMeSomeCoachContext {
        let fatigueStatus = fetchLatestFatigueStatus()
        let readinessTier = todayCheckIn.map { DailyCoachRecommendationService.computeReadinessTier(from: $0) }
        let hasPain = todayCheckIn?.hasPainOrDiscomfort ?? false

        let overlaySummaries = fetchActiveOverlaySummaries()
        let proposals = fetchPendingProposals()
        let preferences = learnPreferences()

        return SuggestMeSomeCoachContext(
            fatigueStatus: fatigueStatus,
            readinessTier: readinessTier,
            hasPainOrDiscomfort: hasPain,
            activeOverlaySummaries: overlaySummaries,
            pendingProposals: proposals,
            objectiveRecoveryInsight: objectiveRecoveryInsight,
            exercisePreferences: preferences
        )
    }

    // MARK: - Private fetches

    private func fetchLatestFatigueStatus() -> FatigueStatus? {
        let descriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
            predicate: #Predicate<WeeklyTrainingAnalysis> { $0.isFinalized },
            sortBy: [SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 1
        let results = (try? context.fetch(limited)) ?? []
        return results.first?.fatigueStatus
    }

    private func fetchActiveOverlaySummaries() -> [String] {
        // Fetch all and filter in-memory to avoid SwiftData predicate limitations with enums.
        let descriptor = FetchDescriptor<AppliedProgramOverlay>(
            sortBy: [SortDescriptor(\AppliedProgramOverlay.appliedAt, order: .reverse)]
        )
        let overlays = (try? context.fetch(descriptor)) ?? []
        return overlays
            .filter { $0.overlayStatus == .active }
            .compactMap(\.summaryText)
            .filter { !$0.isEmpty }
    }

    private func fetchPendingProposals() -> [SuggestMeSomeCoachContextProposal] {
        // Fetch all and filter in-memory to avoid SwiftData predicate limitations with enums.
        let descriptor = FetchDescriptor<AdaptationProposal>(
            sortBy: [SortDescriptor(\AdaptationProposal.priority, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 50   // fetch more than needed; filter down below
        let all = (try? context.fetch(limited)) ?? []

        let pending = all.filter {
            $0.proposalStatus == .pendingUserConfirmation || $0.proposalStatus == .pendingAutoApply
        }.prefix(10)

        return pending.map { proposal in
            SuggestMeSomeCoachContextProposal(
                proposalType: proposal.proposalType,
                targetLiftKey: proposal.targetLiftKey,
                summaryText: proposal.summaryText
            )
        }
    }

    private func learnPreferences() -> SuggestMeSomeExercisePreferences? {
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\Workout.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        let workouts = (try? context.fetch(descriptor)) ?? []
        guard !workouts.isEmpty else { return nil }
        return preferenceLearner.learnPreferences(from: workouts)
    }
}
