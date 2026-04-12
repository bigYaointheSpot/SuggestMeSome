//
//  AdherenceRescueService.swift
//  SuggestMeSome
//
//  Feature 10 Prompt 6 — Adherence rescue logic.
//  Detects when a user is behind their active program schedule and generates
//  conservative, deterministic "resume / trim / continue normal" guidance.
//
//  Non-destructive: no program mutations, no overlay creation.
//

import Foundation

// MARK: - AdherenceRescueService

struct AdherenceRescueService {

    // MARK: - Public API

    /// Evaluate the user's adherence to an active program and return rescue guidance.
    ///
    /// - Parameters:
    ///   - run: The active program run.
    ///   - program: The training program associated with the run.
    ///   - completedWorkoutCount: Number of program-linked workouts logged so far.
    ///   - referenceDate: The date to evaluate adherence against (defaults to today).
    /// - Returns: An `AdherenceRescue` value, or nil if no program is active.
    static func evaluate(
        run: ProgramRun?,
        program: TrainingProgram?,
        completedWorkoutCount: Int,
        referenceDate: Date = Date()
    ) -> AdherenceRescue? {
        guard let run, let program else { return nil }

        let sessionsBehind = computeSessionsBehind(
            run: run,
            program: program,
            completedWorkoutCount: completedWorkoutCount,
            referenceDate: referenceDate
        )

        let status = adherenceStatus(sessionsBehind: sessionsBehind)

        switch status {
        case .onTrack, .noProgramActive:
            // Return a minimal "on track" rescue with no actionable deviation
            return AdherenceRescue(
                status: status,
                guidanceType: .continueNormalSequence,
                headline: onTrackHeadline(program: program, completedWorkoutCount: completedWorkoutCount),
                details: onTrackDetails(program: program, completedWorkoutCount: completedWorkoutCount),
                sessionsBehindCount: 0
            )

        case .slightlyBehind(let behind):
            return AdherenceRescue(
                status: status,
                guidanceType: .trimAndResume,
                headline: "Behind by \(behind) session — trim to catch up.",
                details: trimResumeDetails(
                    program: program,
                    behind: behind,
                    completedWorkoutCount: completedWorkoutCount
                ),
                sessionsBehindCount: behind
            )

        case .significantlyBehind(let behind):
            return AdherenceRescue(
                status: status,
                guidanceType: .conservativeResume,
                headline: "\(behind) sessions behind — conservative resume recommended.",
                details: conservativeResumeDetails(
                    program: program,
                    behind: behind,
                    completedWorkoutCount: completedWorkoutCount
                ),
                sessionsBehindCount: behind
            )
        }
    }

    // MARK: - Sessions-Behind Computation

    /// Computes how many sessions the user is behind the expected program pace.
    ///
    /// Expected sessions = floor(daysElapsed / 7) × sessionsPerWeek + fractional-week sessions.
    /// We use a simple floor(daysElapsed / 7.0 * sessionsPerWeek) model so the result
    /// never overestimates on partial weeks.
    static func computeSessionsBehind(
        run: ProgramRun,
        program: TrainingProgram,
        completedWorkoutCount: Int,
        referenceDate: Date = Date()
    ) -> Int {
        let daysElapsed = max(
            0,
            Calendar.current.dateComponents([.day], from: run.startDate, to: referenceDate).day ?? 0
        )

        // Expected sessions based on elapsed days and sessions-per-week cadence
        let weeksElapsed = Double(daysElapsed) / 7.0
        let expectedSessions = Int(floor(weeksElapsed * Double(program.sessionsPerWeek)))

        // Cap at total program sessions so we never report "behind" on a completed program
        let totalProgramSessions = program.lengthInWeeks * program.sessionsPerWeek
        let cappedExpected = min(expectedSessions, totalProgramSessions)

        return max(0, cappedExpected - completedWorkoutCount)
    }

    // MARK: - Status Classification

    static func adherenceStatus(sessionsBehind: Int) -> AdherenceStatus {
        switch sessionsBehind {
        case 0:
            return .onTrack
        case 1:
            return .slightlyBehind(sessionsBehind: 1)
        default:
            return .significantlyBehind(sessionsBehind: sessionsBehind)
        }
    }

    // MARK: - Guidance Text

    private static func onTrackHeadline(program: TrainingProgram, completedWorkoutCount: Int) -> String {
        let total = program.lengthInWeeks * program.sessionsPerWeek
        return "On track — \(completedWorkoutCount)/\(total) sessions complete."
    }

    private static func onTrackDetails(program: TrainingProgram, completedWorkoutCount: Int) -> String {
        let total = program.lengthInWeeks * program.sessionsPerWeek
        let remaining = total - completedWorkoutCount
        if remaining <= 0 {
            return "You have completed all \(total) sessions of \(program.name). Great work — this run is effectively complete. Consider reviewing your progress in the Dashboard before starting a new program."
        }
        return "You are on pace with \(program.name). \(remaining) session\(remaining == 1 ? "" : "s") remain. Continue with the next scheduled session as planned."
    }

    private static func trimResumeDetails(
        program: TrainingProgram,
        behind: Int,
        completedWorkoutCount: Int
    ) -> String {
        return "You are \(behind) session behind the expected pace for \(program.name). To resume comfortably: run the next scheduled session with one backoff set removed from the primary lift. Keep the main lift, top set, and one key accessory. This lets you re-engage with training quality without forcing a full-volume session after a break."
    }

    private static func conservativeResumeDetails(
        program: TrainingProgram,
        behind: Int,
        completedWorkoutCount: Int
    ) -> String {
        return "You are \(behind) sessions behind the expected pace for \(program.name). A conservative resume is recommended: reduce working loads by 5–10% across all lifts, drop accessories entirely for this session, and focus purely on the primary lift and top set. This re-establishes your training pattern without forcing full volume after an extended gap. Build back to full sessions over the next 2–3 workouts before resuming normal load progression."
    }
}
