//
//  TodayPlanTypes.swift
//  SuggestMeSome
//
//  Feature 10 Prompt 6 — Today Plan Engine value types.
//  Non-persisted structs and enums that represent the full output of the
//  TodayPlanEngine orchestration layer.
//

import Foundation

// MARK: - TodayPlanConfidence

/// Deterministic confidence band for the today plan output.
///
/// Classification rules (see TodayPlanEngine for exact logic):
/// - `.high`   — active program + recent program-linked workouts + today check-in
/// - `.medium` — partial signal (program with no recent history, or check-in only, or history only)
/// - `.low`    — sparse signal (no check-in, no program, fewer than 3 recent workouts)
enum TodayPlanConfidence: String {
    case high   = "High"
    case medium = "Medium"
    case low    = "Low"
}

// MARK: - TodayPlanSourceAttribution

/// Explicit per-source influence description for the today plan.
///
/// Each field describes what signal was available and how it was used (or why it was absent).
struct TodayPlanSourceAttribution {
    /// Influence from the user's manual daily check-in (readiness, time, pain).
    let manualReadinessInfluence: String
    /// Influence from HealthKit objective recovery data (HRV, sleep, steps).
    let healthKitInfluence: String
    /// Influence from the active program's prescription (session sequence, load targets).
    let programPrescriptionInfluence: String
    /// Influence from active adaptive overlays and pending proposals.
    let adaptiveOverlayInfluence: String
    /// Influence from recent training history (fatigue, frequency, session patterns).
    let recentHistoryInfluence: String

    /// Ordered list of source labels for compact display in the UI.
    let activeSourceLabels: [String]
    /// Machine-readable influence flags for deterministic UI + tests.
    let influenceFlags: TodayPlanInfluenceFlags
}

// MARK: - TodayPlanInfluenceFlags

/// Boolean source flags used to make attribution and change messaging explicit.
struct TodayPlanInfluenceFlags {
    let usedActiveProgramContext: Bool
    let usedApprovedOverlayContext: Bool
    let usedPendingProposalContext: Bool
    let usedRuntimeCoachAdjustment: Bool
    let usedRecentHistoryContext: Bool
    let usedHealthKitRecoveryNudge: Bool
}

// MARK: - TodayPlanChangeType

/// High-level category for "What Changed Today".
enum TodayPlanChangeType: String {
    case noChanges = "No Changes"
    case runtimeOnlyAdjustment = "Runtime Adjustment"
    case approvedOverlayInfluence = "Approved Overlay Influence"
    case pendingProposalRelevance = "Pending Proposal Relevance"
    case combinedInfluence = "Combined Influence"
}

// MARK: - TodayPlanChangeSummary

/// Structured "What Changed Today" output designed for compact UI sections.
struct TodayPlanChangeSummary {
    let changeType: TodayPlanChangeType
    let headline: String
    let details: [String]

    var compactText: String {
        details.joined(separator: " ")
    }
}

// MARK: - TodayPlanProposalImpact

/// Horizon classification for pending adaptation proposals.
enum TodayPlanProposalImpact: String {
    case affectsToday = "Affects Today"
    case affectsUpcomingSession = "Affects Upcoming Session"
    case affectsLongHorizonProgramming = "Longer-Horizon Programming"
}

// MARK: - TodayPlanProposalAwarenessItem

/// View-friendly pending proposal summary with impact horizon classification.
struct TodayPlanProposalAwarenessItem {
    let proposalID: UUID
    let summaryText: String
    let impact: TodayPlanProposalImpact
    let targetDescription: String
}

// MARK: - AdherenceStatus

/// Summarises how aligned the user is with their active program schedule.
enum AdherenceStatus: Equatable {
    /// User is on schedule (0 sessions behind).
    case onTrack
    /// User is 1 session behind the expected pace.
    case slightlyBehind(sessionsBehind: Int)
    /// User is 2+ sessions behind the expected pace.
    case significantlyBehind(sessionsBehind: Int)
    /// No active program — adherence is not applicable.
    case noProgramActive
}

// MARK: - AdherenceGuidanceType

/// The style of rescue guidance recommended when adherence is behind.
enum AdherenceGuidanceType: String {
    /// Normal next session — no trimming needed.
    case continueNormalSequence = "Continue"
    /// Trim one backoff set or lowest-priority accessory to make the session more achievable.
    case trimAndResume = "Trim and Resume"
    /// Conservative volume and load — prioritise showing up over ambition.
    case conservativeResume = "Conservative Resume"
}

// MARK: - AdherenceRescue

/// Adherence-aware coaching guidance generated when the user is behind in their program.
///
/// Non-destructive — does not mutate any program sessions or add overlays.
struct AdherenceRescue {
    /// Adherence classification.
    let status: AdherenceStatus
    /// The style of guidance this rescue produces.
    let guidanceType: AdherenceGuidanceType
    /// Short headline for the rescue card (≤ 60 chars).
    let headline: String
    /// Expanded explanation shown in the rescue card detail view.
    let details: String
    /// How many sessions behind the expected pace (0 when onTrack).
    let sessionsBehindCount: Int
}

// MARK: - TodayPlan

/// Full today plan output from the TodayPlanEngine orchestration layer.
///
/// Purely in-memory; never persisted. Designed to be stable across iPhone and Watch
/// presentation surfaces — the view layer selects which fields to surface.
struct TodayPlan {
    /// Core coaching recommendation (existing type — carries primary/secondary suggestions).
    let recommendation: DailyCoachRecommendation
    /// Deterministic confidence band for this plan.
    let confidence: TodayPlanConfidence
    /// Human-readable explanation of why this confidence level was assigned.
    let confidenceRationale: String
    /// Per-source influence descriptions.
    let attribution: TodayPlanSourceAttribution
    /// Adherence rescue guidance; nil when on-track or no program active.
    let adherenceRescue: AdherenceRescue?
    /// "Why today?" — one short paragraph explaining the core logic behind today's plan.
    let whyToday: String
    /// "What changed today?" — notes significant departures from neutral/baseline.
    /// Empty string when today is a normal session with no noteworthy signals.
    let whatChangedToday: String
    /// Structured "What changed today?" output used by richer UI blocks.
    let changeSummary: TodayPlanChangeSummary
    /// Pending proposal awareness with explicit impact horizon classification.
    let proposalAwareness: [TodayPlanProposalAwarenessItem]
}
