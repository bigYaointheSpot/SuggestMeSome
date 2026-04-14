//
//  WatchTodayPlanView.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 3 — Polished watch Today Plan surface.
//
//  Presentational only. Consumes the iPhone-produced `WatchTodayPlanSnapshot`
//  verbatim and renders it as a premium, glanceable watch screen. Never
//  invents its own plan or coaching text.
//

import SwiftUI

struct WatchTodayPlanView: View {
    let todayPlan: WatchTodayPlanSnapshot?
    let liveWorkout: WatchLiveWorkoutSnapshot?
    let completion: WatchSessionCompletionPayload?
    let sessionStatus: WatchCompanionSessionStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let completion {
                    completionCelebration(completion)
                }

                if let liveWorkout {
                    resumeWorkoutCTA(liveWorkout)
                }

                if let todayPlan {
                    planSections(todayPlan)
                } else if completion == nil {
                    WatchEmptyStatePanel(
                        systemImage: "applewatch.radiowaves.left.and.right",
                        title: "No plan yet",
                        message: "Open SuggestMeSome on iPhone to sync today's plan.",
                        subMessage: sessionStatus.message
                    )
                }

                WatchConnectionDot(status: sessionStatus)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Plan Sections

    @ViewBuilder
    private func planSections(_ plan: WatchTodayPlanSnapshot) -> some View {
        sessionHeader(plan)
        primarySuggestionCard(plan)
        signalsRow(plan)
        if !plan.whatChangedToday.isEmpty {
            WatchWhatChangedBlock(text: plan.whatChangedToday)
        }
        if let headline = plan.adherenceHeadline, !headline.isEmpty {
            WatchAdherenceBlock(
                headline: headline,
                guidanceType: plan.adherenceGuidanceType,
                sessionsBehind: plan.sessionsBehindCount
            )
        }
        if !plan.activeSourceLabels.isEmpty {
            WatchSourceLabelsStrip(labels: plan.activeSourceLabels)
                .padding(.horizontal, 2)
        }
    }

    private func sessionHeader(_ plan: WatchTodayPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchPalette.primary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(plan.sessionLabel)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let programName = plan.programName, !programName.isEmpty {
                Text(programName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 2)
    }

    private func primarySuggestionCard(_ plan: WatchTodayPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.primarySuggestionText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            if !plan.compactSummary.isEmpty {
                Text(plan.compactSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .watchCard(emphasized: true)
    }

    private func signalsRow(_ plan: WatchTodayPlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                WatchReadinessBadge(tierLabel: plan.readinessTier, size: .small)
                WatchConfidenceBadge(confidenceLabel: plan.confidence, size: .small)
            }
            if plan.hasPainFlag {
                WatchPainFlagBadge()
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Resume CTA

    private func resumeWorkoutCTA(_ liveWorkout: WatchLiveWorkoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.semibold))
                Text("Live Workout")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(WatchPalette.primary)
            Text(liveWorkout.currentExerciseName ?? liveWorkout.sessionLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("\(liveWorkout.completedExercises) of \(liveWorkout.totalExercises) · \(WatchDurationFormatter.format(liveWorkout.elapsedSeconds))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .watchCard(emphasized: true)
    }

    // MARK: - Completion Celebration

    private func completionCelebration(_ completion: WatchSessionCompletionPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                Text("Workout Saved")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .foregroundStyle(WatchPalette.positive)
            Text(completion.sessionLabel)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("\(completion.completedExercises) of \(completion.totalExercises) exercises · \(WatchDurationFormatter.format(completion.totalElapsedSeconds))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if completion.newPersonalRecordCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.caption2)
                    Text("\(completion.newPersonalRecordCount) new PR\(completion.newPersonalRecordCount == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(WatchPalette.primary)
            }
        }
        .watchCard(emphasized: true, tint: WatchPalette.positive)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Today Plan — Normal") {
    ScrollView {
        WatchTodayPlanView(
            todayPlan: WatchPreviewFixtures.normalPlan,
            liveWorkout: nil,
            completion: nil,
            sessionStatus: WatchPreviewFixtures.reachableStatus
        )
    }
}

#Preview("Today Plan — Pain Flag") {
    ScrollView {
        WatchTodayPlanView(
            todayPlan: WatchPreviewFixtures.painFlaggedPlan,
            liveWorkout: nil,
            completion: nil,
            sessionStatus: WatchPreviewFixtures.reachableStatus
        )
    }
}

#Preview("Today Plan — Adherence Rescue") {
    ScrollView {
        WatchTodayPlanView(
            todayPlan: WatchPreviewFixtures.adherenceRescuePlan,
            liveWorkout: nil,
            completion: nil,
            sessionStatus: WatchPreviewFixtures.reachableStatus
        )
    }
}

#Preview("Today Plan — Empty") {
    ScrollView {
        WatchTodayPlanView(
            todayPlan: nil,
            liveWorkout: nil,
            completion: nil,
            sessionStatus: WatchPreviewFixtures.waitingStatus
        )
    }
}

#Preview("Today Plan — Active Workout CTA") {
    ScrollView {
        WatchTodayPlanView(
            todayPlan: WatchPreviewFixtures.normalPlan,
            liveWorkout: WatchPreviewFixtures.activeLiveWorkout,
            completion: nil,
            sessionStatus: WatchPreviewFixtures.reachableStatus
        )
    }
}

#Preview("Today Plan — Completion Celebration") {
    ScrollView {
        WatchTodayPlanView(
            todayPlan: WatchPreviewFixtures.normalPlan,
            liveWorkout: nil,
            completion: WatchPreviewFixtures.completionPayload,
            sessionStatus: WatchPreviewFixtures.reachableStatus
        )
    }
}
#endif
