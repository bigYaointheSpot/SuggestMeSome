//
//  WatchRootView.swift
//  SuggestMeSomeWatch
//
//  Execution-first root flow: active workout state wins, Today Plan fills idle.
//

import SwiftUI

struct WatchRootView: View {
    @ObservedObject var store: WatchCompanionSessionStore

    var body: some View {
        NavigationStack {
            Group {
                switch store.rootMode {
                case .activeWorkout:
                    WatchActiveWorkoutView(
                        liveWorkout: store.liveWorkout,
                        progressSnapshot: store.progressSnapshot,
                        currentContext: store.currentContext
                    )
                case .todayPlan:
                    WatchTodayPlanView(
                        todayPlan: store.todayPlan,
                        completion: store.completion,
                        connectionMessage: store.connectionMessage
                    )
                }
            }
            .navigationTitle("SuggestMeSome")
        }
        .tint(.indigo)
    }
}

struct WatchActiveWorkoutView: View {
    let liveWorkout: WatchLiveWorkoutSnapshot?
    let progressSnapshot: WatchWorkoutProgressSnapshot?
    let currentContext: WatchCurrentSessionContext?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                progressSection
                if let currentContext {
                    currentSetSection(context: currentContext)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Workout Live")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text(liveWorkout?.sessionLabel ?? "Active workout")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var progressSection: some View {
        let completed = liveWorkout?.completedExercises ?? progressSnapshot?.completedExercises ?? 0
        let total = max(liveWorkout?.totalExercises ?? progressSnapshot?.totalExercises ?? 0, 1)

        return VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(completed), total: Double(total))
                .tint(.indigo)
            Text("\(completed) of \(total) exercises")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let elapsedSeconds = liveWorkout?.elapsedSeconds ?? progressSnapshot?.elapsedSeconds {
                Text(formatElapsed(elapsedSeconds))
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
        }
        .padding(10)
        .background(.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    private func currentSetSection(context: WatchCurrentSessionContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(context.exerciseName)
                .font(.headline)
                .lineLimit(2)
            Text(setSummary(for: context))
                .font(.caption)
                .foregroundStyle(.secondary)

            if context.isCardio {
                cardioTarget(context.cardioTargetSeconds)
            } else {
                CrownSetLoggingControls(context: context)
            }
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cardioTarget(_ seconds: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Target")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(seconds.map(formatElapsed) ?? "Open on iPhone")
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

    private func formatElapsed(_ seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let minutes = clampedSeconds / 60
        let seconds = clampedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct CrownSetLoggingControls: View {
    enum FocusedField {
        case reps
        case weight
    }

    let context: WatchCurrentSessionContext

    @State private var repsValue: Double
    @State private var weightValue: Double
    @FocusState private var focusedField: FocusedField?

    init(context: WatchCurrentSessionContext) {
        self.context = context
        _repsValue = State(initialValue: Double(context.currentSetCompletedReps ?? context.nextPrescribedReps ?? 0))
        _weightValue = State(initialValue: context.currentSetCompletedWeight ?? context.nextPrescribedWeight ?? 0)
    }

    var body: some View {
        VStack(spacing: 7) {
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
                through: 1000,
                by: context.crownWeightStep ?? 5,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
        }
        .onAppear {
            focusedField = .reps
        }
    }

    private var weightText: String {
        let unit = context.nextPrescribedWeightUnit ?? "lb"
        return "\(weightValue.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func crownRow(title: String, valueText: String, field: FocusedField) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.title3.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            focusedField == field ? .indigo.opacity(0.28) : .white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focusedField == field ? .indigo : .clear, lineWidth: 1)
        )
        .focusable(true)
        .focused($focusedField, equals: field)
        .onTapGesture {
            focusedField = field
        }
    }
}

struct WatchTodayPlanView: View {
    let todayPlan: WatchTodayPlanSnapshot?
    let completion: WatchSessionCompletionPayload?
    let connectionMessage: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let completion {
                    completionSummary(completion)
                }

                if let todayPlan {
                    todayPlanSummary(todayPlan)
                } else {
                    emptyState
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func completionSummary(_ completion: WatchSessionCompletionPayload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Workout Saved")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text("\(completion.completedExercises) of \(completion.totalExercises) exercises")
                .font(.caption)
                .foregroundStyle(.secondary)
            if completion.newPersonalRecordCount > 0 {
                Text("\(completion.newPersonalRecordCount) new PRs")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(10)
        .background(.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    private func todayPlanSummary(_ plan: WatchTodayPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today Plan")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text(plan.sessionLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(plan.primarySuggestionText)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                statusPill(plan.readinessTier)
                statusPill(plan.confidence)
            }
            if !plan.whatChangedToday.isEmpty {
                Text(plan.whatChangedToday)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today Plan")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text("Open SuggestMeSome on iPhone to sync today's plan.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(connectionMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.indigo.opacity(0.18), in: Capsule())
    }
}
