//
//  AdaptationProposalPresentationService.swift
//  SuggestMeSome
//
//  Shared proposal display mapping used by review surfaces.
//

import Foundation

struct AdaptationProposalDisplaySummary {
    let title: String
    let affectedWindowText: String
    let changeSummary: String
    let reasonText: String
    let detailText: String?
}

enum AdaptationProposalPresentationService {
    static func makeDisplaySummary(
        for proposal: AdaptationProposal,
        program: TrainingProgram?
    ) -> AdaptationProposalDisplaySummary {
        AdaptationProposalDisplaySummary(
            title: title(for: proposal),
            affectedWindowText: affectedWindowText(for: proposal),
            changeSummary: changeSummary(for: proposal, program: program),
            reasonText: reasonText(for: proposal.adjustmentReason),
            detailText: proposal.detailText
        )
    }

    static func title(for proposal: AdaptationProposal) -> String {
        switch proposal.proposalType {
        case .increaseVolume: return "Volume Increase"
        case .decreaseVolume: return "Volume Decrease"
        case .deload: return "Deload Week"
        case .decreaseLoad: return "Downshift"
        default: return "Adaptive Proposal"
        }
    }

    static func affectedWindowText(for proposal: AdaptationProposal) -> String {
        let start = proposal.targetWeekStart
        let end = max(start, proposal.targetWeekEnd ?? start)
        if start == end {
            if let session = proposal.targetSessionNumber {
                return "Week \(start), S\(session)"
            }
            return "Week \(start)"
        }
        return "Weeks \(start)-\(end)"
    }

    static func changeSummary(for proposal: AdaptationProposal, program: TrainingProgram?) -> String {
        switch proposal.proposalType {
        case .increaseVolume, .decreaseVolume:
            let delta = proposal.proposedSetDelta ?? 0
            let deltaText = delta > 0 ? "+\(delta)" : "\(delta)"
            let exerciseName = targetExerciseName(for: proposal, in: program) ?? "target accessory work"
            return "Adjust sets by \(deltaText) for \(exerciseName)."

        case .deload:
            var parts: [String] = ["Apply a recovery-focused deload."]
            if let loadDelta = proposal.proposedLoadPercentDelta {
                parts.append("Load \(percentText(loadDelta)).")
            }
            if let setDelta = proposal.proposedSetDelta {
                let setText = setDelta > 0 ? "+\(setDelta)" : "\(setDelta)"
                parts.append("Sets \(setText).")
            }
            if let factor = proposal.proposedDeloadFactor {
                parts.append("Deload factor \(percentText(factor - 1)).")
            }
            return parts.joined(separator: " ")

        case .decreaseLoad:
            var parts: [String] = ["Apply a conservative downshift."]
            if let loadDelta = proposal.proposedLoadPercentDelta {
                parts.append("Load \(percentText(loadDelta)).")
            }
            if let setDelta = proposal.proposedSetDelta {
                let setText = setDelta > 0 ? "+\(setDelta)" : "\(setDelta)"
                parts.append("Sets \(setText).")
            }
            return parts.joined(separator: " ")

        default:
            return proposal.summaryText
        }
    }

    static func reasonText(for reason: AdjustmentReason) -> String {
        switch reason {
        case .topSetBeatTarget: return "Top-set performance exceeded target"
        case .topSetMissedTarget: return "Top-set performance missed target"
        case .accessoryOutperformance: return "Accessory performance is ahead"
        case .accessoryUnderperformance: return "Accessory performance is behind"
        case .fatigueAccumulation: return "Fatigue has accumulated across the week"
        case .fatigueResolved: return "Fatigue appears resolved"
        case .positiveLiftTrend: return "Lift-family trend is improving"
        case .negativeLiftTrend: return "Lift-family trend is declining"
        case .plateauDetected: return "Trend indicates a plateau"
        case .lowAdherence: return "Session adherence was low"
        case .standaloneTrendSupport: return "Standalone sessions support this trend"
        case .programSignalPriority: return "Program-linked signals had higher confidence"
        }
    }

    static func percentText(_ value: Double) -> String {
        let percent = value * 100
        if percent >= 0 {
            return String(format: "+%.0f%%", percent)
        }
        return String(format: "%.0f%%", percent)
    }

    private static func targetExerciseName(
        for proposal: AdaptationProposal,
        in program: TrainingProgram?
    ) -> String? {
        guard let targetID = proposal.targetProgramSessionExerciseID else { return nil }
        guard let program else { return nil }

        for week in program.weeks {
            for session in week.sessions {
                if let match = session.exercises.first(where: { $0.id == targetID }) {
                    return match.exerciseName
                }
            }
        }
        return nil
    }
}
