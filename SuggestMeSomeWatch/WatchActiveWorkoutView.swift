//
//  WatchActiveWorkoutView.swift
//  SuggestMeSomeWatch
//
//  Premium live-workout execution surface.
//
//  Consumes iPhone-produced `WatchLiveWorkoutSnapshot` and
//  `WatchCurrentSessionContext` verbatim. Layout is a horizontally paged
//  TabView (Summary / Current Set / Rest) so each screen hosts a single
//  focused surface — mirroring native Workout app direction. Elapsed time
//  ticks locally between iPhone snapshots via `TimelineView` so the wrist
//  never shows a frozen clock. Rest is its own page with a phase-tinted
//  background and the watch-local rest timer; auto-navigates on start/stop.
//

import SwiftUI
#if canImport(WatchKit)
import WatchKit
#endif

struct WatchActiveWorkoutView: View {
    let liveWorkout: WatchLiveWorkoutSnapshot?
    let progressSnapshot: WatchWorkoutProgressSnapshot?
    let currentContext: WatchCurrentSessionContext?
    let watchMetrics: WatchWorkoutMetricsPayload?
    let isLinkedHealthSessionActive: Bool
    let sessionStatus: WatchCompanionSessionStatus
    var onExecutionAction: (WatchWorkoutExecutionActionDTO) -> Void = { _ in }

    @StateObject private var restTimer = WatchRestTimerController()
    @State private var displayedContext: WatchCurrentSessionContext?
    @State private var awaitingPhoneCommitContext: WatchCurrentSessionContext?
    @State private var awaitingPhoneAdvance: AwaitingPhoneAdvance?
    @State private var selectedTab: PageTab = .currentSet

    private enum PageTab: Hashable {
        case summary
        case currentSet
        case rest
    }

    var body: some View {
        Group {
            if let activeContext {
                pagedView(activeContext)
            } else if awaitingPhoneAdvance != nil {
                fullScreenPanel {
                    WatchEmptyStatePanel(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "Syncing with iPhone",
                        message: "Finishing the last set. The next block appears when iPhone confirms it.",
                        subMessage: sessionStatus.message
                    )
                }
            } else if hasPendingActiveWorkout {
                fullScreenPanel { pendingContextCard }
            } else {
                fullScreenPanel { awaitingFirstSyncCard }
            }
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
            guard restTimer.isRunning || restTimer.isPaused else { return }
            guard oldIdentity != newIdentity else { return }
            if oldIdentity != nil {
                restTimer.stop()
            }
        }
        .onChange(of: restTimer.isRunning) { _, running in
            withAnimation(.easeInOut(duration: 0.25)) {
                if running {
                    selectedTab = .rest
                } else if selectedTab == .rest {
                    selectedTab = .currentSet
                }
            }
        }
        .onChange(of: activeLifecycleState) { _, state in
            switch state {
            case .paused:
                restTimer.pause()
            case .running:
                if restTimer.isPaused {
                    restTimer.resume()
                }
            case .none:
                break
            }
        }
    }

    // MARK: - Paged View

    private func pagedView(_ context: WatchCurrentSessionContext) -> some View {
        TabView(selection: $selectedTab) {
            summaryPage
                .tag(PageTab.summary)
            currentSetPage(context)
                .tag(PageTab.currentSet)
            restPage(context)
                .tag(PageTab.rest)
        }
        .tabViewStyle(.page)
    }

    private func fullScreenPanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sessionHeader
                content()
                WatchConnectionDot(status: sessionStatus)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Summary Page

    private var summaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sessionHeader
                elapsedAndProgress
                WatchConnectionDot(status: sessionStatus)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Current Set Page

    private func currentSetPage(_ context: WatchCurrentSessionContext) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.exerciseName)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(setProgressSummary(for: context))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel(setAccessibilityLabel(for: context))
                }
                .padding(.horizontal, 2)

                if isAwaitingPhoneCommitForCurrentSet {
                    syncingCurrentSetPanel(context)
                } else if context.lifecycleState == .paused {
                    pausedCurrentSetPanel(context)
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
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Rest Page

    private func restPage(_ context: WatchCurrentSessionContext) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if restTimer.isRunning {
                    WatchRestTimerPanel(
                        timer: restTimer,
                        nextSetHint: nextSetHint(for: context),
                        onSkip: { restTimer.skip() }
                    )
                    .watchCard(emphasized: true, tint: WatchPalette.positive)
                } else if restTimer.isPaused {
                    WatchRestTimerPanel(
                        timer: restTimer,
                        nextSetHint: nextSetHint(for: context),
                        onSkip: { restTimer.skip() }
                    )
                    .watchCard(emphasized: true, tint: WatchPalette.positive)
                } else {
                    restIdleCard(context)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .background(restBackgroundGradient)
    }

    private var restBackgroundGradient: some View {
        LinearGradient(
            colors: (restTimer.isRunning || restTimer.isPaused)
                ? [WatchPalette.positive.opacity(0.24), .clear]
                : [.clear, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 0.3), value: restTimer.isRunning || restTimer.isPaused)
        .ignoresSafeArea()
    }

    private func restIdleCard(_ context: WatchCurrentSessionContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.caption.weight(.semibold))
                Text("Next up")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(WatchPalette.primary)
            Text(nextSetHint(for: context))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let summary = context.currentSetTargetSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .watchCard(emphasized: true)
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
            if activeLifecycleState == .paused {
                Label("Paused", systemImage: "pause.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Progress (live-ticking)

    private var elapsedAndProgress: some View {
        WatchElapsedProgressCard(presentation: elapsedProgressPresentation)
    }

    private var elapsedProgressPresentation: WatchElapsedProgressPresentation {
        let completed = liveWorkout?.completedExercises ?? progressSnapshot?.completedExercises ?? 0
        let total = max(liveWorkout?.totalExercises ?? progressSnapshot?.totalExercises ?? 0, 1)
        let currentExerciseIndex = (currentContext?.exerciseIndex).map { min($0 + 1, total) } ?? min(completed + 1, total)

        return WatchElapsedProgressPresentation(
            completedExercises: completed,
            totalExercises: total,
            baseElapsedSeconds: liveWorkout?.elapsedSeconds ?? progressSnapshot?.elapsedSeconds ?? 0,
            capturedAt: liveWorkout?.capturedAt,
            currentExerciseIndex: currentExerciseIndex,
            lifecycleState: activeLifecycleState,
            heartRateBPM: watchMetrics?.heartRateBPM,
            activeEnergyKilocalories: watchMetrics?.activeEnergyKilocalories
        )
    }

    // MARK: - Fallback cards (used by fullScreenPanel)

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

    private func pausedCurrentSetPanel(_ context: WatchCurrentSessionContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                Text("Paused")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(.orange)

            Text(setProgressSummary(for: context))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if let summary = context.currentSetTargetSummary, !summary.isEmpty {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Text("Resume the workout on iPhone to keep logging sets here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)
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
                .accessibilityLabel("Cardio target")
                .accessibilityValue(targetText)
            Button {
                playActionHaptic(.success)
                onExecutionAction(
                    makeAction(.completeCardioBlock, context: context)
                )
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchPalette.primary)
            .controlSize(.regular)
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

    private var activeLifecycleState: WatchWorkoutLifecycleState? {
        activeContext?.lifecycleState ?? liveWorkout?.lifecycleState ?? currentContext?.lifecycleState
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
            restTimer.start(
                duration: WatchRestTimerDefaults.strengthSeconds,
                allowsBackgroundNotificationFallback: !isLinkedHealthSessionActive
            )
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
            .foregroundStyle(WatchPalette.positive)

            WatchRestTimerCountdown(timer: timer)

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

    static func countdownText(for seconds: Int) -> String {
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct WatchElapsedProgressPresentation: Equatable {
    let completedExercises: Int
    let totalExercises: Int
    let baseElapsedSeconds: Int
    let capturedAt: Date?
    let currentExerciseIndex: Int
    let lifecycleState: WatchWorkoutLifecycleState?
    let heartRateBPM: Double?
    let activeEnergyKilocalories: Double?

    func tickedElapsed(at date: Date) -> Int {
        guard let capturedAt else { return baseElapsedSeconds }
        guard lifecycleState != .paused else { return baseElapsedSeconds }
        let drift = max(0, date.timeIntervalSince(capturedAt))
        return baseElapsedSeconds + Int(drift.rounded())
    }

    var progressSummaryText: String {
        "\(completedExercises) of \(totalExercises) exercises done"
    }

    var accessibilityProgressValue: String {
        "\(completedExercises) of \(totalExercises) exercises complete"
    }
}

private struct WatchElapsedProgressCard: View {
    let presentation: WatchElapsedProgressPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WatchElapsedProgressHeader(presentation: presentation)
            ProgressView(value: Double(presentation.completedExercises), total: Double(presentation.totalExercises))
                .progressViewStyle(.linear)
                .tint(WatchPalette.primary)
                .accessibilityLabel("Workout progress")
                .accessibilityValue(presentation.accessibilityProgressValue)
            Text(presentation.progressSummaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if presentation.heartRateBPM != nil || presentation.activeEnergyKilocalories != nil {
                HStack(spacing: 10) {
                    if let heartRate = presentation.heartRateBPM {
                        Label("\(Int(heartRate.rounded()))", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                    }
                    if let activeEnergy = presentation.activeEnergyKilocalories {
                        Label("\(Int(activeEnergy.rounded())) kcal", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2.weight(.semibold))
            }
        }
        .watchCard(emphasized: true)
    }
}

private struct WatchElapsedProgressHeader: View {
    let presentation: WatchElapsedProgressPresentation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timelineContext in
            HStack(alignment: .firstTextBaseline) {
                Text(WatchDurationFormatter.format(presentation.tickedElapsed(at: timelineContext.date)))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("Ex \(presentation.currentExerciseIndex)/\(presentation.totalExercises)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WatchRestTimerCountdown: View {
    @ObservedObject var timer: WatchRestTimerController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remainingSeconds = timer.remainingSeconds(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                Text(WatchRestTimerPanel.countdownText(for: remainingSeconds))
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ProgressView(value: timer.progress(at: context.date), total: 1)
                    .progressViewStyle(.linear)
                    .tint(WatchPalette.positive)
            }
        }
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
        let initialReps = context.nextPrescribedReps ?? context.currentSetCompletedReps ?? 0
        let initialWeight = context.nextPrescribedWeight ?? context.currentSetCompletedWeight ?? 0
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
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchPalette.primary)
            .controlSize(.regular)
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
        let valueFont: Font = isFocused
            ? .system(size: 40, weight: .bold, design: .rounded).monospacedDigit()
            : .title3.monospacedDigit().weight(.semibold)
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isFocused ? WatchPalette.primary : .secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(valueText)
                .font(valueFont)
                .foregroundStyle(isFocused ? .primary : .secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isFocused ? 10 : 6)
        .background(
            isFocused ? WatchPalette.primary.opacity(0.28) : WatchPalette.surface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        watchMetrics: WatchPreviewFixtures.activeWatchMetrics,
        isLinkedHealthSessionActive: true,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active — Cardio") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.cardioCurrentContext,
        watchMetrics: WatchPreviewFixtures.activeWatchMetrics,
        isLinkedHealthSessionActive: true,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active — Adjusted Session") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.adjustedLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.adjustedCurrentContext,
        watchMetrics: WatchPreviewFixtures.activeWatchMetrics,
        isLinkedHealthSessionActive: true,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active — Pending Context") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: nil,
        watchMetrics: WatchPreviewFixtures.activeWatchMetrics,
        isLinkedHealthSessionActive: true,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Active — Idle Connection") {
    WatchActiveWorkoutView(
        liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
        progressSnapshot: WatchPreviewFixtures.activeProgressSnapshot,
        currentContext: WatchPreviewFixtures.activeCurrentContext,
        watchMetrics: WatchPreviewFixtures.activeWatchMetrics,
        isLinkedHealthSessionActive: false,
        sessionStatus: WatchPreviewFixtures.idleStatus
    )
}
#endif
