//
//  WatchActiveWorkoutView.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 3 — Premium live-workout execution surface.
//
//  Consumes iPhone-produced `WatchLiveWorkoutSnapshot` and
//  `WatchCurrentSessionContext` verbatim. Crown-first logging uses two
//  stacked focused controls — reps on top, weight below — matching the
//  locked-in Feature 12 direction.
//

import SwiftUI

struct WatchActiveWorkoutView: View {
    let liveWorkout: WatchLiveWorkoutSnapshot?
    let progressSnapshot: WatchWorkoutProgressSnapshot?
    let currentContext: WatchCurrentSessionContext?
    let sessionStatus: WatchCompanionSessionStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sessionHeader
                elapsedAndProgress
                if let currentContext {
                    currentExerciseCard(currentContext)
                }
                WatchConnectionDot(status: sessionStatus)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Live Workout")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchPalette.primary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(liveWorkout?.sessionLabel ?? "Active workout")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Progress

    private var elapsedAndProgress: some View {
        let completed = liveWorkout?.completedExercises ?? progressSnapshot?.completedExercises ?? 0
        let total = max(liveWorkout?.totalExercises ?? progressSnapshot?.totalExercises ?? 0, 1)
        let elapsed = liveWorkout?.elapsedSeconds ?? progressSnapshot?.elapsedSeconds ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            Text(WatchDurationFormatter.format(elapsed))
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
            ProgressView(value: Double(completed), total: Double(total))
                .progressViewStyle(.linear)
                .tint(WatchPalette.primary)
            Text("\(completed) of \(total) exercises")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .watchCard(emphasized: true)
    }

    // MARK: - Current Exercise

    private func currentExerciseCard(_ context: WatchCurrentSessionContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.exerciseName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(setSummary(for: context))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if context.isCardio {
                cardioTarget(context.cardioTargetSeconds)
            } else {
                WatchCrownSetLoggingControls(context: context)
            }
        }
        .watchCard()
    }

    private func cardioTarget(_ seconds: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Target")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(seconds.map(WatchDurationFormatter.format) ?? "Open on iPhone")
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }

    private func setSummary(for context: WatchCurrentSessionContext) -> String {
        if let summary = context.currentSetTargetSummary, !summary.isEmpty {
            return summary
        }
        if let setNumber = context.currentSetNumber ?? context.nextSetNumber {
            return "Set \(setNumber) of \(context.totalSetsInExercise)"
        }
        return "Exercise \(context.exerciseIndex + 1) of \(context.totalExercisesInSession)"
    }
}

// MARK: - Crown-first Set Logging Controls

struct WatchCrownSetLoggingControls: View {
    enum FocusedField: Hashable {
        case reps
        case weight
    }

    let context: WatchCurrentSessionContext

    @State private var repsValue: Double
    @State private var weightValue: Double
    @FocusState private var focusedField: FocusedField?

    init(context: WatchCurrentSessionContext) {
        self.context = context
        let initialReps = context.currentSetCompletedReps ?? context.nextPrescribedReps ?? 0
        let initialWeight = context.currentSetCompletedWeight ?? context.nextPrescribedWeight ?? 0
        _repsValue = State(initialValue: Double(initialReps))
        _weightValue = State(initialValue: initialWeight)
    }

    var body: some View {
        VStack(spacing: 6) {
            crownRow(
                title: "Reps",
                valueText: "\(Int(repsValue.rounded()))",
                field: .reps
            )
            .digitalCrownRotation(
                $repsValue,
                from: 0,
                through: 100,
                by: 1,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )

            crownRow(
                title: "Weight",
                valueText: weightText,
                field: .weight
            )
            .digitalCrownRotation(
                $weightValue,
                from: 0,
                through: 1_000,
                by: context.crownWeightStep ?? 5,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
        }
        .onAppear {
            if focusedField == nil {
                focusedField = .reps
            }
        }
    }

    private var weightText: String {
        let unit = context.nextPrescribedWeightUnit ?? "lb"
        return "\(weightValue.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func crownRow(title: String, valueText: String, field: FocusedField) -> some View {
        let isFocused = focusedField == field
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isFocused ? WatchPalette.primary : .secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(valueText)
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            isFocused ? WatchPalette.primary.opacity(0.28) : WatchPalette.surface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? WatchPalette.primary : WatchPalette.strokeFaint, lineWidth: 0.75)
        )
        .focusable(true)
        .focused($focusedField, equals: field)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = field
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Active Workout — Strength") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.activeCurrentContext,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active Workout — Cardio") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.cardioCurrentContext,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active Workout — Idle Connection") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.activeCurrentContext,
        sessionStatus: WatchPreviewFixtures.idleStatus
    )
}
#endif
