//
//  DailyCoachRecommendationTypes.swift
//  SuggestMeSome
//
//  Feature 7 — Daily Coach recommendation value types.
//  Non-persisted structs and enums that represent today's coaching output.
//

import Foundation

// MARK: - DailySuggestionType

/// Concrete coaching action suggested for today's session.
enum DailySuggestionType: String {
    case runAsPlanned
    case trimAccessories
    case trimOneBackoffSet
    case reduceWorkingLoadsSlightly
    case suggestManualVariationSwap
    case standaloneRecoverySession
    case standaloneShortStrengthSession
}

// MARK: - StandaloneSessionType

/// Inferred session category for users without an active program.
enum StandaloneSessionType: String {
    case fullBody   = "Full Body"
    case upper      = "Upper Body"
    case lower      = "Lower Body"
    case push       = "Push"
    case pull       = "Pull"
    case recovery   = "Recovery"
    case cardio     = "Cardio"
}

// MARK: - ReadinessTier

/// Bucketed readiness level derived from today's check-in composite score.
enum ReadinessTier {
    /// Composite ≥ 4.0 — good day to train hard.
    case strong
    /// 2.5 ≤ composite < 4.0 — normal training day.
    case neutral
    /// Composite < 2.5 — conservative approach warranted.
    case low
    /// No check-in submitted today.
    case unknown
}

// MARK: - DailyCoachSuggestionItem

/// One actionable suggestion with a compact label and optional expanded detail.
struct DailyCoachSuggestionItem {
    let type: DailySuggestionType
    /// One-line summary shown in the collapsed card.
    let compactText: String
    /// Full explanation shown when the user expands the card.
    let expandedText: String
}

// MARK: - NextProgramSessionInfo

/// Identifies the next uncompleted session in the active program run.
struct NextProgramSessionInfo {
    let weekNumber: Int
    let sessionNumber: Int
    /// Optional descriptive name from the session template (e.g. "Heavy Squat Day").
    let sessionName: String?
    let programName: String
}

// MARK: - DailyCoachRecommendation

/// Complete daily coaching output — purely in-memory, never persisted.
struct DailyCoachRecommendation {
    /// One-line summary for the collapsed card header.
    let compactSummary: String
    /// Full paragraph shown when expanded.
    let expandedDetails: String
    /// The top-priority actionable suggestion.
    let primarySuggestion: DailyCoachSuggestionItem
    /// Supporting suggestions, may be empty.
    let secondarySuggestions: [DailyCoachSuggestionItem]
    /// Readiness tier derived from today's check-in.
    let readinessTier: ReadinessTier
    /// True when the user flagged pain or discomfort in their check-in.
    let hasPainFlag: Bool
    /// Set for program users; nil for standalone users.
    let nextProgramSession: NextProgramSessionInfo?
    /// Set for standalone users; nil for program users.
    let standaloneSessionType: StandaloneSessionType?
    /// Count of pending adaptation proposals surfaced for context.
    let pendingProposalCount: Int
}
