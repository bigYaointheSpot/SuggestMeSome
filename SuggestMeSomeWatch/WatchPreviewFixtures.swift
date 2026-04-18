//
//  WatchPreviewFixtures.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 3 — Mock snapshots used by watch SwiftUI previews.
//
//  Kept behind `#if DEBUG` so production builds never carry preview fixtures.
//  These values exercise the empty, normal, pain-flagged, adherence-rescue,
//  and active-workout states listed in the prompt's validation checklist.
//

#if DEBUG
import Foundation

enum WatchPreviewFixtures {

    static let referenceDate = Date(timeIntervalSince1970: 1_744_549_200) // 2025-04-13 13:00 UTC

    // MARK: - Session Status

    static let reachableStatus = WatchCompanionSessionStatus(
        isSupported: true,
        activationState: .activated,
        isCompanionAppInstalled: true,
        isReachable: true,
        hasContentPending: false,
        message: "Synced from iPhone.",
        checkedAt: referenceDate
    )

    static let idleStatus = WatchCompanionSessionStatus(
        isSupported: true,
        activationState: .activated,
        isCompanionAppInstalled: true,
        isReachable: false,
        hasContentPending: false,
        message: "iPhone will sync when available.",
        checkedAt: referenceDate
    )

    static let waitingStatus = WatchCompanionSessionStatus(
        isSupported: true,
        activationState: .inactive,
        isCompanionAppInstalled: true,
        isReachable: false,
        hasContentPending: true,
        message: "Waiting for iPhone.",
        checkedAt: referenceDate
    )

    // MARK: - Today Plan Snapshots

    static let normalPlan = WatchTodayPlanSnapshot(
        confidence: "High",
        compactSummary: "Push focus, 4 lifts, ~55 min",
        primarySuggestionText: "Bench 185 × 5 × 3 · Overhead 115 × 8",
        readinessTier: "Strong",
        hasPainFlag: false,
        sessionLabel: "W3 · S2 — Upper A",
        programName: "Hypertrophy Block",
        programRunStableID: "preview-run",
        programWeekNumber: 3,
        programSessionNumber: 2,
        activeSourceLabels: ["Program", "Check-In", "History"],
        whatChangedToday: "",
        adherenceHeadline: nil,
        adherenceGuidanceType: nil,
        sessionsBehindCount: 0,
        pendingProposalCount: 0,
        generatedAt: referenceDate
    )

    static let painFlaggedPlan = WatchTodayPlanSnapshot(
        confidence: "Medium",
        compactSummary: "Swap: row variation for shoulder safety",
        primarySuggestionText: "Hinge light · Cable row 3 × 12 · Skip overhead",
        readinessTier: "Neutral",
        hasPainFlag: true,
        sessionLabel: "W3 · S2 — Upper A",
        programName: "Hypertrophy Block",
        programRunStableID: "preview-run",
        programWeekNumber: 3,
        programSessionNumber: 2,
        activeSourceLabels: ["Program", "Check-In", "Pain Flag"],
        whatChangedToday: "Right shoulder flagged this morning. Pushing deload on overhead pressing.",
        adherenceHeadline: nil,
        adherenceGuidanceType: nil,
        sessionsBehindCount: 0,
        pendingProposalCount: 0,
        generatedAt: referenceDate
    )

    static let adherenceRescuePlan = WatchTodayPlanSnapshot(
        confidence: "Medium",
        compactSummary: "Trim to 3 lifts, 35 min target",
        primarySuggestionText: "Squat 225 × 5 × 3 · RDL 155 × 8 × 2",
        readinessTier: "Neutral",
        hasPainFlag: false,
        sessionLabel: "W4 · S1 — Lower",
        programName: "Hypertrophy Block",
        programRunStableID: "preview-run",
        programWeekNumber: 4,
        programSessionNumber: 1,
        activeSourceLabels: ["Program", "History"],
        whatChangedToday: "Skipped two lower sessions. Rescuing with a trimmed primary lift list.",
        adherenceHeadline: "You're 2 sessions behind. Trim and resume today.",
        adherenceGuidanceType: "Trim and Resume",
        sessionsBehindCount: 2,
        pendingProposalCount: 0,
        generatedAt: referenceDate
    )

    // MARK: - Live Workout Snapshots

    static let activeLiveWorkout = WatchLiveWorkoutSnapshot(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
        elapsedSeconds: 1_842, // 30:42
        completedExercises: 2,
        totalExercises: 5,
        completedSetsInCurrentExercise: 1,
        totalSetsInCurrentExercise: 3,
        currentExerciseName: "Barbell Bench Press",
        sessionLabel: "W3 · S2 — Upper A",
        programRunStableID: "preview-run",
        programWeekNumber: 3,
        programSessionNumber: 2,
        sessionPlanKind: .planned,
        lifecycleState: .running,
        usesLinkedWatchHealthSession: true,
        sessionSourceLabels: ["Program", "Check-In"],
        sessionVersionStableID: "preview-session-version",
        capturedAt: referenceDate
    )

    static let activeProgressSnapshot = WatchWorkoutProgressSnapshot(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
        elapsedSeconds: 1_842,
        completedExercises: 2,
        totalExercises: 5,
        capturedAt: referenceDate
    )

    static let activeCurrentContext = WatchCurrentSessionContext(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
        exerciseIndex: 2,
        exerciseName: "Barbell Bench Press",
        totalExercisesInSession: 5,
        totalSetsInExercise: 3,
        loggedSetsInExercise: 1,
        nextSetNumber: 2,
        nextPrescribedReps: 5,
        nextPrescribedWeight: 185,
        nextPrescribedWeightUnit: "lb",
        isCardio: false,
        cardioTargetSeconds: nil,
        currentSetNumber: 2,
        currentSetTargetSummary: "5 reps @ 185 lb",
        currentSetCompletedWeight: 185,
        currentSetCompletedReps: 5,
        crownWeightStep: 5,
        quickCompleteEnabled: true,
        preferredInteractionModel: .digitalCrownFirst,
        sessionPlanKind: .planned,
        lifecycleState: .running,
        usesLinkedWatchHealthSession: true,
        sessionSourceLabels: ["Program", "Check-In"],
        sessionVersionStableID: "preview-session-version",
        capturedAt: referenceDate
    )

    static let cardioCurrentContext = WatchCurrentSessionContext(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
        exerciseIndex: 0,
        exerciseName: "Zone 2 Bike",
        totalExercisesInSession: 1,
        totalSetsInExercise: 1,
        loggedSetsInExercise: 0,
        nextSetNumber: 1,
        nextPrescribedReps: nil,
        nextPrescribedWeight: nil,
        nextPrescribedWeightUnit: nil,
        isCardio: true,
        cardioTargetSeconds: 1_500,
        currentSetNumber: 1,
        currentSetTargetSummary: "25m cardio target",
        currentSetCompletedWeight: nil,
        currentSetCompletedReps: nil,
        crownWeightStep: nil,
        quickCompleteEnabled: nil,
        preferredInteractionModel: nil,
        sessionPlanKind: .planned,
        lifecycleState: .running,
        usesLinkedWatchHealthSession: true,
        sessionSourceLabels: ["Program"],
        sessionVersionStableID: "preview-session-version-cardio",
        capturedAt: referenceDate
    )

    static let adjustedLiveWorkout = WatchLiveWorkoutSnapshot(
        workoutID: UUID(uuidString: "22222222-3333-4444-5555-666666666666") ?? UUID(),
        elapsedSeconds: 960, // 16:00
        completedExercises: 1,
        totalExercises: 4,
        completedSetsInCurrentExercise: 2,
        totalSetsInCurrentExercise: 3,
        currentExerciseName: "Goblet Squat",
        sessionLabel: "Lower — Adjusted",
        programRunStableID: "preview-run",
        programWeekNumber: 3,
        programSessionNumber: 3,
        sessionPlanKind: .runtimeAdjusted,
        lifecycleState: .running,
        usesLinkedWatchHealthSession: true,
        sessionSourceLabels: ["Program", "Daily Coach"],
        sessionVersionStableID: "preview-session-adjusted",
        capturedAt: referenceDate
    )

    static let adjustedCurrentContext = WatchCurrentSessionContext(
        workoutID: UUID(uuidString: "22222222-3333-4444-5555-666666666666") ?? UUID(),
        exerciseIndex: 1,
        exerciseName: "Goblet Squat",
        totalExercisesInSession: 4,
        totalSetsInExercise: 3,
        loggedSetsInExercise: 2,
        nextSetNumber: 3,
        nextPrescribedReps: 8,
        nextPrescribedWeight: 55,
        nextPrescribedWeightUnit: "lb",
        isCardio: false,
        cardioTargetSeconds: nil,
        currentSetNumber: 3,
        currentSetTargetSummary: "8 reps @ 55 lb",
        currentSetCompletedWeight: 55,
        currentSetCompletedReps: 8,
        crownWeightStep: 5,
        quickCompleteEnabled: true,
        preferredInteractionModel: .digitalCrownFirst,
        sessionPlanKind: .runtimeAdjusted,
        lifecycleState: .running,
        usesLinkedWatchHealthSession: true,
        sessionSourceLabels: ["Program", "Daily Coach"],
        sessionVersionStableID: "preview-session-adjusted",
        capturedAt: referenceDate
    )

    static let activeWatchMetrics = WatchWorkoutMetricsPayload(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
        sessionVersionStableID: "preview-session-version",
        lifecycleState: .running,
        isLinkedHealthSessionActive: true,
        heartRateBPM: 132,
        activeEnergyKilocalories: 214,
        capturedAt: referenceDate
    )

    static let completionPayload = WatchSessionCompletionPayload(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
        completedAt: referenceDate,
        totalElapsedSeconds: 3_300,
        completedExercises: 5,
        totalExercises: 5,
        completedSets: 15,
        totalSets: 15,
        sessionLabel: "W3 · S2 — Upper A",
        sessionPlanKind: .planned,
        sessionSourceLabels: ["Program", "Check-In"],
        sessionVersionStableID: "preview-session-version",
        newPersonalRecordCount: 2
    )

    static let completionPayloadNoPR = WatchSessionCompletionPayload(
        workoutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
        completedAt: referenceDate,
        totalElapsedSeconds: 2_460,
        completedExercises: 4,
        totalExercises: 4,
        completedSets: 12,
        totalSets: 12,
        sessionLabel: "Upper — Manual",
        sessionPlanKind: nil,
        sessionSourceLabels: nil,
        sessionVersionStableID: nil,
        newPersonalRecordCount: 0
    )
}
#endif
