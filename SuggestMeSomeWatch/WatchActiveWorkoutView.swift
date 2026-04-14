//
//  WatchActiveWorkoutView.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 5 — Premium live-workout execution surface.
//
//  Consumes iPhone-produced `WatchLiveWorkoutSnapshot` and
//  `WatchCurrentSessionContext` verbatim. Crown-first logging uses two
//  stacked focused controls — reps on top, weight below — matching the
//  locked-in Feature 12 direction. A watch-local rest timer takes over
//  the current-exercise card after each completed set and emits haptic
//  cues for the next-set transition.
//

import SwiftUI

struct WatchActiveWorkoutView: View {
    let liveWorkout: WatchLiveWorkoutSnapshot?
    let progressSnapshot: WatchWorkoutProgressSnapshot?
    let currentContext: WatchCurrentSessionContext?
    let sessionStatus: WatchCompanionSessionStatus
    var onExecutionAction: (WatchWorkoutExecutionActionDTO) -> Void = { _ in }

    @StateObject private var restTimer = WatchRestTimerController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sessionHeader
                elapsedAndProgress
                currentBlock
                WatchConnectionDot(status: sessionStatus)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .onChange(of: currentSetSignature) { _, _ in
            if restTimer.isRunning {
                restTimer.stop()
            }
        }
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Live Workout")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchPalette.primary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                if let kindLabel = planKindLabel {
                    WatchPlanKindChip(label: kindLabel)
                }
                Spacer(minLength: 0)
            }
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
        let currentExerciseIndex = (currentContext?.exerciseIndex).map { min($0 + 1, total) } ?? min(completed + 1, total)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(WatchDurationFormatter.format(elapsed))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text("Ex \(currentExerciseIndex)/\(total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(completed), total: Double(total))
                .progressViewStyle(.linear)
                .tint(WatchPalette.primary)
            Text("\(completed) of \(total) exercises done")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .watchCard(emphasized: true)
    }

    // MARK: - Current Block (exercise card / empty state)

    @ViewBuilder
    private var currentBlock: some View {
        if let currentContext {
            currentExerciseCard(currentContext)
        } else if hasPendingActiveWorkout {
            pendingContextCard
        } else {
            awaitingFirstSyncCard
        }
    }

    private var pendingContextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                Text("Warming Up")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(WatchPalette.primary)
            Text("Preparing first set…")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("iPhone is staging the current exercise. This card updates as soon as the first set syncs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .watchCard()
    }

    private var awaitingFirstSyncCard: some View {
        WatchEmptyStatePanel(
            systemImage: "applewatch.radiowaves.left.and.right",
            title: "Waiting on iPhone",
            message: "Start or resume a workout on iPhone to see live reps and weight here.",
            subMessage: sessionStatus.message
        )
    }

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

            if restTimer.isRunning {
                WatchRestTimerPanel(
                    timer: restTimer,
                    nextSetHint: nextSetHint(for: context),
                    onSkip: { restTimer.skip() }
                )
            } else if context.isCardio {
                cardioTarget(context)
            } else {
                WatchCrownSetLoggingControls(
                    context: context,
                    onExecutionAction: handleCrownAction
                )
            }
        }
        .watchCard()
    }

    private func cardioTarget(_ context: WatchCurrentSessionContext) -> some View {
        let targetText = context.cardioTargetSeconds.map { WatchDurationFormatter.format($0) } ?? "Open on iPhone"
        return VStack(alignment: .leading, spacing: 4) {
            Text("Target")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(targetText)
                .font(.title3.monospacedDigit().weight(.semibold))
            Button {
                onExecutionAction(
                    makeAction(.completeCardioBlock, context: context)
                )
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchPalette.primary)
            .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private var hasPendingActiveWorkout: Bool {
        liveWorkout != nil || progressSnapshot != nil
    }

    private var planKindLabel: String? {
        switch liveWorkout?.sessionPlanKind ?? currentContext?.sessionPlanKind {
        case .planned:          return "Planned"
        case .overlayAdjusted:  return "Adjusted"
        case .runtimeAdjusted:  return "Live"
        case .none:             return nil
        }
    }

    private var currentSetSignature: String {
        guard let currentContext else { return "nil" }
        let set = currentContext.currentSetNumber ?? currentContext.nextSetNumber ?? -1
        return "\(currentContext.exerciseIndex)-\(set)-\(currentContext.loggedSetsInExercise)"
    }

    private func setSummary(for context: WatchCurrentSessionContext) -> String {
        let setNumber = context.currentSetNumber ?? context.nextSetNumber
        if let setNumber, context.totalSetsInExercise > 0, !context.isCardio {
            if let summary = context.currentSetTargetSummary, !summary.isEmpty {
                return "Set \(setNumber)/\(context.totalSetsInExercise) · \(summary)"
            }
            return "Set \(setNumber) of \(context.totalSetsInExercise)"
        }
        if let summary = context.currentSetTargetSummary, !summary.isEmpty {
            return summary
        }
        return "Exercise \(context.exerciseIndex + 1) of \(context.totalExercisesInSession)"
    }

    private func nextSetHint(for context: WatchCurrentSessionContext) -> String {
        let nextSet = (context.currentSetNumber ?? context.nextSetNumber).map { $0 + 1 } ?? 0
        if context.totalSetsInExercise > 0, nextSet > 0, nextSet <= context.totalSetsInExercise {
            return "Next: Set \(nextSet) of \(context.totalSetsInExercise)"
        }
        if context.exerciseIndex + 1 < context.totalExercisesInSession {
            return "Next: Exercise \(context.exerciseIndex + 2)"
        }
        return "Last set of the session"
    }

    private func handleCrownAction(_ action: WatchWorkoutExecutionActionDTO) {
        onExecutionAction(action)
        if action.actionKind == .completeCurrentSet {
            restTimer.start(duration: WatchRestTimerDefaults.strengthSeconds)
        }
    }

    private func makeAction(
        _ kind: WatchWorkoutExecutionActionKind,
        context: WatchCurrentSessionContext,
        ticks: Int? = nil
    ) -> WatchWorkoutExecutionActionDTO {
        WatchWorkoutExecutionActionDTO(
            workoutID: context.workoutID,
            sessionVersionStableID: context.sessionVersionStableID,
            actionKind: kind,
            exerciseIndex: context.exerciseIndex,
            setNumber: context.currentSetNumber ?? context.nextSetNumber,
            ticks: ticks
        )
    }
}

// MARK: - Plan Kind Chip

struct WatchPlanKindChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(WatchPalette.primary)
            .background(WatchPalette.primary.opacity(0.22), in: Capsule())
    }
}

// MARK: - Rest Timer Panel

struct WatchRestTimerPanel: View {
    @ObservedObject var timer: WatchRestTimerController
    let nextSetHint: String
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption.weight(.semibold))
                Text("Rest")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer(minLength: 0)
                Text("\(timer.totalSeconds)s set")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(WatchPalette.primary)

            Text(countdownText)
                .font(.largeTitle.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProgressView(value: timer.progress, total: 1)
                .progressViewStyle(.linear)
                .tint(WatchPalette.primary)

            Text(nextSetHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button {
                onSkip()
            } label: {
                Label("Skip Rest", systemImage: "forward.end.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var countdownText: String {
        let seconds = max(0, timer.remainingSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Crown-first Set Logging Controls

struct WatchCrownSetLoggingControls: View {
    enum FocusedField: Hashable {
        case reps
        case weight
    }

    let context: WatchCurrentSessionContext
    let onExecutionAction: (WatchWorkoutExecutionActionDTO) -> Void

    @State private var repsValue: Double
    @State private var weightValue: Double
    @State private var lastSentRepsValue: Double
    @State private var lastSentWeightValue: Double
    @FocusState private var focusedField: FocusedField?

    init(
        context: WatchCurrentSessionContext,
        onExecutionAction: @escaping (WatchWorkoutExecutionActionDTO) -> Void = { _ in }
    ) {
        self.context = context
        self.onExecutionAction = onExecutionAction
        let initialReps = context.currentSetCompletedReps ?? context.nextPrescribedReps ?? 0
        let initialWeight = context.currentSetCompletedWeight ?? context.nextPrescribedWeight ?? 0
        _repsValue = State(initialValue: Double(initialReps))
        _weightValue = State(initialValue: initialWeight)
        _lastSentRepsValue = State(initialValue: Double(initialReps))
        _lastSentWeightValue = State(initialValue: initialWeight)
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
            .onChange(of: repsValue) { _, newValue in sendRepsDelta(newValue) }

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
            .onChange(of: weightValue) { _, newValue in sendWeightDelta(newValue) }

            Button {
                onExecutionAction(makeAction(.completeCurrentSet))
            } label: {
                Label("Complete Set", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchPalette.primary)
            .controlSize(.small)
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

    private func sendRepsDelta(_ newValue: Double) {
        let newReps = Int(newValue.rounded())
        let oldReps = Int(lastSentRepsValue.rounded())
        let ticks = newReps - oldReps
        guard ticks != 0 else { return }
        lastSentRepsValue = Double(newReps)
        onExecutionAction(
            makeAction(.applyCrownTicksToCurrentSetReps, ticks: ticks)
        )
    }

    private func sendWeightDelta(_ newValue: Double) {
        let step = max(0.1, context.crownWeightStep ?? 5)
        let ticks = Int(((newValue - lastSentWeightValue) / step).rounded())
        guard ticks != 0 else { return }
        lastSentWeightValue += Double(ticks) * step
        onExecutionAction(
            makeAction(.applyCrownTicksToCurrentSetWeight, ticks: ticks)
        )
    }

    private func makeAction(
        _ kind: WatchWorkoutExecutionActionKind,
        ticks: Int? = nil
    ) -> WatchWorkoutExecutionActionDTO {
        WatchWorkoutExecutionActionDTO(
            workoutID: context.workoutID,
            sessionVersionStableID: context.sessionVersionStableID,
            actionKind: kind,
            exerciseIndex: context.exerciseIndex,
            setNumber: context.currentSetNumber ?? context.nextSetNumber,
            ticks: ticks
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Active — Strength") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.activeCurrentContext,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active — Cardio") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.cardioCurrentContext,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active — Adjusted Session") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.adjustedLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.adjustedCurrentContext,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active — Pending Context") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: nil,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active — Idle Connection") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.activeCurrentContext,
        sessionStatus: WatchPreviewFixtures.idleStatus
    )
}
#endif
