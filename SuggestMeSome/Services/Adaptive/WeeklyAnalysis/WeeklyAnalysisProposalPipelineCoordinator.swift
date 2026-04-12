import Foundation
import SwiftData

enum WeeklyAnalysisProposalPipelineCoordinator {
    static func finalizeProgramWeek(
        from analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) {
        AdaptiveLoadProgressionService.generateProposals(from: analysis, context: context)
        AdaptiveVolumeProgressionService.generateProposals(from: analysis, context: context)
        AdaptiveFatigueDeloadService.generateProposals(from: analysis, context: context)
        AdaptiveVariationSwapService.generateAndApply(from: analysis, context: context)
        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis, context: context)
    }

    static func finalizeStandaloneWeek(
        from analysis: WeeklyTrainingAnalysis,
        context: ModelContext
    ) {
        DailyCoachWeeklyReviewService.generateOrUpdate(from: analysis, context: context)
    }
}
