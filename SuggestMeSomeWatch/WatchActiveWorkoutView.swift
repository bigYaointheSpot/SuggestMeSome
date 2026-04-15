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
#if canImport(WatchKit)
import WatchKit
#endif

struct WatchActiveWorkoutView: View {
    let liveWorkout: WatchLiveWorkoutSnapshot?
    let progressSnapshot: WatchWorkoutProgressSnapshot?
    let currentContext: WatchCurrentSessionContext?
    let sessionStatus: WatchCompanionSessionStatus
    var onExecutionAction: (WatchWorkoutExecutionActionDTO) -> Void = { _ in }

    @StateObject private var restTimer = WatchRestTimerController()
    @State private var displayedContext: WatchCurrentSessionContext?
    @State private var awaitingPhoneCommitContext: WatchCurrentSessionContext?
    @State private var awaitingPhoneAdvance: AwaitingPhoneAdvance?

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
        .onAppear {
            synchronizeDisplayedContext()
        }
        .onChange(of: currentContext) { _, _ in
            synchronizeDisplayedContext()
        }
        .onChange(of: liveWorkout) { _, _ in
            synchronizeDisplayedContext()
        }
        .onChange(of: restTimerSessionIdentity) { oldIdentity, newIdentity in
            guard restTimer.isRunning else { return }
            guard oldIdentity != newIdentity else { return }
            if oldIdentity != nil {
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
                .accessibilityLabel("Workout progress")
                .accessibilityValue("\(completed) of \(total) exercises complete")
            Text("\(completed) of \(total) exercises done")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .watchCard(emphasized: true)
    }

    // MARK: - Current Block (exercise card / empty state)

    @ViewBuilder
    private var currentBlock: some View {
        if let activeContext {
            currentExerciseCard(activeContext)
        } else if awaitingPhoneAdvance != nil {
            syncingCommitCard
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
                Text(setProgressSummary(for: context))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel(setAccessibilityLabel(for: context))
            }

            if restTimer.isRunning {
                WatchRestTimerPanel(
                    timer: restTimer,
                    nextSetHint: nextSetHint(for: context),
                    onSkip: { restTimer.skip() }
                )
            } else if isAwaitingPhoneCommitForCurrentSet {
                syncingCurrentSetPanel(context)
            } else if context.isCardio {
                cardioTarget(context)
            } else {
                WatchCrownSetLoggingControls(
                    context: context,
                    onExecutionAction: handleCrownAction
                )
                .id(currentSetSignature)
            }
        }
        .watchCard()
    }

    private var syncingCommitCard: some View {
        WatchEmptyStatePanel(
            systemImage: "arrow.triangle.2.circlepath",
            title: "Syncing with iPhone",
            message: "Finishing the last set. The next block appears when iPhone confirms it.",
            subMessage: sessionStatus.message
        )
    }

    private func syncingCurrentSetPanel(_ context: WatchCurrentSessionContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                Text("Syncing")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(WatchPalette.primary)

            Text(setProgressSummary(for: context))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .accessibilityLabel(setAccessibilityLabel(for: context))

            Text("iPhone is saving the last set. Next-set controls unlock as soon as it confirms.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Text(sessionStatus.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
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
                .accessibilityLabel("Cardio target")
                .accessibilityValue(targetText)
            Button {
                playActionHaptic(.success)
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
            .accessibilityHint("Marks this cardio block complete on iPhone.")
        }
    }

    // MARK: - Helpers

    private var hasPendingActiveWorkout: Bool {
        liveWorkout != nil || progressSnapshot != nil
    }

    private var planKindLabel: String? {
        switch liveWorkout?.sessionPlanKind ?? activeContext?.sessionPlanKind ?? currentContext?.sessionPlanKind {
        case .planned:          return "Planned"
        case .overlayAdjusted:  return "Adjusted"
        case .runtimeAdjusted:  return "Live"
        case .none:             return nil
        }
    }

    private var currentSetSignature: String {
        WatchCurrentSetPresentationPolicy.setSignature(for: activeContext) ?? "nil"
    }

    private var restTimerSessionIdentity: String? {
        WatchRestTimerTransitionPolicy.sessionIdentity(for: activeContext)
    }

    private var isAwaitingPhoneCommitForCurrentSet: Bool {
        guard !WatchCurrentSetPresentationPolicy.hasLiveWorkoutCaughtUp(
            liveWorkout: liveWorkout,
            to: awaitingPhoneCommitContext
        ) else {
            return false
        }
        return WatchCurrentSetPresentationPolicy.isAheadOfPhone(
            displayedContext: awaitingPhoneCommitContext,
            phoneContext: currentContext
        )
    }

    private var activeContext: WatchCurrentSessionContext? {
        if shouldSuppressCurrentContextWhileAwaitingAdvance {
            return displayedContext
        }
        return displayedContext ?? currentContext
    }

    private func setProgressSummary(for context: WatchCurrentSessionContext) -> String {
        let setNumber = context.currentSetNumber ?? context.nextSetNumber
        if let setNumber, context.totalSetsInExercise > 0, !context.isCardio {
            return "Set \(setNumber) of \(context.totalSetsInExercise)"
        }
        return "Exercise \(context.exerciseIndex + 1) of \(context.totalExercisesInSession)"
    }

    private func setAccessibilityLabel(for context: WatchCurrentSessionContext) -> String {
        if let setNumber = context.currentSetNumber ?? context.nextSetNumber,
           context.totalSetsInExercise > 0,
           !context.isCardio {
            return "Current set \(setNumber) of \(context.totalSetsInExercise)"
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
        if action.actionKind == .completeCurrentSet {
            applyLocalCompletionTransition(
                completedReps: action.completedReps,
                completedWeight: action.completedWeight
            )
            playActionHaptic(.success)
        }
        onExecutionAction(action)
        if action.actionKind == .completeCurrentSet {
            restTimer.start(duration: WatchRestTimerDefaults.strengthSeconds)
        }
    }

    private func playActionHaptic(_ type: WatchActionHaptic) {
#if canImport(WatchKit)
        switch type {
        case .success:
            WKInterfaceDevice.current().play(.success)
        }
#else
        _ = type
#endif
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

    private func synchronizeDisplayedContext() {
        if currentContext == nil && liveWorkout == nil {
            displayedContext = nil
            awaitingPhoneCommitContext = nil
            awaitingPhoneAdvance = nil
            return
        }

        if let awaitingPhoneAdvance,
           WatchCurrentSetPresentationPolicy.hasLiveWorkoutAdvancedPastCompletedExercise(
            liveWorkout: liveWorkout,
            sessionIdentity: awaitingPhoneAdvance.sessionIdentity,
            completedExerciseIndex: awaitingPhoneAdvance.completedExerciseIndex
           ) {
            self.awaitingPhoneAdvance = nil
        }

        guard let currentContext else {
            if WatchCurrentSetPresentationPolicy.hasLiveWorkoutCaughtUp(
                liveWorkout: liveWorkout,
                to: awaitingPhoneCommitContext
            ) {
                awaitingPhoneCommitContext = nil
            }
            return
        }

        if awaitingPhoneAdvance?.isSatisfied(by: currentContext) == true {
            awaitingPhoneAdvance = nil
        }

        if WatchCurrentSetPresentationPolicy.hasLiveWorkoutCaughtUp(
            liveWorkout: liveWorkout,
            to: awaitingPhoneCommitContext
        ) {
            awaitingPhoneCommitContext = nil
        } else if WatchCurrentSetPresentationPolicy.hasCaughtUp(
            phoneContext: currentContext,
            to: awaitingPhoneCommitContext
        ) {
            if awaitingPhoneCommitContext != nil {
                displayedContext = currentContext
            }
            awaitingPhoneCommitContext = nil
        }

        if awaitingPhoneCommitContext != nil {
            return
        }

        guard !shouldSuppressCurrentContextWhileAwaitingAdvance else { return }
        if displayedContext != nil,
           WatchCurrentSetPresentationPolicy.isPhoneContextStaleComparedToLiveWorkout(
            phoneContext: currentContext,
            liveWorkout: liveWorkout
           ) {
            return
        }

        guard WatchCurrentSetPresentationPolicy.shouldReplaceDisplayedContext(
            existing: displayedContext,
            incoming: currentContext
        ) else {
            if displayedContext == nil {
                displayedContext = currentContext
            }
            return
        }

        displayedContext = currentContext
    }

    private var shouldSuppressCurrentContextWhileAwaitingAdvance: Bool {
        guard let awaitingPhoneAdvance else { return false }
        return awaitingPhoneAdvance.shouldSuppress(currentContext)
    }

    private func applyLocalCompletionTransition(
        completedReps: Int?,
        completedWeight: Double?
    ) {
        guard let context = activeContext else { return }
        awaitingPhoneCommitContext = nil
        awaitingPhoneAdvance = nil

        if let nextContext = WatchCurrentSetPresentationPolicy.optimisticNextSetContext(
            afterCompleting: context,
            completedReps: completedReps,
            completedWeight: completedWeight
        ) {
            displayedContext = nextContext
            awaitingPhoneCommitContext = nextContext
            return
        }

        displayedContext = nil
        if let sessionIdentity = WatchRestTimerTransitionPolicy.sessionIdentity(for: context) {
            awaitingPhoneAdvance = AwaitingPhoneAdvance(
                sessionIdentity: sessionIdentity,
                completedExerciseIndex: context.exerciseIndex
            )
        }
    }
}

private enum WatchActionHaptic {
    case success
}

private struct AwaitingPhoneAdvance: Equatable {
    let sessionIdentity: String
    let completedExerciseIndex: Int

    func shouldSuppress(_ currentContext: WatchCurrentSessionContext?) -> Bool {
        guard let currentContext else { return false }
        return WatchRestTimerTransitionPolicy.sessionIdentity(for: currentContext) == sessionIdentity
            && currentContext.exerciseIndex <= completedExerciseIndex
    }

    func isSatisfied(by currentContext: WatchCurrentSessionContext) -> Bool {
        guard WatchRestTimerTransitionPolicy.sessionIdentity(for: currentContext) == sessionIdentity else {
            return true
        }
        return currentContext.exerciseIndex > completedExerciseIndex
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

            Button {
                onExecutionAction(
                    makeAction(
                        .completeCurrentSet,
                        completedReps: Int(repsValue.rounded()),
                        completedWeight: weightValue
                    )
                )
            } label: {
                Label("Complete Set", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchPalette.primary)
            .controlSize(.small)
            .accessibilityHint("Logs the current set on iPhone and starts a rest timer.")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
        .accessibilityHint("Double tap to focus, then turn the Digital Crown to adjust.")
    }

    private func makeAction(
        _ kind: WatchWorkoutExecutionActionKind,
        ticks: Int? = nil,
        completedReps: Int? = nil,
        completedWeight: Double? = nil
    ) -> WatchWorkoutExecutionActionDTO {
        WatchWorkoutExecutionActionDTO(
            workoutID: context.workoutID,
            sessionVersionStableID: context.sessionVersionStableID,
            actionKind: kind,
            exerciseIndex: context.exerciseIndex,
            setNumber: context.currentSetNumber ?? context.nextSetNumber,
            ticks: ticks,
            completedReps: completedReps,
            completedWeight: completedWeight
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
