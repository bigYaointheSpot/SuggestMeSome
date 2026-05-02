//
//  ProgramReviewSubviews.swift
//  SuggestMeSome
//
//  Subviews extracted from ProgramReviewView in Feature 22 Prompt 1.
//  Behavior unchanged.
//

import SwiftUI
import SwiftData

struct PhaseCardView: View {
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
                            .dsHeadline()
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

struct WeekRowView: View {
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

struct SessionRowView: View {
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

struct GroupedExerciseRowView: View {
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
                        Text(ExerciseDisplayFormatter.workingSetStyleLabel(for: group.workingSet))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ExerciseDisplayFormatter.workingSetStyleColor(for: group.workingSet).opacity(0.15))
                            .foregroundStyle(ExerciseDisplayFormatter.workingSetStyleColor(for: group.workingSet))
                            .clipShape(Capsule())
                    }
                    Text(ExerciseDisplayFormatter.exerciseDisplayText(exercise: group.workingSet, oneRepMaxes: input.oneRepMaxes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if showAdditionalInfo {
                        HStack(spacing: 4) {
                            if let purpose = ExerciseDisplayFormatter.exercisePurposeLabel(for: group.workingSet) {
                                Text(purpose)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.tertiarySystemBackground))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                            if let reason = ExerciseDisplayFormatter.exerciseSelectionReasonLabel(for: group.workingSet) {
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
                            Text(ExerciseDisplayFormatter.exerciseDisplayText(exercise: warmup, oneRepMaxes: input.oneRepMaxes))
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
            if let orm = ExerciseDisplayFormatter.resolvedOneRepMax(for: name, oneRepMaxes: input.oneRepMaxes) {
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
                                            .dsHeadline()
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
