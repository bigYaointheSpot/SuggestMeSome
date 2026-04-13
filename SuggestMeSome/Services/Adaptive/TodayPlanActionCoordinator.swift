//
//  TodayPlanActionCoordinator.swift
//  SuggestMeSome
//
//  Feature 11 Prompt 2 — Today Plan review/confirm/launch flow coordinator.
//

import Foundation
import SwiftData

enum TodayPlanProposalDecisionAction {
    case approve
    case reject
}

struct StagedTodayPlanProposalDecision {
    let proposalID: UUID
    let action: TodayPlanProposalDecisionAction
    let title: String
    let message: String
}

enum TodayPlanLaunchRequest {
    case startAsPlanned
    case startRuntimeAdjusted
    case startApprovedVersion
}

enum TodayPlanLaunchPath {
    case planned
    case runtimeAdjusted
    case approvedOverlayAdjusted
}

enum TodayPlanChangeSource {
    case plannedPrescription
    case pendingProposal
    case approvedOverlay
    case runtimeCoachOnly
}

struct TodayPlanLaunchResolution {
    let path: TodayPlanLaunchPath
    let source: TodayPlanChangeSource
    let usesPreparedDraft: Bool
}

enum TodayPlanActionCoordinator {
    static func relevantProposalForTodayPlan(
        pendingProposals: [AdaptationProposal],
        plan: TodayPlan
    ) -> AdaptationProposal? {
        guard !pendingProposals.isEmpty, !plan.proposalAwareness.isEmpty else { return nil }
        let awarenessByID = Dictionary(uniqueKeysWithValues: plan.proposalAwareness.map { ($0.proposalID, $0) })
        let ranked = pendingProposals
            .filter { AdaptationProposalConfirmationService.isPendingUserProposal($0) }
            .compactMap { proposal -> (AdaptationProposal, TodayPlanProposalAwarenessItem)? in
                guard let awareness = awarenessByID[proposal.id] else { return nil }
                return (proposal, awareness)
            }
            .sorted { lhs, rhs in
                let leftRank = impactRank(lhs.1.impact)
                let rightRank = impactRank(rhs.1.impact)
                if leftRank != rightRank { return leftRank < rightRank }
                if lhs.0.priority != rhs.0.priority { return lhs.0.priority > rhs.0.priority }
                return lhs.0.createdAt > rhs.0.createdAt
            }

        return ranked.first { entry in
            entry.1.impact == .affectsToday || entry.1.impact == .affectsUpcomingSession
        }?.0
    }

    static func stageDecision(
        action: TodayPlanProposalDecisionAction,
        proposal: AdaptationProposal
    ) -> StagedTodayPlanProposalDecision? {
        guard AdaptationProposalConfirmationService.isPendingUserProposal(proposal) else { return nil }
        let title: String
        let verb: String
        switch action {
        case .approve:
            title = "Approve Proposal?"
            verb = "approve"
        case .reject:
            title = "Reject Proposal?"
            verb = "reject"
        }
        let message = "This requires confirmation. If you \(verb), base program rows still remain unchanged."
        return StagedTodayPlanProposalDecision(
            proposalID: proposal.id,
            action: action,
            title: title,
            message: message
        )
    }

    @MainActor
    static func commitStagedDecision(
        _ staged: StagedTodayPlanProposalDecision,
        proposal: AdaptationProposal,
        context: ModelContext
    ) throws {
        guard staged.proposalID == proposal.id else { return }
        switch staged.action {
        case .approve:
            try AdaptationProposalConfirmationService.approve(proposal, context: context)
        case .reject:
            try AdaptationProposalConfirmationService.reject(proposal, context: context)
        }
    }

    static func resolveLaunch(
        request: TodayPlanLaunchRequest,
        recommendation: DailyCoachRecommendation,
        hasOverlayAffectingToday: Bool,
        hasApprovedProposalAppliedForToday: Bool = false
    ) -> TodayPlanLaunchResolution {
        switch request {
        case .startAsPlanned:
            return TodayPlanLaunchResolution(
                path: .planned,
                source: .plannedPrescription,
                usesPreparedDraft: false
            )

        case .startRuntimeAdjusted:
            if recommendation.primarySuggestion.type == .runAsPlanned {
                return resolveLaunch(
                    request: .startAsPlanned,
                    recommendation: recommendation,
                    hasOverlayAffectingToday: hasOverlayAffectingToday,
                    hasApprovedProposalAppliedForToday: hasApprovedProposalAppliedForToday
                )
            }
            return TodayPlanLaunchResolution(
                path: .runtimeAdjusted,
                source: .runtimeCoachOnly,
                usesPreparedDraft: true
            )

        case .startApprovedVersion:
            if hasOverlayAffectingToday || hasApprovedProposalAppliedForToday {
                return TodayPlanLaunchResolution(
                    path: .approvedOverlayAdjusted,
                    source: .approvedOverlay,
                    usesPreparedDraft: false
                )
            }
            return resolveLaunch(
                request: .startAsPlanned,
                recommendation: recommendation,
                hasOverlayAffectingToday: hasOverlayAffectingToday,
                hasApprovedProposalAppliedForToday: hasApprovedProposalAppliedForToday
            )
        }
    }

    static func executionSourceLabels(
        plan: TodayPlan,
        resolution: TodayPlanLaunchResolution,
        hasRelevantPendingProposal: Bool
    ) -> [String] {
        var labels = plan.attribution.activeSourceLabels.filter {
            $0 != "Approved Overlays" && $0 != "Proposals"
        }

        switch resolution.source {
        case .plannedPrescription:
            labels.append(plan.attribution.influenceFlags.usedActiveProgramContext ? "Base Program" : "Base Plan")
            if hasRelevantPendingProposal {
                labels.append("Pending Proposal Not Applied")
            }
        case .approvedOverlay:
            labels.append("Approved Overlay")
        case .runtimeCoachOnly:
            labels.append("Daily Coach Runtime")
        case .pendingProposal:
            labels.append("Pending Proposal")
        }

        return dedupedLabels(labels)
    }

    /// Pure mapping from an iPhone `TodayPlanLaunchPath` to the watch-safe
    /// `WatchSessionPlanKind`. Kept alongside `resolveLaunch` so a single
    /// call site owns the planned/overlay/runtime classification.
    static func watchSessionPlanKind(for path: TodayPlanLaunchPath) -> WatchSessionPlanKind {
        switch path {
        case .planned: return .planned
        case .approvedOverlayAdjusted: return .overlayAdjusted
        case .runtimeAdjusted: return .runtimeAdjusted
        }
    }

    /// Stable session-version label used across watch payloads so the watch
    /// never shows the wrong attribution when the iPhone launches a planned
    /// vs overlay vs runtime-adjusted version. Deterministic and side-effect
    /// free so it can be unit-tested directly.
    static func watchSessionVersionStableID(
        runStableID: String?,
        path: TodayPlanLaunchPath,
        weekNumber: Int?,
        sessionNumber: Int?
    ) -> String {
        let runSegment = runStableID ?? "standalone"
        let coord: String = {
            if let weekNumber, let sessionNumber {
                return "w\(weekNumber)s\(sessionNumber)"
            }
            return "free"
        }()
        let suffix: String = {
            switch path {
            case .planned: return "planned"
            case .approvedOverlayAdjusted: return "overlay"
            case .runtimeAdjusted: return "runtime"
            }
        }()
        return "\(runSegment)::\(coord)::\(suffix)"
    }

    static func sourceDescription(
        source: TodayPlanChangeSource,
        hasRelevantPendingProposal: Bool
    ) -> String {
        switch source {
        case .pendingProposal:
            return "Pending proposal awaiting confirmation."
        case .approvedOverlay:
            return "Approved overlay is active for this session."
        case .runtimeCoachOnly:
            return "Runtime Daily Coach adjustment for today only."
        case .plannedPrescription:
            if hasRelevantPendingProposal {
                return "Base plan selected while a relevant pending proposal is awaiting confirmation."
            }
            return "Base program prescription with no additional change layer."
        }
    }

    private static func impactRank(_ impact: TodayPlanProposalImpact) -> Int {
        switch impact {
        case .affectsToday: return 0
        case .affectsUpcomingSession: return 1
        case .affectsLongHorizonProgramming: return 2
        }
    }

    private static func dedupedLabels(_ labels: [String]) -> [String] {
        var seen: Set<String> = []
        return labels.compactMap { raw in
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !seen.contains(label) else { return nil }
            seen.insert(label)
            return label
        }
    }
}
