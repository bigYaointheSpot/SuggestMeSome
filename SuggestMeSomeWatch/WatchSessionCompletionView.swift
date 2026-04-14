//
//  WatchSessionCompletionView.swift
//  SuggestMeSomeWatch
//
//  Feature 12 Prompt 5 — Polished session completion moment.
//
//  Presented when the iPhone sends a `sessionCompletion` payload. Kept
//  subtle and premium — a single hero card with set/exercise totals,
//  elapsed time, PR count when present, and a "Back to Today" action
//  that lets the user glance at their Today Plan again.
//

import SwiftUI

struct WatchSessionCompletionView: View {
    let completion: WatchSessionCompletionPayload
    let sessionStatus: WatchCompanionSessionStatus
    var onDismiss: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                hero
                metricsRow
                if completion.newPersonalRecordCount > 0 {
                    prBanner
                }
                if let labels = completion.sessionSourceLabels, !labels.isEmpty {
                    WatchSourceLabelsStrip(labels: labels)
                        .padding(.horizontal, 2)
                }
                Button {
                    onDismiss()
                } label: {
                    Label("Back to Today", systemImage: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                WatchConnectionDot(status: sessionStatus)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Components

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                Text("Workout Saved")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .foregroundStyle(WatchPalette.positive)
            Text(completion.sessionLabel)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 2)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WatchDurationFormatter.format(completion.totalElapsedSeconds))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Text("Total time")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .watchCard(emphasized: true, tint: WatchPalette.positive)
    }

    private var metricsRow: some View {
        HStack(spacing: 6) {
            metricTile(
                value: "\(completion.completedExercises)/\(completion.totalExercises)",
                label: "Exercises"
            )
            metricTile(
                value: "\(completion.completedSets)/\(completion.totalSets)",
                label: "Sets"
            )
        }
    }

    private func metricTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(WatchPalette.strokeFaint, lineWidth: 0.5)
        )
    }

    private var prBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.caption.weight(.semibold))
            Text("\(completion.newPersonalRecordCount) new PR\(completion.newPersonalRecordCount == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(WatchPalette.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(WatchPalette.primary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(WatchPalette.primary.opacity(0.4), lineWidth: 0.5)
        )
    }
}

#if DEBUG
#Preview("Completion — With PRs") {
    WatchSessionCompletionView(
        completion: WatchPreviewFixtures.completionPayload,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}

#Preview("Completion — No PRs") {
    WatchSessionCompletionView(
        completion: WatchPreviewFixtures.completionPayloadNoPR,
        sessionStatus: WatchPreviewFixtures.reachableStatus
    )
}
#endif
