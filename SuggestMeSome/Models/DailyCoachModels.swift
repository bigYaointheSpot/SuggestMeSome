//
//  DailyCoachModels.swift
//  SuggestMeSome
//
//  Feature 7 — Daily Coach data layer.
//  Stores daily readiness check-ins and weekly review summaries.
//

import Foundation
import SwiftData

// MARK: - WorkoutEffortFeedback

/// Per-exercise effort rating captured during or after a session.
enum WorkoutEffortFeedback: String, Codable {
    case tooEasy
    case onTarget
    case tooHard
}

// MARK: - DailyCoachCheckIn

/// One readiness snapshot per calendar day (uniqueness enforced in service/UI code).
@Model
final class DailyCoachCheckIn {
    var id: UUID
    /// Calendar day this check-in represents (time component should be start-of-day).
    var date: Date
    /// Timestamp when the user started the check-in flow.
    var dayStart: Date
    /// 1–5 subjective sleep quality rating.
    var sleepQuality: Int
    /// 1–5 whole-body soreness rating.
    var soreness: Int
    /// 1–5 energy level rating.
    var energy: Int
    /// 1–5 stress level rating.
    var stress: Int
    /// How many minutes the user has available for today's session.
    var availableTimeMinutes: Int
    /// Whether the user flagged any pain or discomfort.
    var hasPainOrDiscomfort: Bool
    /// Free-text pain notes; only present when hasPainOrDiscomfort is true.
    var painNotes: String?
    /// Active program run at the time of check-in, if any.
    var programRun: ProgramRun?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        dayStart: Date = Date(),
        sleepQuality: Int = 3,
        soreness: Int = 1,
        energy: Int = 3,
        stress: Int = 2,
        availableTimeMinutes: Int = 60,
        hasPainOrDiscomfort: Bool = false,
        painNotes: String? = nil,
        programRun: ProgramRun? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.dayStart = dayStart
        self.sleepQuality = sleepQuality
        self.soreness = soreness
        self.energy = energy
        self.stress = stress
        self.availableTimeMinutes = availableTimeMinutes
        self.hasPainOrDiscomfort = hasPainOrDiscomfort
        self.painNotes = painNotes
        self.programRun = programRun
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - DailyCoachWeeklyReview

/// AI-generated weekly training summary surfaced to the user once per week.
@Model
final class DailyCoachWeeklyReview {
    var id: UUID
    /// Monday (or chosen week-start) of the reviewed week.
    var weekStart: Date
    /// Sunday (or chosen week-end) of the reviewed week.
    var weekEnd: Date
    /// True when this review covers a structured program week.
    var isProgramWeek: Bool
    /// Program run associated with this week, if any.
    var programRun: ProgramRun?
    /// One-line summary headline shown at the top of the review card.
    var headline: String
    /// Positive highlight from the week.
    var winText: String
    /// Area to monitor or potential risk flagged for the coming week.
    var watchoutText: String
    /// Concrete suggested action for the next training cycle.
    var nextActionText: String
    /// Opaque reference to the WeeklyTrainingAnalysis that sourced this review.
    var sourceWeeklyAnalysisIDText: String?
    /// False until the user opens/dismisses the review card.
    var hasBeenSeen: Bool

    var createdAt: Date

    init(
        id: UUID = UUID(),
        weekStart: Date,
        weekEnd: Date,
        isProgramWeek: Bool = false,
        programRun: ProgramRun? = nil,
        headline: String = "",
        winText: String = "",
        watchoutText: String = "",
        nextActionText: String = "",
        sourceWeeklyAnalysisIDText: String? = nil,
        hasBeenSeen: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.isProgramWeek = isProgramWeek
        self.programRun = programRun
        self.headline = headline
        self.winText = winText
        self.watchoutText = watchoutText
        self.nextActionText = nextActionText
        self.sourceWeeklyAnalysisIDText = sourceWeeklyAnalysisIDText
        self.hasBeenSeen = hasBeenSeen
        self.createdAt = createdAt
    }
}
