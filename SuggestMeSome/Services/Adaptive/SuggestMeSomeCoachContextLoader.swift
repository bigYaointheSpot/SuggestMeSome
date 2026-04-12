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
        let focusRun = activeRun ?? fetchActiveRun()
        let fatigueStatus = fetchLatestFatigueStatus(for: focusRun)
        let readinessTier = todayCheckIn.map { DailyCoachRecommendationService.computeReadinessTier(from: $0) }
        let hasPain = todayCheckIn?.hasPainOrDiscomfort ?? false

        let overlaySummaries = fetchActiveOverlaySummaries(for: focusRun)
        let proposals = fetchPendingProposals(for: focusRun)
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

    private func fetchActiveRun() -> ProgramRun? {
        ReadQueryRepository.activeProgramRuns(limit: 1, context: context).first
    }

    private func fetchLatestFatigueStatus(for run: ProgramRun?) -> FatigueStatus? {
        if let run {
            let runID = run.id
            let descriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
                predicate: #Predicate<WeeklyTrainingAnalysis> {
                    $0.programRun?.id == runID && $0.isFinalized
                },
                sortBy: [SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .reverse)]
            )
            var limited = descriptor
            limited.fetchLimit = 1
            let results = (try? context.fetch(limited)) ?? []
            return results.first?.fatigueStatus
        }

        let descriptor = FetchDescriptor<WeeklyTrainingAnalysis>(
            predicate: #Predicate<WeeklyTrainingAnalysis> { $0.isFinalized },
            sortBy: [SortDescriptor(\WeeklyTrainingAnalysis.weekStartDate, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 10
        let results = (try? context.fetch(limited)) ?? []
        return results.first(where: { $0.programRun == nil })?.fatigueStatus
    }

    private func fetchActiveOverlaySummaries(for run: ProgramRun?) -> [String] {
        guard let run else { return [] }
        return ReadQueryRepository.activeOverlays(for: run, context: context)
            .compactMap(\.summaryText)
            .filter { !$0.isEmpty }
    }

    private func fetchPendingProposals(for run: ProgramRun?) -> [SuggestMeSomeCoachContextProposal] {
        ReadQueryRepository.pendingCoachContextProposals(for: run, context: context, limit: 10).map { proposal in
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
