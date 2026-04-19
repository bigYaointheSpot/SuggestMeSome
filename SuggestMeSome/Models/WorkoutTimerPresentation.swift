//
//  WorkoutTimerPresentation.swift
//  SuggestMeSome
//
//  Narrow timer-only presentation helpers used to keep tick-driven updates
//  isolated from larger phone workout surfaces.
//

import Foundation

struct WorkoutElapsedTimerPresentation: Equatable {
    let isActive: Bool
    let startTime: Date?
    let session: ActiveWorkoutSession?

    func elapsedSeconds(at date: Date) -> Int {
        guard isActive else { return 0 }
        if let session {
            return session.elapsedSeconds(at: date)
        }
        guard let startTime else { return 0 }
        return max(0, Int(date.timeIntervalSince(startTime)))
    }

    func formattedElapsed(at date: Date) -> String {
        let elapsedSeconds = elapsedSeconds(at: date)
        let hours = elapsedSeconds / 3_600
        let minutes = (elapsedSeconds % 3_600) / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct ActiveWorkoutBannerPresentation: Equatable {
    let elapsedTimer: WorkoutElapsedTimerPresentation
    let exerciseCount: Int

    var exerciseCountText: String {
        exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
    }
}
