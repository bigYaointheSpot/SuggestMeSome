//
//  WatchWidgetSnapshot.swift
//  SuggestMeSome
//
//  Feature 12 Prompt 6 — Smart Stack snapshot model shared by the watch app
//  and the watch widget extension.
//

import Foundation

enum WatchSmartStackPreferredSurface: String, Codable, Equatable {
    case todayPlan
    case liveWorkout
    case empty
}

struct WatchWidgetTodayPlanSummary: Codable, Equatable {
    var sessionLabel: String
    var primarySuggestionText: String
    var compactSummary: String
    var readinessTier: String
    var confidence: String
    var hasPainFlag: Bool
    var sourceLabels: [String]
    var generatedAt: Date
}

struct WatchWidgetLiveWorkoutSummary: Codable, Equatable {
    var workoutID: UUID
    var sessionLabel: String
    var currentExerciseName: String?
    var currentSetSummary: String?
    var elapsedSeconds: Int
    var completedExercises: Int
    var totalExercises: Int
    var completedSetsInCurrentExercise: Int
    var totalSetsInCurrentExercise: Int
    var sessionPlanKind: WatchSessionPlanKind?
    var sourceLabels: [String]
    var sessionVersionStableID: String?
    var capturedAt: Date
}

struct WatchWidgetSnapshot: Codable, Equatable {
    static let activeWorkoutStaleAfter: TimeInterval = 20 * 60

    var todayPlan: WatchWidgetTodayPlanSummary?
    var liveWorkout: WatchWidgetLiveWorkoutSummary?
    var updatedAt: Date

    static func empty(updatedAt: Date = Date()) -> WatchWidgetSnapshot {
        WatchWidgetSnapshot(todayPlan: nil, liveWorkout: nil, updatedAt: updatedAt)
    }

    func preferredSurface(
        now: Date = Date(),
        activeWorkoutStaleAfter: TimeInterval = Self.activeWorkoutStaleAfter
    ) -> WatchSmartStackPreferredSurface {
        if let liveWorkout, !isLiveWorkoutStale(liveWorkout, now: now, staleAfter: activeWorkoutStaleAfter) {
            return .liveWorkout
        }
        if todayPlan != nil {
            return .todayPlan
        }
        return .empty
    }

    static func mergingTodayPlan(
        _ plan: WatchTodayPlanSnapshot,
        into existing: WatchWidgetSnapshot = .empty(),
        updatedAt: Date = Date()
    ) -> WatchWidgetSnapshot {
        WatchWidgetSnapshot(
            todayPlan: WatchWidgetTodayPlanSummary(
                sessionLabel: plan.sessionLabel,
                primarySuggestionText: plan.primarySuggestionText,
                compactSummary: plan.compactSummary,
                readinessTier: plan.readinessTier,
                confidence: plan.confidence,
                hasPainFlag: plan.hasPainFlag,
                sourceLabels: plan.activeSourceLabels,
                generatedAt: plan.generatedAt
            ),
            liveWorkout: existing.liveWorkout,
            updatedAt: updatedAt
        )
    }

    static func mergingLiveWorkout(
        _ liveWorkout: WatchLiveWorkoutSnapshot,
        currentContext: WatchCurrentSessionContext? = nil,
        into existing: WatchWidgetSnapshot = .empty(),
        updatedAt: Date = Date()
    ) -> WatchWidgetSnapshot {
        let context = matchingContext(currentContext, liveWorkout: liveWorkout)
        return WatchWidgetSnapshot(
            todayPlan: existing.todayPlan,
            liveWorkout: WatchWidgetLiveWorkoutSummary(
                workoutID: liveWorkout.workoutID,
                sessionLabel: liveWorkout.sessionLabel,
                currentExerciseName: context?.exerciseName ?? liveWorkout.currentExerciseName,
                currentSetSummary: context?.currentSetTargetSummary,
                elapsedSeconds: max(0, liveWorkout.elapsedSeconds),
                completedExercises: liveWorkout.completedExercises,
                totalExercises: liveWorkout.totalExercises,
                completedSetsInCurrentExercise: liveWorkout.completedSetsInCurrentExercise,
                totalSetsInCurrentExercise: liveWorkout.totalSetsInCurrentExercise,
                sessionPlanKind: liveWorkout.sessionPlanKind,
                sourceLabels: liveWorkout.sessionSourceLabels ?? [],
                sessionVersionStableID: liveWorkout.sessionVersionStableID,
                capturedAt: liveWorkout.capturedAt
            ),
            updatedAt: updatedAt
        )
    }

    func updatingCurrentContext(
        _ context: WatchCurrentSessionContext,
        updatedAt: Date = Date()
    ) -> WatchWidgetSnapshot {
        guard var liveWorkout, contextMatches(context, liveWorkout: liveWorkout) else {
            return self
        }
        liveWorkout.currentExerciseName = context.exerciseName
        liveWorkout.currentSetSummary = context.currentSetTargetSummary
        liveWorkout.sourceLabels = context.sessionSourceLabels ?? liveWorkout.sourceLabels
        liveWorkout.sessionPlanKind = context.sessionPlanKind ?? liveWorkout.sessionPlanKind
        liveWorkout.sessionVersionStableID = context.sessionVersionStableID ?? liveWorkout.sessionVersionStableID
        liveWorkout.capturedAt = max(liveWorkout.capturedAt, context.capturedAt)
        return WatchWidgetSnapshot(
            todayPlan: todayPlan,
            liveWorkout: liveWorkout,
            updatedAt: updatedAt
        )
    }

    func clearingActiveWorkout(updatedAt: Date = Date()) -> WatchWidgetSnapshot {
        WatchWidgetSnapshot(
            todayPlan: todayPlan,
            liveWorkout: nil,
            updatedAt: updatedAt
        )
    }

    private func isLiveWorkoutStale(
        _ liveWorkout: WatchWidgetLiveWorkoutSummary,
        now: Date,
        staleAfter: TimeInterval
    ) -> Bool {
        liveWorkout.capturedAt.addingTimeInterval(staleAfter) < now
    }

    private static func matchingContext(
        _ context: WatchCurrentSessionContext?,
        liveWorkout: WatchLiveWorkoutSnapshot
    ) -> WatchCurrentSessionContext? {
        guard let context else { return nil }
        guard context.workoutID == liveWorkout.workoutID else { return nil }
        if let contextVersion = context.sessionVersionStableID,
           let liveVersion = liveWorkout.sessionVersionStableID,
           contextVersion != liveVersion {
            return nil
        }
        return context
    }

    private func contextMatches(
        _ context: WatchCurrentSessionContext,
        liveWorkout: WatchWidgetLiveWorkoutSummary
    ) -> Bool {
        guard context.workoutID == liveWorkout.workoutID else { return false }
        if let contextVersion = context.sessionVersionStableID,
           let liveVersion = liveWorkout.sessionVersionStableID,
           contextVersion != liveVersion {
            return false
        }
        return true
    }
}

enum WatchWidgetSnapshotStore {
    static let appGroupID = "group.com.alexyao.SuggestMeSome"
    static let snapshotKey = "watch.smartStack.snapshot.v1"

    static func load(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) -> WatchWidgetSnapshot {
        guard let defaults,
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WatchWidgetSnapshot.self, from: data) else {
            return .empty()
        }
        return snapshot
    }

    static func save(
        _ snapshot: WatchWidgetSnapshot,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: snapshotKey)
    }
}
