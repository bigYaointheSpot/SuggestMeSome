import Foundation

struct ProgramGenerationExplainabilityStamper {
    private let cardioPlanner = ProgramGenerationCardioPlanner()

    func resolveSessionReasonCode(
        focusProfile: ProgramFocusProgrammingProfile,
        strategy: ProgramGenerationProgressionStrategy,
        schedule: ProgramGenerationWeekSchedule,
        sessionName: String
    ) -> ProgramSessionReasonCode {
        if schedule.isDeload { return .deloadRecovery }

        let lower = sessionName.lowercased()
        if strategy.family == .enduranceConditioning {
            if lower.contains("recovery") { return .enduranceRecovery }
            if lower.contains("long") { return .enduranceLong }
            if lower.contains("interval") || lower.contains("vo2") || lower.contains("threshold") || lower.contains("tempo") {
                return .enduranceQuality
            }
            return .enduranceBase
        }

        switch focusProfile.primaryAdaptationGoal {
        case .maximalStrength: return .specificityExposure
        case .strengthHypertrophy: return .specificityExposure
        case .hypertrophy: return .hypertrophyVolume
        case .balancedFitness: return .balancedCoverage
        case .aerobicEndurance: return .enduranceBase
        }
    }

    func resolveExercisePurposeCode(
        templateExercise: TemplateExercise,
        isPrimary: Bool,
        schedule: ProgramGenerationWeekSchedule,
        sessionName: String
    ) -> ProgramExercisePurposeCode {
        if templateExercise.role == .cardio {
            let type = cardioPlanner.resolveCardioSessionType(sessionName: sessionName)
            switch type {
            case .recovery: return .recovery
            case .interval, .threshold: return .conditioningQuality
            case .easyAerobic, .longSession: return .conditioningBase
            }
        }

        if schedule.isDeload { return .fatigueControl }
        if templateExercise.role == .variation { return .technique }
        if isPrimary { return .specificity }
        return .volumeFill
    }
}
