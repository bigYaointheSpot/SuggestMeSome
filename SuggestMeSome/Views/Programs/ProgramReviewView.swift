//
//  ProgramReviewView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/7/26.
//

import SwiftUI
import SwiftData

// MARK: - Review Phase Group

struct ReviewPhaseGroup: Identifiable {
    let id: String   // stable: derived from title so re-renders don't break expansion state
    let title: String
    let weekRange: String
    let schemeDescription: String
    var weeks: [ProgramWeekTemplate]
    let isDeload: Bool
}

private struct ProgramLogicSnapshot {
    let progressionModel: String
    let usedLiftMapping: Bool
    let usedVolumeBalancing: Bool
    let usedFatigueBalancing: Bool
    let usedTopSetBackoff: Bool
}

// MARK: - Phase Helpers

private func buildPhaseGroups(
    input: ProgramGenerationInput,
    weeks: [ProgramWeekTemplate]
) -> [ReviewPhaseGroup] {
    let sorted = weeks.sorted { $0.weekNumber < $1.weekNumber }
    switch input.level {
    case .beginner, .intermediate:
        let isDeload: (ProgramWeekTemplate) -> Bool = { week in
            week.isDeloadWeek
        }
        let workingWeeks = sorted.filter { !isDeload($0) }
        let deloadWeeks  = sorted.filter(isDeload)
        let scheme = input.level == .beginner
            ? "Linear: template-anchor %1RM with small weekly increases"
            : "DUP: heavy/moderate/light anchor-relative intensity shifts"
        var groups = [
            ReviewPhaseGroup(
                id: "working",
                title: "Working Weeks",
                weekRange: weekRangeText(workingWeeks.isEmpty ? sorted : workingWeeks),
                schemeDescription: scheme,
                weeks: workingWeeks.isEmpty ? sorted : workingWeeks,
                isDeload: false
            )
        ]
        if !deloadWeeks.isEmpty {
            groups.append(ReviewPhaseGroup(
                id: "deload",
                title: "Deload Weeks",
                weekRange: weekRangeText(deloadWeeks),
                schemeDescription: "Reduced volume (~50%) with explicit intensity drop",
                weeks: deloadWeeks,
                isDeload: true
            ))
        }
        return groups

    case .advanced:
        return buildBlockPhaseGroups(durationWeeks: input.durationWeeks, weeks: sorted)
    }
}

private func buildBlockPhaseGroups(
    durationWeeks: Int,
    weeks: [ProgramWeekTemplate]
) -> [ReviewPhaseGroup] {
    let sequence: [(String?, Int)]
    switch durationWeeks {
    case 6:  sequence = [("Hypertrophy", 2), (nil, 1), ("Strength", 2), ("Peaking", 1)]
    case 8:  sequence = [("Hypertrophy", 3), (nil, 1), ("Strength", 2), ("Peaking", 1), (nil, 1)]
    case 10: sequence = [("Hypertrophy", 3), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2)]
    case 12: sequence = [("Hypertrophy", 4), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2), (nil, 1)]
    default: sequence = [("Hypertrophy", 4), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2), (nil, 1)]
    }

    var groups: [ReviewPhaseGroup] = []
    var weekIdx = 1
    for (name, count) in sequence {
        let phaseWeeks = weeks.filter { $0.weekNumber >= weekIdx && $0.weekNumber < weekIdx + count }
        let range = count == 1
            ? "Week \(weekIdx)"
            : "Weeks \(weekIdx)–\(weekIdx + count - 1)"

        if let phaseName = name {
            let scheme: String
            switch phaseName {
            case "Hypertrophy": scheme = "Anchor-relative lower intensity accumulation"
            case "Strength":    scheme = "Anchor-relative strength intensification"
            case "Peaking":     scheme = "Anchor-relative high-intensity peaking"
            default:            scheme = ""
            }
            groups.append(ReviewPhaseGroup(
                id: phaseName.lowercased(),
                title: "\(phaseName) Phase",
                weekRange: range,
                schemeDescription: scheme,
                weeks: phaseWeeks,
                isDeload: false
            ))
        } else {
            // Multiple deload groups possible; make ID unique by week index
            groups.append(ReviewPhaseGroup(
                id: "deload-\(weekIdx)",
                title: "Deload",
                weekRange: range,
                schemeDescription: "Reduced volume (~50%) with explicit intensity drop",
                weeks: phaseWeeks,
                isDeload: true
            ))
        }
        weekIdx += count
    }
    return groups
}

private func weekRangeText(_ weeks: [ProgramWeekTemplate]) -> String {
    let nums = weeks.map(\.weekNumber).sorted()
    guard !nums.isEmpty else { return "" }
    if nums.count == 1 { return "Week \(nums[0])" }

    var ranges: [ClosedRange<Int>] = []
    var start = nums[0], end = nums[0]
    for n in nums.dropFirst() {
        if n == end + 1 { end = n } else { ranges.append(start...end); start = n; end = n }
    }
    ranges.append(start...end)

    return ranges.map { r in
        r.lowerBound == r.upperBound
            ? "Week \(r.lowerBound)"
            : "Weeks \(r.lowerBound)–\(r.upperBound)"
    }.joined(separator: ", ")
}

private func resolvedOneRepMax(
    for exerciseName: String,
    oneRepMaxes: [String: (weight: Double, unit: String)]
) -> (weight: Double, unit: String)? {
    if let direct = oneRepMaxes[exerciseName] {
        return direct
    }

    guard
        let mapping = FocusTemplateLibrary.loadMapping(for: exerciseName),
        let sourceORM = oneRepMaxes[mapping.sourceLift]
    else {
        return nil
    }

    return (
        weight: sourceORM.weight * mapping.multiplier,
        unit: sourceORM.unit
    )
}

// MARK: - Exercise Display Helper

private func exerciseDisplayText(
    exercise: ProgramSessionExercise,
    oneRepMaxes: [String: (weight: Double, unit: String)]
) -> String {
    // Cardio: no targetSets, targetReps holds duration in minutes
    if exercise.targetSets == nil, let mins = exercise.targetReps {
        return "\(mins) min"
    }

    let sStr = exercise.targetSets.map(String.init) ?? "—"
    let rStr = exercise.targetReps.map(String.init) ?? "—"

    if let pct = exercise.targetPercentage1RM {
        let pctInt = Int((pct * 100).rounded())

        // Prefer weight stored at generation time
        if let w = exercise.prescribedWeight, let unit = exercise.prescribedWeightUnit {
            let wStr = w == w.rounded(.towardZero)
                ? "\(Int(w)) \(unit)"
                : String(format: "%.1f \(unit)", w)
            var detail = "\(sStr)×\(rStr) @ \(wStr) (\(pctInt)%)"
            if let rir = exercise.targetRIR {
                let rirStr = rir.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(rir))
                    : String(format: "%.1f", rir)
                detail += " · RIR \(rirStr)"
            } else if let rpe = exercise.targetRPE {
                let rpeStr = rpe.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(rpe))
                    : String(format: "%.1f", rpe)
                detail += " · RPE \(rpeStr)"
            }
            if exercise.workingSetStyle == .backoff, let drop = exercise.backoffPercentageDrop {
                detail += String(format: " · -%.0f%%", drop * 100.0)
            }
            return detail
        }

        // Fallback: compute from oneRepMaxes (programs generated before fix)
        // Supports mapped variation lifts when direct 1RM is unavailable.
        if let orm = resolvedOneRepMax(for: exercise.exerciseName, oneRepMaxes: oneRepMaxes) {
            let raw = pct * orm.weight
            let rounded = orm.unit == "lbs"
                ? (raw / 5.0).rounded() * 5.0
                : (raw / 2.5).rounded() * 2.5
            let wStr = rounded == rounded.rounded(.towardZero)
                ? "\(Int(rounded)) \(orm.unit)"
                : String(format: "%.1f \(orm.unit)", rounded)
            var detail = "\(sStr)×\(rStr) @ \(wStr) (\(pctInt)%)"
            if let rir = exercise.targetRIR {
                let rirStr = rir.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(rir))
                    : String(format: "%.1f", rir)
                detail += " · RIR \(rirStr)"
            } else if let rpe = exercise.targetRPE {
                let rpeStr = rpe.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(rpe))
                    : String(format: "%.1f", rpe)
                detail += " · RPE \(rpeStr)"
            }
            if exercise.workingSetStyle == .backoff, let drop = exercise.backoffPercentageDrop {
                detail += String(format: " · -%.0f%%", drop * 100.0)
            }
            return detail
        }
        var detail = "\(sStr)×\(rStr) @ \(pctInt)%"
        if let rir = exercise.targetRIR {
            let rirStr = rir.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(rir))
                : String(format: "%.1f", rir)
            detail += " · RIR \(rirStr)"
        } else if let rpe = exercise.targetRPE {
            let rpeStr = rpe.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(rpe))
                : String(format: "%.1f", rpe)
            detail += " · RPE \(rpeStr)"
        }
        if exercise.workingSetStyle == .backoff, let drop = exercise.backoffPercentageDrop {
            detail += String(format: " · -%.0f%%", drop * 100.0)
        }
        return detail
    }

    if let rir = exercise.targetRIR {
        let rirStr = rir.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rir))
            : String(format: "%.1f", rir)
        return "\(sStr)×\(rStr) @ RIR \(rirStr)"
    }

    if let rpe = exercise.targetRPE {
        let rpeStr = rpe.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rpe))
            : String(format: "%.1f", rpe)
        return "\(sStr)×\(rStr) @ RPE \(rpeStr)"
    }

    return "\(sStr)×\(rStr)"
}

private func workingSetStyleLabel(for exercise: ProgramSessionExercise) -> String {
    if exercise.targetSets == nil { return "Cardio" }
    switch exercise.workingSetStyle {
    case .topSet: return "Top Set"
    case .backoff: return "Backoff"
    case .straight, .none: return "Straight Sets"
    }
}

private func workingSetStyleColor(for exercise: ProgramSessionExercise) -> Color {
    if exercise.targetSets == nil { return .green }
    switch exercise.workingSetStyle {
    case .topSet: return .indigo
    case .backoff: return .blue
    case .straight, .none: return .secondary
    }
}

private func exercisePurposeLabel(for exercise: ProgramSessionExercise) -> String? {
    exercise.explainabilityPurpose?.shortLabel
}

private func exerciseSelectionReasonLabel(for exercise: ProgramSessionExercise) -> String? {
    exercise.explainabilitySelectionReason?.shortLabel
}

// MARK: - ProgramReviewView

struct ProgramReviewView: View {
    let program: TrainingProgram
    let input: ProgramGenerationInput
    let onStartProgram: () -> Void
    let onRegenerate: () -> Void

    @Environment(\.modelContext) private var modelContext
    private let generationService = ProgramGenerationService()

    @State private var editableName: String = ""
    @State private var isEditingName = false
    @State private var expandedPhaseIDs: Set<String> = []
    @State private var expandedWeeks: Set<Int> = []
    @State private var expandedSessions: Set<String> = []

    @State private var editingExercise: ProgramSessionExercise?
    @State private var addingToSession: ProgramSessionTemplate?
    @State private var showRegenerateAlert = false
    @State private var showAdditionalInfo = false

    private var groups: [ReviewPhaseGroup] {
        buildPhaseGroups(input: input, weeks: program.weeks)
    }

    private var weeklySummariesByWeek: [Int: ProgramGeneratedWeekSummary] {
        Dictionary(
            uniqueKeysWithValues: generationService.weeklySummary(for: program).map { ($0.weekNumber, $0) }
        )
    }

    private var programLogic: ProgramLogicSnapshot {
        let mapped = program.usedLiftMapping
            ?? program.weeks.flatMap(\.sessions).flatMap(\.exercises).contains { $0.usedMappedSourceLift == true }
        let topBackoff = program.usedTopSetBackoff
            ?? program.weeks.flatMap(\.sessions).flatMap(\.exercises).contains {
                $0.workingSetStyle == .topSet || $0.workingSetStyle == .backoff
            }
        let progressionName = (program.progressionModel ?? fallbackProgressionModel).displayName

        return ProgramLogicSnapshot(
            progressionModel: progressionName,
            usedLiftMapping: mapped,
            usedVolumeBalancing: program.usedVolumeBalancing ?? true,
            usedFatigueBalancing: program.usedFatigueBalancing ?? true,
            usedTopSetBackoff: topBackoff
        )
    }

    private var fallbackProgressionModel: ProgramProgressionModel {
        switch input.level {
        case .beginner: return .linear
        case .intermediate: return .dup
        case .advanced: return .block
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryHeaderView
                    .padding()
                Divider()
                phaseListView
                    .padding(.bottom, 96)
            }
        }
        .safeAreaInset(edge: .bottom) { actionBarView }
        .onAppear { editableName = program.name }
        .alert("Regenerate Program?", isPresented: $showRegenerateAlert) {
            Button("Regenerate", role: .destructive) { onRegenerate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will discard your edits. Regenerate?")
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseEditSheet(exercise: exercise, input: input)
        }
        .sheet(item: $addingToSession) { session in
            ReviewExercisePickerSheet { exerciseName in
                addExercise(named: exerciseName, to: session)
            }
        }
    }

    // MARK: Summary Header

    @ViewBuilder
    private var summaryHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Program name (editable)
            HStack(alignment: .center, spacing: 8) {
                if isEditingName {
                    TextField("Program Name", text: $editableName)
                        .font(.title2.weight(.bold))
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit { commitName() }
                } else {
                    Text(editableName.isEmpty ? program.name : editableName)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                }
                Button(action: {
                    if isEditingName { commitName() } else { isEditingName = true }
                }) {
                    Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil")
                        .foregroundStyle(.teal)
                        .font(.subheadline)
                }
            }

            // Metadata badges
            HStack(spacing: 8) {
                levelBadge
                Text("\(input.durationWeeks) weeks")
                    .badgeStyle()
                Text("\(program.sessionsPerWeek)/week")
                    .badgeStyle()
            }

            HStack(spacing: 8) {
                Text("Show Additional Info")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $showAdditionalInfo)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.85)
            }

            if showAdditionalInfo {
                programLogicSection
            }

            // Periodization description
            if let desc = program.descriptionText {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Block phase breakdown
            if input.level == .advanced {
                Text(blockBreakdownText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var programLogicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Program Logic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                logicRow("Progression", value: programLogic.progressionModel)
                logicRow("Lift Mapping", value: boolLabel(programLogic.usedLiftMapping))
                logicRow("Volume Balance", value: boolLabel(programLogic.usedVolumeBalancing))
                logicRow("Fatigue Balance", value: boolLabel(programLogic.usedFatigueBalancing))
                logicRow("Top+Backoff", value: boolLabel(programLogic.usedTopSetBackoff))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func logicRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func boolLabel(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private var levelBadge: some View {
        let (label, color): (String, Color) = {
            switch input.level {
            case .beginner:     return ("Beginner", .green)
            case .intermediate: return ("Intermediate", .orange)
            case .advanced:     return ("Advanced", .purple)
            }
        }()
        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var blockBreakdownText: String {
        let sequence: [(String?, Int)]
        switch input.durationWeeks {
        case 6:  sequence = [("Hypertrophy", 2), (nil, 1), ("Strength", 2), ("Peaking", 1)]
        case 8:  sequence = [("Hypertrophy", 3), (nil, 1), ("Strength", 2), ("Peaking", 1), (nil, 1)]
        case 10: sequence = [("Hypertrophy", 3), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2)]
        case 12: sequence = [("Hypertrophy", 4), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2), (nil, 1)]
        default: sequence = [("Hypertrophy", 4), (nil, 1), ("Strength", 3), (nil, 1), ("Peaking", 2), (nil, 1)]
        }
        var parts: [String] = []
        var w = 1
        for (name, count) in sequence {
            let range = count == 1 ? "Week \(w)" : "Weeks \(w)–\(w + count - 1)"
            parts.append("\(range): \(name ?? "Deload")")
            w += count
        }
        return parts.joined(separator: " → ")
    }

    // MARK: Phase List

    private var phaseListView: some View {
        VStack(spacing: 0) {
            ForEach(groups) { group in
                PhaseCardView(
                    group: group,
                    isExpanded: expandedPhaseIDs.contains(group.id),
                    showAdditionalInfo: showAdditionalInfo,
                    expandedWeeks: $expandedWeeks,
                    expandedSessions: $expandedSessions,
                    editingExercise: $editingExercise,
                    addingToSession: $addingToSession,
                    weeklySummariesByWeek: weeklySummariesByWeek,
                    input: input,
                    onTogglePhase: { togglePhase(id: group.id) },
                    onDeleteExercise: deleteExercise
                )
                Divider()
            }
        }
    }

    // MARK: Action Bar

    private var actionBarView: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: { showRegenerateAlert = true }) {
                    Text("Regenerate")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
                }

                Button(action: startProgram) {
                    Text("Start Program")
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

    // MARK: Actions

    private func commitName() {
        program.name = editableName.isEmpty ? program.name : editableName
        isEditingName = false
    }

    private func togglePhase(id: String) {
        if expandedPhaseIDs.contains(id) { expandedPhaseIDs.remove(id) }
        else { expandedPhaseIDs.insert(id) }
    }

    private func startProgram() {
        commitName()
        let startDate = Date.now
        let run = ProgramRun(startDate: startDate)
        run.program = program

        if let sourceStableID = input.carryForwardContext?.sourceProgramRunStableID {
            let sourceRun = ProgramRunContinuityService.sourceRun(
                matching: sourceStableID,
                context: modelContext
            )
            ProgramRunContinuityService.applyAcceptedContinuity(
                to: run,
                sourceRun: sourceRun,
                input: input,
                startedAt: startDate
            )
        }

        modelContext.insert(run)
        try? modelContext.save()
        onStartProgram()
    }

    private func addExercise(named name: String, to session: ProgramSessionTemplate) {
        let nextOrder = (session.exercises.map(\.orderIndex).max() ?? -1) + 1
        let ex = ProgramSessionExercise(
            exerciseName: name,
            orderIndex: nextOrder,
            targetSets: 3,
            targetReps: 8,
            targetRPE: 7.0,
            targetEffortType: .rpe
        )
        modelContext.insert(ex)
        ex.session = session
    }

    private func deleteExercise(_ exercise: ProgramSessionExercise) {
        modelContext.delete(exercise)
    }
}

// MARK: - Badge Style Helper

private extension Text {
    func badgeStyle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
    }
}

// MARK: - PhaseCardView

private struct PhaseCardView: View {
    let group: ReviewPhaseGroup
    let isExpanded: Bool
    let showAdditionalInfo: Bool
    @Binding var expandedWeeks: Set<Int>
    @Binding var expandedSessions: Set<String>
    @Binding var editingExercise: ProgramSessionExercise?
    @Binding var addingToSession: ProgramSessionTemplate?
    let weeklySummariesByWeek: [Int: ProgramGeneratedWeekSummary]
    let input: ProgramGenerationInput
    let onTogglePhase: () -> Void
    let onDeleteExercise: (ProgramSessionExercise) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            phaseHeader
            if isExpanded {
                Divider().padding(.leading, 16)
                let sortedWeeks = group.weeks.sorted { $0.weekNumber < $1.weekNumber }
                ForEach(sortedWeeks) { week in
                    WeekRowView(
                        week: week,
                        isDeload: group.isDeload,
                        isExpanded: expandedWeeks.contains(week.weekNumber),
                        showAdditionalInfo: showAdditionalInfo,
                        weekSummary: weeklySummariesByWeek[week.weekNumber],
                        expandedSessions: $expandedSessions,
                        editingExercise: $editingExercise,
                        addingToSession: $addingToSession,
                        input: input,
                        onToggleWeek: {
                            if expandedWeeks.contains(week.weekNumber) { expandedWeeks.remove(week.weekNumber) }
                            else { expandedWeeks.insert(week.weekNumber) }
                        },
                        onDeleteExercise: onDeleteExercise
                    )
                    if week.id != sortedWeeks.last?.id {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
    }

    private var phaseHeader: some View {
        Button(action: onTogglePhase) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if group.isDeload {
                            Text("Deload")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(group.weekRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(group.schemeDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WeekRowView

private struct WeekRowView: View {
    let week: ProgramWeekTemplate
    let isDeload: Bool
    let isExpanded: Bool
    let showAdditionalInfo: Bool
    let weekSummary: ProgramGeneratedWeekSummary?
    @Binding var expandedSessions: Set<String>
    @Binding var editingExercise: ProgramSessionExercise?
    @Binding var addingToSession: ProgramSessionTemplate?
    let input: ProgramGenerationInput
    let onToggleWeek: () -> Void
    let onDeleteExercise: (ProgramSessionExercise) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekHeader
            if isExpanded {
                let sortedSessions = week.sessions.sorted { $0.sessionNumber < $1.sessionNumber }
                VStack(spacing: 0) {
                    if showAdditionalInfo, let summary = weekSummary {
                        weekSummaryRow(summary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    ForEach(sortedSessions) { session in
                        let key = "W\(week.weekNumber)S\(session.sessionNumber)"
                        SessionRowView(
                            session: session,
                            isExpanded: expandedSessions.contains(key),
                            showAdditionalInfo: showAdditionalInfo,
                            editingExercise: $editingExercise,
                            addingToSession: $addingToSession,
                            input: input,
                            onToggleSession: {
                                if expandedSessions.contains(key) { expandedSessions.remove(key) }
                                else { expandedSessions.insert(key) }
                            },
                            onDeleteExercise: onDeleteExercise
                        )
                        if session.id != sortedSessions.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .padding(.leading, 16)
                .background(Color(.secondarySystemBackground).opacity(0.5))
            }
        }
    }

    private var weekHeader: some View {
        Button(action: onToggleWeek) {
            HStack(spacing: 8) {
                Text("Week \(week.weekNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if isDeload {
                    Text("Deload")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                if showAdditionalInfo, let fatigue = weekSummary?.totalFatigueScore {
                    Text("Fatigue \(formatOneDecimal(fatigue))")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func weekSummaryRow(_ summary: ProgramGeneratedWeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly Hard Sets")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(
                        ProgramVolumeMuscle.allCases.compactMap { muscle -> (ProgramVolumeMuscle, Double)? in
                            let sets = summary.totalHardSetsByMuscle[muscle] ?? 0
                            return sets > 0 ? (muscle, sets) : nil
                        },
                        id: \.0
                    ) { muscle, sets in
                        Text("\(muscle.displayName): \(formatOneDecimal(sets))")
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemBackground))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

// MARK: - SessionRowView

private struct SessionRowView: View {
    let session: ProgramSessionTemplate
    let isExpanded: Bool
    let showAdditionalInfo: Bool
    @Binding var editingExercise: ProgramSessionExercise?
    @Binding var addingToSession: ProgramSessionTemplate?
    let input: ProgramGenerationInput
    let onToggleSession: () -> Void
    let onDeleteExercise: (ProgramSessionExercise) -> Void

    private var sessionTitle: String {
        if let name = session.sessionName {
            return "Session \(session.sessionNumber) — \(name)"
        }
        return "Session \(session.sessionNumber)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionHeader
            if isExpanded {
                let sorted = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
                let groups = ProgramReviewGrouping.groupedExercises(from: sorted)
                VStack(spacing: 0) {
                    ForEach(groups) { group in
                        GroupedExerciseRowView(
                            group: group,
                            showAdditionalInfo: showAdditionalInfo,
                            input: input,
                            onTapWorking: { editingExercise = group.workingSet },
                            onDelete: { onDeleteExercise(group.workingSet) }
                        )
                        if group.id != groups.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }

                    // Add exercise
                    Button(action: { addingToSession = session }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.teal)
                            Text("Add Exercise")
                                .font(.subheadline)
                                .foregroundStyle(.teal)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sessionHeader: some View {
        Button(action: onToggleSession) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sessionTitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if showAdditionalInfo, let reason = session.explainabilityReason {
                        Text(reason.shortLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemBackground))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GroupedExerciseRowView

private struct GroupedExerciseRowView: View {
    let group: ProgramReviewExerciseGroup
    let showAdditionalInfo: Bool
    let input: ProgramGenerationInput
    let onTapWorking: () -> Void
    let onDelete: () -> Void

    @State private var warmupsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Working set row
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.teal.opacity(0.6))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.workingSet.exerciseName)
                            .font(.subheadline)
                        Text(workingSetStyleLabel(for: group.workingSet))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(workingSetStyleColor(for: group.workingSet).opacity(0.15))
                            .foregroundStyle(workingSetStyleColor(for: group.workingSet))
                            .clipShape(Capsule())
                    }
                    Text(exerciseDisplayText(exercise: group.workingSet, oneRepMaxes: input.oneRepMaxes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if showAdditionalInfo {
                        HStack(spacing: 4) {
                            if let purpose = exercisePurposeLabel(for: group.workingSet) {
                                Text(purpose)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.tertiarySystemBackground))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                            if let reason = exerciseSelectionReasonLabel(for: group.workingSet) {
                                Text(reason)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.tertiarySystemBackground))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                if !group.warmupSets.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { warmupsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                            Text(warmupsExpanded ? "Hide" : "\(group.warmupSets.count) warmups")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onTapWorking) {
                    Image(systemName: "pencil.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { onTapWorking() }

            // Warmup sub-rows (collapsible)
            if warmupsExpanded {
                ForEach(group.warmupSets.sorted { $0.orderIndex < $1.orderIndex }) { warmup in
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.orange.opacity(0.35))
                            .frame(width: 2)
                            .padding(.leading, 16)

                        Circle()
                            .fill(Color.orange.opacity(0.5))
                            .frame(width: 5, height: 5)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Warmup")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(exerciseDisplayText(exercise: warmup, oneRepMaxes: input.oneRepMaxes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .padding(.leading, 4)
                }
            }
        }
    }
}

// MARK: - ExerciseEditSheet

struct ExerciseEditSheet: View {
    let exercise: ProgramSessionExercise
    let input: ProgramGenerationInput
    @Environment(\.dismiss) private var dismiss

    @State private var selectedName: String = ""
    @State private var setsText: String = ""
    @State private var repsText: String = ""
    @State private var pctText: String = ""
    @State private var rpeText: String = ""
    @State private var showingPicker = false

    private var isCardio: Bool { exercise.targetSets == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    HStack {
                        Text(selectedName.isEmpty ? exercise.exerciseName : selectedName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Swap") { showingPicker = true }
                            .font(.subheadline)
                            .foregroundStyle(.teal)
                    }
                }

                if !isCardio {
                    Section("Volume") {
                        HStack {
                            Text("Sets")
                            Spacer()
                            TextField("Sets", text: $setsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Reps")
                            Spacer()
                            TextField("Reps", text: $repsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                Section("Intensity") {
                    if isCardio {
                        HStack {
                            Text("Duration (min)")
                            Spacer()
                            TextField("min", text: $repsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    } else if exercise.targetPercentage1RM != nil {
                        HStack {
                            Text("% of 1RM")
                            Spacer()
                            TextField("e.g. 85", text: $pctText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("%").foregroundStyle(.secondary)
                        }
                    } else if exercise.targetRPE != nil {
                        HStack {
                            Text("RPE (1–10)")
                            Spacer()
                            TextField("e.g. 7.5", text: $rpeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadValues() }
            .sheet(isPresented: $showingPicker) {
                ReviewExercisePickerSheet { name in selectedName = name }
            }
        }
    }

    private func loadValues() {
        selectedName = exercise.exerciseName
        setsText = exercise.targetSets.map(String.init) ?? ""
        repsText = exercise.targetReps.map(String.init) ?? ""
        if let pct = exercise.targetPercentage1RM {
            pctText = String(format: "%.0f", pct * 100)
        }
        if let rpe = exercise.targetRPE {
            rpeText = rpe.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(rpe))
                : String(format: "%.1f", rpe)
        }
    }

    private func save() {
        if !selectedName.isEmpty { exercise.exerciseName = selectedName }
        if let sets = Int(setsText), sets > 0 { exercise.targetSets = sets }
        if let reps = Int(repsText), reps > 0 { exercise.targetReps = reps }

        if !pctText.isEmpty, let pct = Double(pctText), pct > 0 {
            let normalizedPct = min(pct / 100.0, 1.0)
            exercise.targetPercentage1RM = normalizedPct
            exercise.targetEffortType = .percentage1RM

            let name = selectedName.isEmpty ? exercise.exerciseName : selectedName
            if let orm = resolvedOneRepMax(for: name, oneRepMaxes: input.oneRepMaxes) {
                let raw = normalizedPct * orm.weight
                let rounded = orm.unit == "lbs"
                    ? max(5.0, (raw / 5.0).rounded() * 5.0)
                    : max(2.5, (raw / 2.5).rounded() * 2.5)
                exercise.prescribedWeight = rounded
                exercise.prescribedWeightUnit = orm.unit
            } else {
                exercise.prescribedWeight = nil
                exercise.prescribedWeightUnit = nil
            }
        }

        if !rpeText.isEmpty, let rpe = Double(rpeText), rpe > 0 {
            exercise.targetRPE = min(rpe, 10.0)
            if exercise.targetPercentage1RM == nil {
                exercise.targetEffortType = .rpe
            }
        }
        dismiss()
    }
}

// MARK: - ReviewExercisePickerSheet

struct ReviewExercisePickerSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]
    @State private var expandedGroups: Set<String> = []
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(muscleGroups) { group in
                    let exercises = group.exercises
                        .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
                        .sorted { $0.name < $1.name }

                    if !exercises.isEmpty {
                        Section {
                            if expandedGroups.contains(group.name) || !searchText.isEmpty {
                                ForEach(exercises) { exercise in
                                    Button(action: {
                                        onSelect(exercise.name)
                                        dismiss()
                                    }) {
                                        Text(exercise.name)
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        } header: {
                            if searchText.isEmpty {
                                Button(action: {
                                    if expandedGroups.contains(group.name) {
                                        expandedGroups.remove(group.name)
                                    } else {
                                        expandedGroups.insert(group.name)
                                    }
                                }) {
                                    HStack {
                                        Text(group.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .textCase(nil)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .rotationEffect(.degrees(
                                                expandedGroups.contains(group.name) ? 90 : 0
                                            ))
                                            .animation(.easeInOut(duration: 0.2), value: expandedGroups.contains(group.name))
                                    }
                                }
                            } else {
                                Text(group.name).textCase(nil)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
