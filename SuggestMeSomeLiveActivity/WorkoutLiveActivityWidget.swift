//
//  WorkoutLiveActivityWidget.swift
//  SuggestMeSomeLiveActivity
//
//  Lock-screen + Dynamic Island presentations for the active-workout
//  Live Activity. This file is designed to live in a dedicated iOS
//  Widget Extension target (see `docs/LIVE_ACTIVITY_SETUP.md`). The
//  target builds against the main app's WorkoutLiveActivityAttributes
//  type by adding that source file to the extension's target membership
//  in Xcode.
//
//  Kept compact on purpose — every view path reads from the
//  ContentState the main app ships; nothing here starts async work or
//  fetches data.
//

import SwiftUI
import WidgetKit
import ActivityKit

@available(iOS 16.1, *)
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            LockScreenLayout(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(.indigo.opacity(0.35))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(WorkoutLiveActivityAttributes.deepLinkURL(for: context.attributes.sessionID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LeadingExpanded(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TrailingExpanded(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    CenterExpanded(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    BottomExpanded(state: context.state)
                }
            } compactLeading: {
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
            .widgetURL(WorkoutLiveActivityAttributes.deepLinkURL(for: context.attributes.sessionID))
            .keylineTint(.indigo)
        }
    }
}

// MARK: - Lock screen

@available(iOS 16.1, *)
private struct LockScreenLayout: View {
    let attributes: WorkoutLiveActivityAttributes
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.sessionTitle, systemImage: "dumbbell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                elapsedLabel
            }
            if let currentExerciseName = state.currentExerciseName {
                Text(currentExerciseName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 12) {
                progressRing
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.completedSetCount)/\(state.totalSetCount) sets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(state.nextSetTarget ?? "All sets logged")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .padding()
    }

    private var elapsedLabel: some View {
        Group {
            if state.isPaused {
                Label(formattedPaused, systemImage: "pause.circle.fill")
            } else {
                Label {
                    Text(state.startDate, style: .timer)
                } icon: {
                    Image(systemName: "timer")
                }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .monospacedDigit()
    }

    private var formattedPaused: String {
        let minutes = state.pausedElapsedSeconds / 60
        let seconds = state.pausedElapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: state.progressFraction)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(state.progressFraction * 100))%")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Dynamic Island regions

@available(iOS 16.1, *)
private struct LeadingExpanded: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Workout")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if state.isPaused {
                Text(formattedPaused)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            } else {
                Text(state.startDate, style: .timer)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
        }
    }

    private var formattedPaused: String {
        let minutes = state.pausedElapsedSeconds / 60
        let seconds = state.pausedElapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@available(iOS 16.1, *)
private struct TrailingExpanded: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Sets")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(state.completedSetCount)/\(state.totalSetCount)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
    }
}

@available(iOS 16.1, *)
private struct CenterExpanded: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            if let name = state.currentExerciseName {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            ProgressView(value: state.progressFraction)
                .progressViewStyle(.linear)
                .tint(.indigo)
        }
        .padding(.horizontal, 8)
    }
}

@available(iOS 16.1, *)
private struct BottomExpanded: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        HStack {
            Image(systemName: "arrow.forward.circle")
                .foregroundStyle(.indigo)
            Text(state.nextSetTarget ?? "All sets logged")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
        }
    }
}

@available(iOS 16.1, *)
private struct CompactLeading: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        if let glyph = state.currentExerciseInitial {
            Text(glyph)
                .font(.caption2.weight(.bold))
                .frame(width: 16, height: 16)
                .background(Color.indigo, in: Circle())
                .foregroundStyle(.white)
        } else {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(.indigo)
        }
    }
}

@available(iOS 16.1, *)
private struct CompactTrailing: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Image(systemName: "pause.fill")
                .foregroundStyle(.orange)
        } else {
            Text(state.startDate, style: .timer)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.indigo)
        }
    }
}

@available(iOS 16.1, *)
private struct MinimalView: View {
    let state: WorkoutLiveActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.isPaused ? "pause.circle.fill" : "dumbbell.fill")
            .foregroundStyle(.indigo)
    }
}
