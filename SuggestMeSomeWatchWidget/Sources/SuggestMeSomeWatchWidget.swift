//
//  SuggestMeSomeWatchWidget.swift
//  SuggestMeSomeWatchWidget
//
//  Feature 12 Prompt 6 — Smart Stack surface.
//

import SwiftUI
import WidgetKit

struct SuggestMeSomeWatchWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchWidgetSnapshot
}

struct SuggestMeSomeWatchWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SuggestMeSomeWatchWidgetEntry {
        SuggestMeSomeWatchWidgetEntry(
            date: Date(),
            snapshot: .previewLive
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (SuggestMeSomeWatchWidgetEntry) -> Void
    ) {
        completion(
            SuggestMeSomeWatchWidgetEntry(
                date: Date(),
                snapshot: context.isPreview ? .previewToday : WatchWidgetSnapshotStore.load()
            )
        )
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SuggestMeSomeWatchWidgetEntry>) -> Void
    ) {
        let now = Date()
        let snapshot = WatchWidgetSnapshotStore.load()
        let nextRefresh: TimeInterval = snapshot.preferredSurface(now: now) == .liveWorkout ? 5 * 60 : 30 * 60
        let entry = SuggestMeSomeWatchWidgetEntry(date: now, snapshot: snapshot)
        completion(
            Timeline(
                entries: [entry],
                policy: .after(now.addingTimeInterval(nextRefresh))
            )
        )
    }
}

struct SuggestMeSomeWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SuggestMeSomeWatchWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        switch entry.snapshot.preferredSurface(now: entry.date) {
        case .liveWorkout:
            if let live = entry.snapshot.liveWorkout {
                VStack(alignment: .leading, spacing: 3) {
                    Label(planKindText(live.sessionPlanKind), systemImage: "figure.strengthtraining.traditional")
                        .font(.caption2.weight(.semibold))
                    Text(live.currentExerciseName ?? live.sessionLabel)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Ex \(min(live.completedExercises + 1, max(live.totalExercises, 1)))/\(max(live.totalExercises, 1)) · \(WidgetDurationFormatter.format(live.elapsedSeconds))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live workout")
                .accessibilityValue("\(live.currentExerciseName ?? live.sessionLabel), exercise \(min(live.completedExercises + 1, max(live.totalExercises, 1))) of \(max(live.totalExercises, 1))")
            } else {
                emptyView
            }
        case .todayPlan:
            if let plan = entry.snapshot.todayPlan {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Today", systemImage: plan.hasPainFlag ? "exclamationmark.triangle.fill" : "calendar")
                        .font(.caption2.weight(.semibold))
                    Text(plan.sessionLabel)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(plan.readinessTier) readiness · \(plan.confidence) confidence")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today plan")
                .accessibilityValue("\(plan.sessionLabel), \(plan.readinessTier) readiness, \(plan.confidence) confidence")
            } else {
                emptyView
            }
        case .empty:
            emptyView
        }
    }

    @ViewBuilder
    private var circularView: some View {
        switch entry.snapshot.preferredSurface(now: entry.date) {
        case .liveWorkout:
            if let live = entry.snapshot.liveWorkout {
                Gauge(
                    value: Double(live.completedExercises),
                    in: 0...Double(max(live.totalExercises, 1))
                ) {
                    Image(systemName: "figure.strengthtraining.traditional")
                } currentValueLabel: {
                    Text("\(min(live.completedExercises + 1, max(live.totalExercises, 1)))")
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel("Live workout progress")
                .accessibilityValue("\(live.completedExercises) of \(max(live.totalExercises, 1)) exercises complete")
            } else {
                Image(systemName: "calendar")
            }
        case .todayPlan:
            Image(systemName: entry.snapshot.todayPlan?.hasPainFlag == true ? "exclamationmark.triangle.fill" : "calendar")
                .accessibilityLabel("Today plan")
        case .empty:
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .accessibilityLabel("Waiting for iPhone sync")
        }
    }

    @ViewBuilder
    private var inlineView: some View {
        switch entry.snapshot.preferredSurface(now: entry.date) {
        case .liveWorkout:
            if let live = entry.snapshot.liveWorkout {
                Text("Live: Ex \(min(live.completedExercises + 1, max(live.totalExercises, 1)))/\(max(live.totalExercises, 1))")
            } else {
                Text("Waiting for iPhone")
            }
        case .todayPlan:
            Text("Today: \(entry.snapshot.todayPlan?.sessionLabel ?? "Plan")")
        case .empty:
            Text("Open SuggestMeSome")
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("SuggestMeSome", systemImage: "applewatch.radiowaves.left.and.right")
                .font(.caption2.weight(.semibold))
            Text("Open iPhone")
                .font(.headline)
            Text("Sync today's plan")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open SuggestMeSome on iPhone to sync today's plan.")
    }

    private func planKindText(_ kind: WatchSessionPlanKind?) -> String {
        switch kind {
        case .planned:
            return "Live planned"
        case .overlayAdjusted:
            return "Live adjusted"
        case .runtimeAdjusted:
            return "Live runtime"
        case .none:
            return "Live workout"
        }
    }
}

struct SuggestMeSomeWatchWidget: Widget {
    let kind = "SuggestMeSomeWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: SuggestMeSomeWatchWidgetProvider()
        ) { entry in
            SuggestMeSomeWatchWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("SuggestMeSome")
        .description("Today Plan when idle. Live workout progress while training.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct SuggestMeSomeWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SuggestMeSomeWatchWidget()
    }
}

private enum WidgetDurationFormatter {
    static func format(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

private extension WatchWidgetSnapshot {
    static var previewToday: WatchWidgetSnapshot {
        WatchWidgetSnapshot(
            todayPlan: WatchWidgetTodayPlanSummary(
                sessionLabel: "W2 · S1",
                primarySuggestionText: "Run the scheduled lower session.",
                compactSummary: "Strong readiness",
                readinessTier: "Strong",
                confidence: "High",
                hasPainFlag: false,
                sourceLabels: ["Manual Check-In", "Program"],
                generatedAt: Date()
            ),
            liveWorkout: nil,
            updatedAt: Date()
        )
    }

    static var previewLive: WatchWidgetSnapshot {
        WatchWidgetSnapshot(
            todayPlan: previewToday.todayPlan,
            liveWorkout: WatchWidgetLiveWorkoutSummary(
                workoutID: UUID(),
                sessionLabel: "W2 · S1",
                currentExerciseName: "Back Squat",
                currentSetSummary: "5 reps @ 225 lbs",
                elapsedSeconds: 735,
                completedExercises: 1,
                totalExercises: 4,
                completedSetsInCurrentExercise: 2,
                totalSetsInCurrentExercise: 4,
                sessionPlanKind: .planned,
                sourceLabels: ["Program"],
                sessionVersionStableID: "preview::w2s1::planned",
                capturedAt: Date()
            ),
            updatedAt: Date()
        )
    }
}
