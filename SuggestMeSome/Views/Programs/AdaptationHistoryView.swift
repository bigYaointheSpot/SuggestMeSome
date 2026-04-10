//
//  AdaptationHistoryView.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import SwiftUI
import SwiftData

/// Compact explainability surface for Feature 6 adaptation behavior.
/// Shows auditable weekly signals, proposal lifecycle, overlay application, and event reasons.
struct AdaptationHistoryView: View {
    @Bindable var run: ProgramRun

    @Query private var allAnalyses: [WeeklyTrainingAnalysis]
    @Query private var allTrendSnapshots: [LiftTrendSnapshot]
    @Query private var allProposals: [AdaptationProposal]
    @Query private var allOverlays: [AppliedProgramOverlay]
    @Query private var allEvents: [AdaptationEventHistory]

    private var analyses: [WeeklyTrainingAnalysis] {
        allAnalyses
            .filter { $0.programRun?.id == run.id }
            .sorted { lhs, rhs in
                if lhs.weekStartDate == rhs.weekStartDate {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.weekStartDate > rhs.weekStartDate
            }
    }

    private var trendSnapshots: [LiftTrendSnapshot] {
        allTrendSnapshots
            .filter { $0.programRun?.id == run.id }
            .sorted { lhs, rhs in
                if lhs.weekEndDate == rhs.weekEndDate {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.weekEndDate > rhs.weekEndDate
            }
    }

    private var latestTrendByLift: [LiftTrendSnapshot] {
        var latestByKey: [String: LiftTrendSnapshot] = [:]
        for snapshot in trendSnapshots {
            if let existing = latestByKey[snapshot.canonicalLiftKey] {
                if snapshot.weekEndDate > existing.weekEndDate {
                    latestByKey[snapshot.canonicalLiftKey] = snapshot
                }
            } else {
                latestByKey[snapshot.canonicalLiftKey] = snapshot
            }
        }
        return latestByKey.values.sorted { $0.liftDisplayName < $1.liftDisplayName }
    }

    private var proposals: [AdaptationProposal] {
        allProposals
            .filter { $0.programRun?.id == run.id }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.priority > rhs.priority
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var autoVariationSwaps: [AdaptationProposal] {
        proposals.filter {
            $0.proposalType == .variationSwap &&
            ($0.proposalStatus == .autoApplied || $0.autoApplyEligible)
        }
    }

    private var overlays: [AppliedProgramOverlay] {
        allOverlays
            .filter { $0.programRun?.id == run.id }
            .sorted { $0.appliedAt > $1.appliedAt }
    }

    private var events: [AdaptationEventHistory] {
        allEvents
            .filter { $0.programRun?.id == run.id }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        List {
            if analyses.isEmpty && proposals.isEmpty && overlays.isEmpty && events.isEmpty {
                ContentUnavailableView(
                    "No Adaptive History",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("Complete program sessions to generate analyses, proposals, overlays, and explainable adaptation events.")
                )
                .listRowBackground(Color.clear)
            } else {
                weeklyAnalysisSection
                liftTrendSection
                proposalSection
                automaticSwapSection
                overlaySection
                eventTimelineSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Adaptation History")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private var weeklyAnalysisSection: some View {
        Section("Recent Weekly Analyses") {
            ForEach(Array(analyses.prefix(8))) { analysis in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(weekLabel(for: analysis))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        fatigueBadge(analysis.fatigueStatus)
                    }

                    Text("Performance: \(signedScoreText(analysis.weightedPerformanceScore))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Workouts: \(analysis.programWorkoutCount) program, \(analysis.standaloneWorkoutCount) standalone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var liftTrendSection: some View {
        Section("Lift Trends") {
            if latestTrendByLift.isEmpty {
                Text("No lift trends yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(latestTrendByLift) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(snapshot.liftDisplayName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            trendBadge(snapshot.trendStatus)
                        }

                        let changeText = snapshot.changePercent.map { fmtPercent($0 / 100.0) } ?? "n/a"
                        Text("4-week change: \(changeText) · confidence \(fmtPercent(snapshot.confidenceScore))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Fatigue: \(fatigueLabel(snapshot.fatigueStatus))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var proposalSection: some View {
        Section("Adaptation Proposals") {
            if proposals.isEmpty {
                Text("No proposals yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(proposals.prefix(16))) { proposal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(proposalTypeLabel(proposal.proposalType))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            statusBadge(proposal.proposalStatus)
                        }

                        Text(proposal.summaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Reason: \(reasonText(proposal.adjustmentReason)) · Target \(proposalTargetText(proposal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var automaticSwapSection: some View {
        Section("Automatic Variation Swaps") {
            if autoVariationSwaps.isEmpty {
                Text("No automatic variation swaps applied.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(autoVariationSwaps.prefix(10))) { proposal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Week \(proposal.targetWeekStart)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            statusBadge(proposal.proposalStatus)
                        }

                        Text("\(proposal.swapFromExerciseName ?? "lift") -> \(proposal.swapToExerciseName ?? "variation")")
                            .font(.caption)
                            .foregroundStyle(.primary)

                        Text("Why: \(reasonText(proposal.adjustmentReason))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var overlaySection: some View {
        Section("Applied Overlays") {
            if overlays.isEmpty {
                Text("No overlays applied yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(overlays.prefix(16))) { overlay in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(overlay.summaryText ?? "Overlay")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            overlayBadge(overlay.overlayStatus)
                        }

                        Text("Effective: \(weekRangeText(start: overlay.effectiveWeekStart, end: overlay.effectiveWeekEnd))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Adjustments: \(overlay.adjustments.count) · \(overlayOriginText(overlay))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var eventTimelineSection: some View {
        Section("Adaptation Event Timeline") {
            if events.isEmpty {
                Text("No adaptation events yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(Array(events.prefix(30))) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(eventTypeLabel(event.eventType))
                                    .font(.subheadline.weight(.semibold))
                                Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let reason = event.adjustmentReason {
                                reasonBadge(reason)
                            }
                        }

                        Text(event.message)
                            .font(.caption)
                            .foregroundStyle(.primary)

                        if let explanation = event.explanation, !explanation.isEmpty {
                            Text(userFacingExplanation(from: explanation))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: Formatting Helpers

    private func weekLabel(for analysis: WeeklyTrainingAnalysis) -> String {
        if let programWeek = analysis.programWeekNumber {
            return "Week \(programWeek) · \(analysis.weekStartDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return analysis.weekStartDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func weekRangeText(start: Int, end: Int?) -> String {
        let end = max(start, end ?? start)
        if start == end { return "Week \(start)" }
        return "Weeks \(start)-\(end)"
    }

    private func proposalTargetText(_ proposal: AdaptationProposal) -> String {
        if let session = proposal.targetSessionNumber {
            return "Week \(proposal.targetWeekStart), Session \(session)"
        }
        return weekRangeText(start: proposal.targetWeekStart, end: proposal.targetWeekEnd)
    }

    private func overlayOriginText(_ overlay: AppliedProgramOverlay) -> String {
        overlay.appliedByUserConfirmation ? "user-confirmed" : "automatic"
    }

    private func topSetText(_ snapshot: LiftTrendSnapshot) -> String {
        guard let load = snapshot.latestTopSetWeight,
              let reps = snapshot.latestTopSetReps else {
            return "n/a"
        }
        return "\(fmt1(load)) x \(reps)"
    }

    private func userFacingExplanation(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if let sentence = trimmed.split(separator: ";").first {
            return String(sentence)
        }
        return trimmed
    }

    private func signedScoreText(_ score: Double) -> String {
        if score >= 0 {
            return String(format: "+%.1f", score)
        }
        return String(format: "%.1f", score)
    }

    private func fmt1(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func fmt2(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.2f", value)
    }

    private func fmtPercent(_ value: Double) -> String {
        let percent = value * 100
        if percent >= 0 {
            return String(format: "+%.0f%%", percent)
        }
        return String(format: "%.0f%%", percent)
    }

    // MARK: Badge Views

    @ViewBuilder
    private func fatigueBadge(_ status: FatigueStatus) -> some View {
        Text(fatigueLabel(status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fatigueColor(status).opacity(0.2))
            .foregroundStyle(fatigueColor(status))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func trendBadge(_ status: LiftTrendStatus) -> some View {
        Text(trendLabel(status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(trendColor(status).opacity(0.2))
            .foregroundStyle(trendColor(status))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func statusBadge(_ status: ProposalStatus) -> some View {
        Text(proposalStatusLabel(status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(proposalStatusColor(status).opacity(0.2))
            .foregroundStyle(proposalStatusColor(status))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func overlayBadge(_ status: OverlayStatus) -> some View {
        Text(overlayStatusLabel(status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(overlayStatusColor(status).opacity(0.2))
            .foregroundStyle(overlayStatusColor(status))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func reasonBadge(_ reason: AdjustmentReason) -> some View {
        Text(reasonText(reason))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.12))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
            .lineLimit(1)
    }

    // MARK: Labels + Colors

    private func fatigueLabel(_ status: FatigueStatus) -> String {
        switch status {
        case .low: return "Low Fatigue"
        case .manageable: return "Manageable"
        case .elevated: return "Elevated"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    private func fatigueColor(_ status: FatigueStatus) -> Color {
        switch status {
        case .low: return .green
        case .manageable: return .blue
        case .elevated: return .orange
        case .high: return .red
        case .critical: return .pink
        }
    }

    private func trendLabel(_ status: LiftTrendStatus) -> String {
        switch status {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        case .volatile: return "Volatile"
        case .insufficientData: return "Insufficient"
        }
    }

    private func trendColor(_ status: LiftTrendStatus) -> Color {
        switch status {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .red
        case .volatile: return .orange
        case .insufficientData: return .gray
        }
    }

    private func proposalTypeLabel(_ type: ProposalType) -> String {
        switch type {
        case .increaseLoad: return "Load Increase"
        case .decreaseLoad: return "Load Decrease"
        case .increaseVolume: return "Volume Increase"
        case .decreaseVolume: return "Volume Decrease"
        case .deload: return "Deload"
        case .variationSwap: return "Variation Swap"
        }
    }

    private func proposalStatusLabel(_ status: ProposalStatus) -> String {
        switch status {
        case .draft: return "Draft"
        case .pendingUserConfirmation: return "Pending User"
        case .pendingAutoApply: return "Pending Auto"
        case .confirmed: return "Approved"
        case .rejected: return "Rejected"
        case .autoApplied: return "Auto Applied"
        case .expired: return "Expired"
        case .superseded: return "Superseded"
        }
    }

    private func proposalStatusColor(_ status: ProposalStatus) -> Color {
        switch status {
        case .draft: return .gray
        case .pendingUserConfirmation, .pendingAutoApply: return .orange
        case .confirmed, .autoApplied: return .green
        case .rejected: return .red
        case .expired, .superseded: return .secondary
        }
    }

    private func overlayStatusLabel(_ status: OverlayStatus) -> String {
        switch status {
        case .active: return "Active"
        case .superseded: return "Superseded"
        case .reverted: return "Reverted"
        case .expired: return "Expired"
        }
    }

    private func overlayStatusColor(_ status: OverlayStatus) -> Color {
        switch status {
        case .active: return .green
        case .superseded: return .orange
        case .reverted: return .red
        case .expired: return .secondary
        }
    }

    private func eventTypeLabel(_ type: AdaptationEventType) -> String {
        switch type {
        case .weeklyAnalysisFinalized: return "Weekly Analysis"
        case .trendUpdated: return "Trend Update"
        case .proposalCreated: return "Proposal Created"
        case .proposalConfirmed: return "Proposal Approved"
        case .proposalRejected: return "Proposal Rejected"
        case .overlayApplied: return "Overlay Applied"
        case .overlaySuperseded: return "Overlay Superseded"
        }
    }

    private func reasonText(_ reason: AdjustmentReason) -> String {
        switch reason {
        case .topSetBeatTarget: return "Top-set beat target"
        case .topSetMissedTarget: return "Top-set missed target"
        case .accessoryOutperformance: return "Accessory ahead"
        case .accessoryUnderperformance: return "Accessory behind"
        case .fatigueAccumulation: return "Fatigue accumulation"
        case .fatigueResolved: return "Fatigue resolved"
        case .positiveLiftTrend: return "Positive lift trend"
        case .negativeLiftTrend: return "Negative lift trend"
        case .plateauDetected: return "Plateau detected"
        case .lowAdherence: return "Low adherence"
        case .standaloneTrendSupport: return "Standalone support"
        case .programSignalPriority: return "Program signal priority"
        }
    }
}
