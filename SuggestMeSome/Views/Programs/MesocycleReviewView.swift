//
//  MesocycleReviewView.swift
//  SuggestMeSome
//
//  Feature 13 — Post-block payoff layer. Accepts an injected MesocycleReviewSnapshot;
//  falls back to .mock if the backend is not yet wired.
//

import SwiftData
import SwiftUI

// MARK: - MesocycleReviewView

struct MesocycleReviewView: View {
    let snapshot: MesocycleReviewSnapshot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isPhaseRecapExpanded = true
    @State private var showingAIGenerator = false
    @State private var selectedRecommendation: MesocycleNextBlockRecommendation?
    @State private var confirmedPrefill: MesocycleNextBlockPrefill?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MesocycleReviewHeader(snapshot: snapshot)
                MesocycleHeadlineMetricsSection(metrics: snapshot.headlineMetrics)
                if !snapshot.performanceHighlights.isEmpty {
                    MesocycleHighlightsSection(highlights: snapshot.performanceHighlights)
                }
                if !snapshot.frictionSignals.isEmpty {
                    MesocycleFrictionSection(signals: snapshot.frictionSignals)
                }
                if !snapshot.phaseRecap.isEmpty {
                    MesocyclePhaseRecapSection(
                        phases: snapshot.phaseRecap,
                        isExpanded: $isPhaseRecapExpanded
                    )
                }
                MesocycleNarrativeSection(text: snapshot.narrativeSummary)
                MesocycleNextBlockSection(
                    recommendations: snapshot.rankedRecommendations,
                    selectedStableID: selectedRecommendation?.stableID,
                    onSelect: { selectedRecommendation = $0 }
                )
                Color.clear.frame(height: 88)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .navigationTitle("Block Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            MesocycleReviewCTABar(
                onClose: { dismiss() },
                onViewNextBlock: { primaryCTATapped() }
            )
        }
        .sheet(item: $selectedRecommendation) { rec in
            NextBlockPrefillReviewSheet(
                recommendation: rec,
                onConfirm: { editedPrefill in
                    persistDecision(
                        recommendation: rec,
                        decision: .accepted,
                        editedPrefill: editedPrefill
                    )
                    confirmedPrefill = editedPrefill
                    selectedRecommendation = nil
                    showingAIGenerator = true
                },
                onDecline: {
                    persistDecision(
                        recommendation: rec,
                        decision: .declined
                    )
                    selectedRecommendation = nil
                }
            )
        }
        .fullScreenCover(isPresented: $showingAIGenerator) {
            AIProgramGeneratorView(prefill: confirmedPrefill ?? snapshot.defaultNextBlockPrefill)
        }
    }

    private func primaryCTATapped() {
        if let first = snapshot.rankedRecommendations.first {
            selectedRecommendation = first
        } else {
            confirmedPrefill = nil
            showingAIGenerator = true
        }
    }

    private func persistDecision(
        recommendation: MesocycleNextBlockRecommendation,
        decision: MesocycleRecommendationDecision,
        editedPrefill: NextBlockPrefillContext? = nil
    ) {
        guard let sourceRun = ProgramRunContinuityService.sourceRun(
            matching: snapshot.programRunStableID,
            context: modelContext
        ) else {
            return
        }

        ProgramRunContinuityService.recordDecision(
            on: sourceRun,
            review: snapshot,
            recommendation: recommendation,
            decision: decision,
            editedPrefill: editedPrefill
        )
        try? modelContext.save()
    }
}

// MARK: - Header

private struct MesocycleReviewHeader: View {
    let snapshot: MesocycleReviewSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.programName)
                .font(.title2.weight(.bold))
            Text(dateRangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                badge("Completed", color: .green)
                if let focusName = snapshot.focusDisplayName {
                    badge(focusName, color: .teal)
                }
                badge(snapshot.inferredCurrentLevel.rawValue.capitalized, color: levelColor)
                if let model = snapshot.progressionModel {
                    badge(model.rawValue.uppercased(), color: .secondary)
                }
            }
        }
    }

    private var dateRangeText: String {
        let fmt = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(snapshot.startDate.formatted(fmt)) – \(snapshot.endDate.formatted(fmt))"
    }

    private var levelColor: Color {
        switch snapshot.inferredCurrentLevel {
        case .beginner:     return .blue
        case .intermediate: return .teal
        case .advanced:     return .purple
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Headline Metrics

private struct MesocycleMetricTile: View {
    let value: String
    let label: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MesocycleHeadlineMetricsSection: View {
    let metrics: MesocycleHeadlineMetrics

    private var avgDurationText: String {
        let mins = metrics.workoutSummary.averageDurationSeconds / 60
        return "\(mins)m"
    }

    private var adherenceColor: Color {
        metrics.adherencePercentage >= 80 ? .green : (metrics.adherencePercentage >= 60 ? .orange : .red)
    }

    var body: some View {
        HStack(spacing: 8) {
            MesocycleMetricTile(
                value: "\(metrics.adherencePercentage)%",
                label: "adherence",
                valueColor: adherenceColor
            )
            MesocycleMetricTile(
                value: "\(metrics.sessionSummary.completedSessions)/\(metrics.sessionSummary.plannedSessions)",
                label: "sessions",
                valueColor: .primary
            )
            MesocycleMetricTile(
                value: "\(metrics.personalRecordSummary.achievedSetCount)",
                label: "new PRs",
                valueColor: metrics.personalRecordSummary.achievedSetCount > 0 ? .yellow : .secondary
            )
            MesocycleMetricTile(
                value: avgDurationText,
                label: "avg session",
                valueColor: .primary
            )
        }
    }
}

// MARK: - What Improved

private struct MesocycleHighlightRow: View {
    let highlight: MesocyclePerformanceHighlight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.title)
                    .font(.subheadline.weight(.semibold))
                Text(highlight.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        switch highlight.kind {
        case .completion:          return "checkmark.circle.fill"
        case .personalRecord:      return "trophy.fill"
        case .liftMomentum:        return "arrow.up.right.circle.fill"
        case .exerciseConsistency: return "repeat.circle.fill"
        case .standaloneSupport:   return "figure.run.circle.fill"
        }
    }

    private var iconColor: Color {
        switch highlight.kind {
        case .completion:          return .green
        case .personalRecord:      return .yellow
        case .liftMomentum:        return .teal
        case .exerciseConsistency: return .blue
        case .standaloneSupport:   return .orange
        }
    }
}

private struct MesocycleHighlightsSection: View {
    let highlights: [MesocyclePerformanceHighlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            Divider().padding(.leading, 16)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<highlights.count, id: \.self) { i in
                    MesocycleHighlightRow(highlight: highlights[i])
                }
            }
            .padding(16)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.green)
            Text("What Improved")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - What Held You Back

private struct MesocycleFrictionRow: View {
    let signal: MesocycleFrictionSignal

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(severityColor)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(signal.title)
                        .font(.subheadline.weight(.semibold))
                    if signal.severity != .low {
                        Text(signal.severity.rawValue.capitalized)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(severityColor.opacity(0.15))
                            .foregroundStyle(severityColor)
                            .clipShape(Capsule())
                    }
                }
                Text(signal.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        switch signal.kind {
        case .missedPlannedSessions:  return "calendar.badge.minus"
        case .sparseProgramData:      return "questionmark.circle.fill"
        case .duplicateSessionLogs:   return "doc.on.doc.fill"
        case .longGapBetweenSessions: return "clock.badge.exclamationmark.fill"
        case .standaloneDrift:        return "arrow.triangle.2.circlepath"
        }
    }

    private var severityColor: Color {
        switch signal.severity {
        case .low:    return Color.secondary
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

private struct MesocycleFrictionSection: View {
    let signals: [MesocycleFrictionSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            Divider().padding(.leading, 16)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<signals.count, id: \.self) { i in
                    MesocycleFrictionRow(signal: signals[i])
                }
            }
            .padding(16)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text("What Held You Back")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Phase Recap

private struct MesocyclePhaseRecapSection: View {
    let phases: [MesocyclePhaseRecap]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.checkmark")
                        .foregroundStyle(.blue)
                    Text("Phase Breakdown")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.leading, 16)
                ForEach(0..<phases.count, id: \.self) { i in
                    if i > 0 { Divider().padding(.leading, 16) }
                    MesocyclePhaseRecapRow(phase: phases[i])
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MesocyclePhaseRecapRow: View {
    let phase: MesocyclePhaseRecap

    private var isFullyCompleted: Bool {
        phase.completedSessionCount >= phase.plannedSessionCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(phase.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(phase.completedSessionCount)/\(phase.plannedSessionCount)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background((isFullyCompleted ? Color.green : Color.orange).opacity(0.12))
                    .foregroundStyle(isFullyCompleted ? .green : .orange)
                    .clipShape(Capsule())
            }
            Text(phase.weekRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(phase.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Narrative Summary

private struct MesocycleNarrativeSection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.teal)
                Text("Coach Summary")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider().padding(.leading, 16)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(16)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Next Block

private struct MesocycleNextBlockSection: View {
    let recommendations: [MesocycleNextBlockRecommendation]
    let selectedStableID: String?
    let onSelect: (MesocycleNextBlockRecommendation) -> Void

    private var secondaryRecommendations: [MesocycleNextBlockRecommendation] {
        guard recommendations.count > 1 else { return [] }
        return Array(recommendations.dropFirst())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.forward.circle.fill")
                    .foregroundStyle(.teal)
                Text("What's Next")
                    .font(.headline)
                Spacer()
                if recommendations.count > 1 {
                    Text("\(recommendations.count) options")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider().padding(.leading, 16)

            if let top = recommendations.first {
                VStack(alignment: .leading, spacing: 12) {
                    NextBlockRecommendationCard(
                        recommendation: top,
                        style: .primary,
                        isSelected: selectedStableID == top.stableID,
                        onTap: { onSelect(top) }
                    )
                    if !secondaryRecommendations.isEmpty {
                        Text("More options")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        VStack(spacing: 8) {
                            ForEach(secondaryRecommendations, id: \.stableID) { rec in
                                NextBlockRecommendationCard(
                                    recommendation: rec,
                                    style: .secondary,
                                    isSelected: selectedStableID == rec.stableID,
                                    onTap: { onSelect(rec) }
                                )
                            }
                        }
                    }
                }
                .padding(16)
            } else {
                Text("Recommendations will appear here after the block is analyzed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - CTA Bar

private struct MesocycleReviewCTABar: View {
    let onClose: () -> Void
    let onViewNextBlock: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Text("Close")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
                }
                Button(action: onViewNextBlock) {
                    Text("View Next Block")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.teal)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Mock Data

extension MesocycleReviewSnapshot {
    static var mock: MesocycleReviewSnapshot {
        let now = Date()
        let start = now.addingTimeInterval(-56 * 24 * 3600)
        let sessionSummary = MesocycleSessionCompletionSummary(
            plannedSessions: 24,
            completedSessions: 21,
            uniqueCompletedSessions: 21,
            duplicateWorkoutCount: 0,
            missedSessions: 3
        )
        let workoutSummary = MesocycleWorkoutDurationSummary(
            programWorkoutCount: 21,
            standaloneWorkoutCount: 2,
            totalWorkoutCount: 23,
            totalDurationSeconds: 72000,
            averageDurationSeconds: 3120
        )
        let prSummary = MesocyclePersonalRecordSummary(
            achievedSetCount: 5,
            uniqueExerciseCount: 3,
            notableExercises: ["Squat", "Deadlift", "Bench Press"]
        )
        let consistencySummary = MesocycleExerciseConsistencySummary(
            repeatedExerciseCount: 4,
            anchorExercises: [
                MesocycleExerciseFrequency(exerciseName: "Squat", workoutCount: 18, appearancePercentage: 86),
                MesocycleExerciseFrequency(exerciseName: "Deadlift", workoutCount: 14, appearancePercentage: 67)
            ],
            summaryText: "Strong anchor consistency across primary lifts."
        )
        let standaloneInfluence = MesocycleStandaloneWorkoutInfluenceSummary(
            includedWorkoutCount: 2,
            totalDurationSeconds: 5400,
            dominantPatterns: [],
            summaryText: "2 standalone workouts supplemented the program.",
            influencePolicyText: "Included in consistency calculations."
        )
        let recInput = MesocycleRecommendationInputPayload(
            programRunStableID: "mock-run-1",
            trainingProgramStableID: "mock-program-1",
            currentFocus: .powerlifting,
            inferredCurrentLevel: .intermediate,
            progressionModel: .dup,
            sessionSummary: sessionSummary,
            workoutSummary: workoutSummary,
            personalRecordSummary: prSummary,
            exerciseConsistencySummary: consistencySummary,
            liftHighlights: [
                MesocycleLiftHighlight(
                    liftKey: "squat",
                    displayName: "Squat",
                    firstEstimatedOneRepMaxLbs: 275,
                    bestEstimatedOneRepMaxLbs: 292,
                    improvementPercentage: 6,
                    sourcedFromStandaloneWorkout: false
                )
            ],
            movementPatterns: [],
            standaloneInfluence: standaloneInfluence,
            frictionSignalKinds: [.missedPlannedSessions]
        )
        let prefill = MesocycleNextBlockPrefill(
            sourceProgramRunStableID: "mock-run-1",
            recommendationStableID: "mock-rec-1",
            focus: .powerlifting,
            level: .intermediate,
            durationWeeks: 8,
            sessionsPerWeek: 3,
            oneRepMaxSuggestions: [],
            notes: ["Carry forward new PR estimates as 1RM anchors"]
        )
        let recommendation = MesocycleNextBlockRecommendation(
            stableID: "mock-rec-1",
            rank: 1,
            kind: .consolidateFocus,
            title: "Consolidate with a Strength Block",
            summary: "Your momentum favors an 8-week strength block to lock in these new PRs.",
            rationale: [
                "New PRs suggest near-peak neurological readiness",
                "DUP experience supports higher intensity work",
                "88% adherence shows this frequency is sustainable"
            ],
            targetFocus: .powerlifting,
            targetFocusDisplayName: "Powerlifting",
            suggestedLevel: .intermediate,
            suggestedDurationWeeks: 8,
            suggestedSessionsPerWeek: 3,
            decision: .pending,
            prefill: prefill
        )
        return MesocycleReviewSnapshot(
            reviewStableID: "mock-review-1",
            programRunStableID: "mock-run-1",
            trainingProgramStableID: "mock-program-1",
            programName: "AI Powerlifting Block",
            focus: .powerlifting,
            focusDisplayName: "Powerlifting",
            inferredCurrentLevel: .intermediate,
            progressionModel: .dup,
            startDate: start,
            endDate: now,
            headlineMetrics: MesocycleHeadlineMetrics(
                sessionSummary: sessionSummary,
                adherencePercentage: 88,
                workoutSummary: workoutSummary,
                personalRecordSummary: prSummary,
                exerciseConsistencySummary: consistencySummary
            ),
            performanceHighlights: [
                MesocyclePerformanceHighlight(
                    kind: .personalRecord,
                    title: "5 New PR Sets",
                    detail: "Hit new 1RM estimates on Squat, Deadlift, and Bench Press."
                ),
                MesocyclePerformanceHighlight(
                    kind: .completion,
                    title: "88% Adherence",
                    detail: "Completed 21 of 24 planned sessions across 8 weeks."
                ),
                MesocyclePerformanceHighlight(
                    kind: .liftMomentum,
                    title: "Squat +6%",
                    detail: "Estimated 1RM climbed from 275 to 292 lbs over the block."
                )
            ],
            frictionSignals: [
                MesocycleFrictionSignal(
                    kind: .missedPlannedSessions,
                    severity: .low,
                    title: "3 Missed Sessions",
                    detail: "Clustered in Week 5. Consider scheduling a deload at that point next block."
                )
            ],
            narrativeSummary: "Strong block overall. You maintained high consistency on the primary lifts and hit new personal records at the end of the strength phase. The three missed sessions were minor and did not derail progress. Your lift momentum suggests you're ready to push intensity further — or consolidate strength gains with a focused deload before the next block.",
            phaseRecap: [
                MesocyclePhaseRecap(
                    title: "Hypertrophy Phase",
                    weekRangeText: "Weeks 1–3",
                    plannedSessionCount: 9,
                    completedSessionCount: 9,
                    summaryText: "Perfect attendance. Volume was well-tolerated across all sessions."
                ),
                MesocyclePhaseRecap(
                    title: "Strength Phase",
                    weekRangeText: "Weeks 4–6",
                    plannedSessionCount: 9,
                    completedSessionCount: 7,
                    summaryText: "Two missed sessions in Week 5. Intensity targets hit on attended days."
                ),
                MesocyclePhaseRecap(
                    title: "Peaking Phase",
                    weekRangeText: "Weeks 7–8",
                    plannedSessionCount: 6,
                    completedSessionCount: 5,
                    summaryText: "One missed session. PR attempts successful on three lifts."
                )
            ],
            standaloneInfluence: standaloneInfluence,
            recommendationInput: recInput,
            rankedRecommendations: [recommendation],
            defaultNextBlockPrefill: prefill
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MesocycleReviewView(snapshot: .mock)
    }
}
