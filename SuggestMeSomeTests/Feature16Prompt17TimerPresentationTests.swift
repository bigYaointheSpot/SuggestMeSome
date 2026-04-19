import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
struct Feature16Prompt17TimerPresentationTests {

    @Test func elapsedTimerAdvancesRunningSessionFromAccumulatedState() {
        let anchor = Date(timeIntervalSince1970: 1_800_700_000)
        let session = ActiveWorkoutSession(
            startTime: anchor.addingTimeInterval(-600),
            lifecycleState: .running,
            accumulatedElapsedSeconds: 120,
            stateChangedAt: anchor
        )
        let presentation = WorkoutElapsedTimerPresentation(
            isActive: true,
            startTime: session.startTime,
            session: session
        )

        #expect(presentation.elapsedSeconds(at: anchor.addingTimeInterval(30)) == 150)
        #expect(presentation.formattedElapsed(at: anchor.addingTimeInterval(30)) == "00:02:30")
    }

    @Test func elapsedTimerDoesNotAdvancePausedSession() {
        let anchor = Date(timeIntervalSince1970: 1_800_700_100)
        let session = ActiveWorkoutSession(
            startTime: anchor.addingTimeInterval(-900),
            lifecycleState: .paused,
            accumulatedElapsedSeconds: 245,
            stateChangedAt: anchor
        )
        let presentation = WorkoutElapsedTimerPresentation(
            isActive: true,
            startTime: session.startTime,
            session: session
        )

        #expect(presentation.elapsedSeconds(at: anchor.addingTimeInterval(45)) == 245)
        #expect(presentation.formattedElapsed(at: anchor.addingTimeInterval(45)) == "00:04:05")
    }

    @Test func elapsedTimerFallsBackToStartTimeWhenSessionSnapshotIsUnavailable() {
        let anchor = Date(timeIntervalSince1970: 1_800_700_200)
        let presentation = WorkoutElapsedTimerPresentation(
            isActive: true,
            startTime: anchor,
            session: nil
        )

        #expect(presentation.elapsedSeconds(at: anchor.addingTimeInterval(75)) == 75)
        #expect(presentation.formattedElapsed(at: anchor.addingTimeInterval(75)) == "00:01:15")
    }

    @Test func inactiveElapsedTimerStaysAtZero() {
        let anchor = Date(timeIntervalSince1970: 1_800_700_300)
        let presentation = WorkoutElapsedTimerPresentation(
            isActive: false,
            startTime: anchor.addingTimeInterval(-120),
            session: nil
        )

        #expect(presentation.elapsedSeconds(at: anchor) == 0)
        #expect(presentation.formattedElapsed(at: anchor) == "00:00:00")
    }
}
