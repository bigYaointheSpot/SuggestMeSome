//
//  CreateProgramView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import SwiftUI
import SwiftData

// MARK: - Draft Types

struct DraftSessionExercise: Identifiable {
    var id = UUID()
    var exerciseName: String
    var targetSetsText: String = ""
    var targetRepsText: String = ""
}

struct DraftSession: Identifiable {
    var id = UUID()
    var sessionNumber: Int
    var exercises: [DraftSessionExercise] = []
}

struct DraftWeek: Identifiable {
    var id = UUID()
    var weekNumber: Int
    var sessions: [DraftSession] = []
    var isExpanded: Bool = false
}

// MARK: - CreateProgramView

struct CreateProgramView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]

    @State private var step = 1

    // Step 1
    @State private var programName = ""
    @State private var lengthInWeeks = 8
    @State private var sessionsPerWeek = 3

    // Step 2
    @State private var selectedExerciseNames: [String] = []
    @State private var expandedGroups: Set<String> = []

    // Step 3
    @State private var exerciseAssignments: [String: Set<Int>] = [:]
    @State private var exerciseTargetSets: [String: String] = [:]
    @State private var exerciseTargetReps: [String: String] = [:]

    // Step 4
    @State private var draftWeeks: [DraftWeek] = []
    @State private var showingExercisePicker = false
    @State private var pickerTarget: (weekIdx: Int, sessionIdx: Int)? = nil

    private var stepTitle: String {
        switch step {
        case 1: return "Program Basics"
        case 2: return "Select Exercises"
        case 3: return "Assign to Sessions"
        default: return "Review & Customize"
        }
    }

    var body: some View {
        Group {
            switch step {
            case 1: step1View
            case 2: step2View
            case 3: step3View
            default: step4View
            }
        }
        .navigationTitle(stepTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if step == 4 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            if let target = pickerTarget {
                ProgramExercisePickerSheet(muscleGroups: muscleGroups) { name, setsText, repsText in
                    let ex = DraftSessionExercise(
                        exerciseName: name,
                        targetSetsText: setsText,
                        targetRepsText: repsText
                    )
                    draftWeeks[target.weekIdx].sessions[target.sessionIdx].exercises.append(ex)
                }
            }
        }
    }

    // MARK: - Step 1

    private var step1View: some View {
        Form {
            Section("Program Name") {
                TextField("e.g. 8-Week Strength Block", text: $programName)
                    .textInputAutocapitalization(.words)
            }

            Section {
                Picker("Length", selection: $lengthInWeeks) {
                    ForEach([6, 8, 10, 12], id: \.self) { n in
                        Text("\(n) weeks").tag(n)
                    }
                }
                Picker("Sessions per Week", selection: $sessionsPerWeek) {
                    ForEach(2...6, id: \.self) { n in
                        Text("\(n) sessions").tag(n)
                    }
                }
            } header: {
                Text("Duration")
            }

            Section {
                Button("Next: Select Exercises") {
                    step = 2
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(programName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Step 2

    private var step2View: some View {
        List {
            ForEach(muscleGroups) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedGroups.contains(group.name) },
                        set: {
                            if $0 { expandedGroups.insert(group.name) }
                            else { expandedGroups.remove(group.name) }
                        }
                    )
                ) {
                    ForEach(group.exercises.sorted { $0.name < $1.name }) { exercise in
                        exerciseSelectionRow(exercise.name)
                    }
                } label: {
                    Text(group.name).font(.headline).foregroundStyle(.primary)
                }
            }

            Section {
                Button("Next: Assign to Sessions") {
                    advanceToStep3()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(selectedExerciseNames.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            if !selectedExerciseNames.isEmpty {
                HStack {
                    Text("\(selectedExerciseNames.count) exercise\(selectedExerciseNames.count == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func exerciseSelectionRow(_ exerciseName: String) -> some View {
        let isSelected = selectedExerciseNames.contains(exerciseName)
        return Button {
            if isSelected {
                selectedExerciseNames.removeAll { $0 == exerciseName }
            } else {
                selectedExerciseNames.append(exerciseName)
            }
        } label: {
            HStack {
                Text(exerciseName).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.blue)
                }
            }
        }
    }

    private func advanceToStep3() {
        for name in selectedExerciseNames {
            if exerciseAssignments[name] == nil { exerciseAssignments[name] = [] }
            if exerciseTargetSets[name] == nil { exerciseTargetSets[name] = "" }
            if exerciseTargetReps[name] == nil { exerciseTargetReps[name] = "" }
        }
        let toRemove = exerciseAssignments.keys.filter { !selectedExerciseNames.contains($0) }
        for key in toRemove {
            exerciseAssignments.removeValue(forKey: key)
            exerciseTargetSets.removeValue(forKey: key)
            exerciseTargetReps.removeValue(forKey: key)
        }
        step = 3
    }

    // MARK: - Step 3

    private var allSessionsCovered: Bool {
        (1...sessionsPerWeek).allSatisfy { sessionNum in
            selectedExerciseNames.contains { name in
                exerciseAssignments[name]?.contains(sessionNum) == true
            }
        }
    }

    private var step3View: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Week 1 Template — \(sessionsPerWeek) session\(sessionsPerWeek == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemGroupedBackground))

            List {
                ForEach(selectedExerciseNames, id: \.self) { name in
                    exerciseAssignmentRow(for: name)
                }

                Section {
                    Button("Next: Review & Customize") {
                        buildDraftWeeks()
                        step = 4
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!allSessionsCovered)
                } footer: {
                    if !allSessionsCovered {
                        Text("Each session needs at least one exercise.")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func exerciseAssignmentRow(for name: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).font(.headline)

            HStack(spacing: 6) {
                ForEach(Array(1...sessionsPerWeek), id: \.self) { sessionNum in
                    let isOn = exerciseAssignments[name]?.contains(sessionNum) == true
                    Button {
                        if isOn {
                            exerciseAssignments[name]?.remove(sessionNum)
                        } else {
                            exerciseAssignments[name, default: []].insert(sessionNum)
                        }
                    } label: {
                        Text("S\(sessionNum)")
                            .font(.caption.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(isOn ? Color.blue : Color(.tertiarySystemBackground))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Sets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                    TextField("—", text: Binding(
                        get: { exerciseTargetSets[name] ?? "" },
                        set: { exerciseTargetSets[name] = $0 }
                    ))
                    .keyboardType(.numberPad)
                    .frame(width: 52)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 6) {
                    Text("Reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                    TextField("—", text: Binding(
                        get: { exerciseTargetReps[name] ?? "" },
                        set: { exerciseTargetReps[name] = $0 }
                    ))
                    .keyboardType(.numberPad)
                    .frame(width: 52)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Build Draft Weeks

    private func buildDraftWeeks() {
        draftWeeks = (1...lengthInWeeks).map { weekNum in
            let sessions = (1...sessionsPerWeek).map { sessionNum in
                let exercises = selectedExerciseNames
                    .filter { exerciseAssignments[$0]?.contains(sessionNum) == true }
                    .map { name in
                        DraftSessionExercise(
                            exerciseName: name,
                            targetSetsText: exerciseTargetSets[name] ?? "",
                            targetRepsText: exerciseTargetReps[name] ?? ""
                        )
                    }
                return DraftSession(sessionNumber: sessionNum, exercises: exercises)
            }
            return DraftWeek(weekNumber: weekNum, sessions: sessions, isExpanded: weekNum == 1)
        }
    }

    // MARK: - Step 4

    private var step4View: some View {
        List {
            ForEach($draftWeeks) { $week in
                Section {
                    if week.isExpanded {
                        ForEach($week.sessions) { $session in
                            sessionHeaderRow(session: session)

                            ForEach($session.exercises) { $exercise in
                                exerciseEditorRow(exercise: $exercise)
                            }
                            .onMove { from, to in
                                $session.wrappedValue.exercises.move(fromOffsets: from, toOffset: to)
                            }
                            .onDelete { offsets in
                                $session.wrappedValue.exercises.remove(atOffsets: offsets)
                            }

                            addExerciseButton(week: week, session: session)
                        }
                    }
                } header: {
                    weekHeader(week: week, toggle: {
                        $week.wrappedValue.isExpanded.toggle()
                    })
                }
            }

            Section {
                Button("Save Program") {
                    saveProgram()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .font(.headline)
                .foregroundStyle(Color.white)
                .listRowBackground(Color.blue)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sessionHeaderRow(session: DraftSession) -> some View {
        HStack {
            Text("Session \(session.sessionNumber)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(session.exercises.count) exercise\(session.exercises.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color(.tertiarySystemBackground))
    }

    private func addExerciseButton(week: DraftWeek, session: DraftSession) -> some View {
        Button {
            if let wi = draftWeeks.firstIndex(where: { $0.id == week.id }),
               let si = draftWeeks[wi].sessions.firstIndex(where: { $0.id == session.id }) {
                pickerTarget = (weekIdx: wi, sessionIdx: si)
                showingExercisePicker = true
            }
        } label: {
            Label("Add Exercise", systemImage: "plus.circle.fill")
                .foregroundStyle(.blue)
                .font(.subheadline)
        }
    }

    private func exerciseEditorRow(exercise: Binding<DraftSessionExercise>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.wrappedValue.exerciseName).font(.body)
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Sets").font(.caption).foregroundStyle(.secondary)
                    TextField("—", text: exercise.targetSetsText)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                HStack(spacing: 4) {
                    Text("Reps").font(.caption).foregroundStyle(.secondary)
                    TextField("—", text: exercise.targetRepsText)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func weekHeader(week: DraftWeek, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text("Week \(week.weekNumber)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
                Spacer()
                let totalEx = week.sessions.reduce(0) { $0 + $1.exercises.count }
                Text("\(week.sessions.count) sessions • \(totalEx) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(week.isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: week.isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: - Save

    private func saveProgram() {
        let program = TrainingProgram(
            name: programName.trimmingCharacters(in: .whitespaces),
            lengthInWeeks: lengthInWeeks,
            sessionsPerWeek: sessionsPerWeek,
            source: .userCreated
        )
        modelContext.insert(program)

        for draftWeek in draftWeeks {
            let week = ProgramWeekTemplate(weekNumber: draftWeek.weekNumber)
            week.program = program
            modelContext.insert(week)

            for draftSession in draftWeek.sessions {
                let session = ProgramSessionTemplate(sessionNumber: draftSession.sessionNumber)
                session.week = week
                modelContext.insert(session)

                for (idx, draftExercise) in draftSession.exercises.enumerated() {
                    let ex = ProgramSessionExercise(
                        exerciseName: draftExercise.exerciseName,
                        orderIndex: idx,
                        targetSets: Int(draftExercise.targetSetsText),
                        targetReps: Int(draftExercise.targetRepsText)
                    )
                    ex.session = session
                    modelContext.insert(ex)
                }
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - ProgramExercisePickerSheet

struct ProgramExercisePickerSheet: View {
    let muscleGroups: [MuscleGroup]
    /// Called with (exerciseName, targetSetsText, targetRepsText).
    let onAdd: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var expandedGroups: Set<String> = []
    @State private var selectedExercise: String? = nil
    @State private var showingDetails = false
    @State private var setsText = ""
    @State private var repsText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(muscleGroups) { group in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedGroups.contains(group.name) },
                            set: {
                                if $0 { expandedGroups.insert(group.name) }
                                else { expandedGroups.remove(group.name) }
                            }
                        )
                    ) {
                        ForEach(group.exercises.sorted { $0.name < $1.name }) { exercise in
                            Button {
                                selectedExercise = exercise.name
                                setsText = ""
                                repsText = ""
                                showingDetails = true
                            } label: {
                                Text(exercise.name).foregroundStyle(.primary)
                            }
                        }
                    } label: {
                        Text(group.name).font(.headline).foregroundStyle(.primary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingDetails) {
                exerciseDetailsView
            }
        }
    }

    @ViewBuilder
    private var exerciseDetailsView: some View {
        if let name = selectedExercise {
            Form {
                Section("Exercise") {
                    Text(name).font(.headline)
                }
                Section {
                    HStack {
                        Text("Target Sets").foregroundStyle(.secondary)
                        Spacer()
                        TextField("Optional", text: $setsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Target Reps").foregroundStyle(.secondary)
                        Spacer()
                        TextField("Optional", text: $repsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                } header: {
                    Text("Targets (Optional)")
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name, setsText, repsText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
