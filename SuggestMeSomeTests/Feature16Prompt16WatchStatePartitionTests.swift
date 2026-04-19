import Foundation
import Testing
@testable import SuggestMeSome

@Suite(.serialized)
@MainActor
struct Feature16Prompt16WatchStatePartitionTests {

    @Test func passiveTodayPlanUpdatesDoNotDisplaceActiveWorkoutPresentation() {
        let liveState = WatchLiveWorkoutState()
        let passiveState = WatchPassiveContextState()
        let presentationState = WatchRootPresentationState()
        let launch = WatchWorkoutLaunchPayload(
            workoutID: UUID(),
            startedAt: Date(),
            sessionPlanKind: .planned
        )

        liveState.setWorkoutLaunch(launch)
        presentationState.refresh(
            liveWorkoutState: liveState,
            passiveContextState: passiveState
        )

        passiveState.setTodayPlan(
            WatchTodayPlanSnapshot(
                confidence: "High",
                compactSummary: "Keep the plan simple.",
                primarySuggestionText: "Finish your current session.",
                readinessTier: "Strong",
                hasPainFlag: false,
                sessionLabel: "Upper",
                programName: "Smart Block",
                activeSourceLabels: ["Program"],
                whatChangedToday: "",
                adherenceHeadline: nil,
                adherenceGuidanceType: nil,
                sessionsBehindCount: 0,
                pendingProposalCount: 0,
                generatedAt: Date()
            )
        )
        presentationState.refresh(
            liveWorkoutState: liveState,
            passiveContextState: passiveState
        )

        #expect(presentationState.rootMode == .activeWorkout)
        #expect(liveState.workoutLaunch?.workoutID == launch.workoutID)
        #expect(passiveState.todayPlan?.sessionLabel == "Upper")
    }

    @Test func completionModeTransitionsIndependentlyOfLiveWorkoutBucket() {
        let liveState = WatchLiveWorkoutState()
        let passiveState = WatchPassiveContextState()
        let presentationState = WatchRootPresentationState()
        let completion = WatchSessionCompletionPayload(
            workoutID: UUID(),
            completedAt: Date(),
            totalElapsedSeconds: 2_400,
            completedExercises: 5,
            totalExercises: 5,
            completedSets: 16,
            totalSets: 16,
            sessionLabel: "Leg Day",
            sessionPlanKind: .planned,
            sessionSourceLabels: ["Program"],
            sessionVersionStableID: "session-v1",
            newPersonalRecordCount: 1
        )

        passiveState.setCompletion(completion)
        presentationState.refresh(
            liveWorkoutState: liveState,
            passiveContextState: passiveState
        )
        #expect(presentationState.rootMode == .sessionCompletion)
        #expect(liveState.hasActiveWorkout == false)

        passiveState.setCompletion(nil)
        presentationState.refresh(
            liveWorkoutState: liveState,
            passiveContextState: passiveState
        )
        #expect(presentationState.rootMode == .todayPlan)
        #expect(liveState.hasActiveWorkout == false)
    }
}
