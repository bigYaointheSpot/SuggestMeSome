//
//  SettingsView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]
    @Query(sort: \Workout.date) private var allWorkouts: [Workout]
    @Query private var allExerciseEntries: [ExerciseEntry]

    // Add group
    @State private var showingAddGroup = false
    @State private var newGroupName = ""

    // Rename group
    @State private var groupToRename: MuscleGroup?
    @State private var renameGroupText = ""

    // Delete group
    @State private var groupToDelete: MuscleGroup?

    // Add exercise
    @State private var groupForNewExercise: MuscleGroup?
    @State private var newExerciseName = ""

    // Rename exercise
    @State private var exerciseToRename: Exercise?
    @State private var renameExerciseText = ""

    // Delete exercise
    @State private var exerciseToDelete: Exercise?

    // Preferences
    @AppStorage("globalWeightUnit") private var globalWeightUnit: String = WeightUnit.lbs.rawValue

    private var weightUnitBinding: Binding<WeightUnit> {
        Binding(
            get: { WeightUnit(rawValue: globalWeightUnit) ?? .lbs },
            set: { globalWeightUnit = $0.rawValue }
        )
    }

    // Data management
    @State private var showingDeleteAllConfirm = false
    @State private var showingDeleteRangeSheet = false

    // MARK: - Helpers (extracted to avoid type-checker overload)

    private func groupDeleteTitle(_ group: MuscleGroup) -> String {
        let n = group.exercises.count
        if n == 0 { return "Delete Group" }
        return "Delete Group and \(n) Exercise\(n == 1 ? "" : "s")"
    }

    private func groupDeleteMessage(_ group: MuscleGroup) -> String {
        let n = group.exercises.count
        return "All \(n) exercise\(n == 1 ? "" : "s") in this group will also be deleted. Historical workout data is not affected."
    }

    private func exerciseDeleteMessage(_ exercise: Exercise) -> String {
        let n = allExerciseEntries.filter { $0.exerciseName == exercise.name }.count
        if n > 0 {
            return "\"\(exercise.name)\" has been logged in \(n) workout\(n == 1 ? "" : "s"). Historical data will not be affected."
        }
        return "This exercise has not been used in any workouts."
    }

    private func deleteAllTitle() -> String {
        let n = allWorkouts.count
        return "Delete \(n) Workout\(n == 1 ? "" : "s") and All PRs"
    }

    private func deleteAllMessage() -> String {
        let n = allWorkouts.count
        return "All \(n) workout\(n == 1 ? "" : "s") and every personal record will be permanently deleted. Your exercise library is kept."
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                Picker("Default Weight Unit", selection: weightUnitBinding) {
                    ForEach(WeightUnit.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Preferences")
            }

            Section {
                personalRecordsLink
                healthDataLink
            }

            ForEach(muscleGroups) { group in
                muscleGroupSection(group)
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteRangeSheet = true
                } label: {
                    Label("Delete Workouts by Date Range…", systemImage: "calendar.badge.minus")
                }
                Button(role: .destructive) {
                    showingDeleteAllConfirm = true
                } label: {
                    Label("Delete All Workout Data", systemImage: "trash.fill")
                }
            } header: {
                Text("Data Management")
            } footer: {
                Text("Deleting workouts permanently removes all associated exercises and sets. Personal records are recalculated automatically. Your exercise library is not affected.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Manage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newGroupName = ""
                    showingAddGroup = true
                } label: {
                    Label("Add Group", systemImage: "plus")
                }
            }
        }
        .alert("New Muscle Group", isPresented: $showingAddGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Add") { addGroup() }
            Button("Cancel", role: .cancel) { newGroupName = "" }
        }
        .alert("Rename Group", isPresented: Binding(
            get: { groupToRename != nil },
            set: { if !$0 { groupToRename = nil } }
        )) {
            TextField("Group name", text: $renameGroupText)
            Button("Save") { saveGroupRename() }
            Button("Cancel", role: .cancel) { groupToRename = nil }
        }
        .confirmationDialog(
            "Delete \"\(groupToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { groupToDelete != nil },
                set: { if !$0 { groupToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let group = groupToDelete {
                Button(groupDeleteTitle(group), role: .destructive) {
                    modelContext.delete(group)
                    groupToDelete = nil
                }
                Button("Cancel", role: .cancel) { groupToDelete = nil }
            }
        } message: {
            if let group = groupToDelete, !group.exercises.isEmpty {
                Text(groupDeleteMessage(group))
            }
        }
        .alert("New Exercise", isPresented: Binding(
            get: { groupForNewExercise != nil },
            set: { if !$0 { groupForNewExercise = nil } }
        )) {
            TextField("Exercise name", text: $newExerciseName)
            Button("Add") { addExercise() }
            Button("Cancel", role: .cancel) { groupForNewExercise = nil }
        } message: {
            if let group = groupForNewExercise {
                Text("Adding to \(group.name)")
            }
        }
        .alert("Rename Exercise", isPresented: Binding(
            get: { exerciseToRename != nil },
            set: { if !$0 { exerciseToRename = nil } }
        )) {
            TextField("Exercise name", text: $renameExerciseText)
            Button("Save") { saveExerciseRename() }
            Button("Cancel", role: .cancel) { exerciseToRename = nil }
        }
        .confirmationDialog(
            "Delete \"\(exerciseToDelete?.name ?? "")\"?",
            isPresented: Binding(
                get: { exerciseToDelete != nil },
                set: { if !$0 { exerciseToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Exercise", role: .destructive) {
                if let e = exerciseToDelete { modelContext.delete(e) }
                exerciseToDelete = nil
            }
            Button("Cancel", role: .cancel) { exerciseToDelete = nil }
        } message: {
            if let exercise = exerciseToDelete {
                Text(exerciseDeleteMessage(exercise))
            }
        }
        .confirmationDialog(
            "Delete All Workout Data?",
            isPresented: $showingDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button(deleteAllTitle(), role: .destructive) {
                deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteAllMessage())
        }
        .sheet(isPresented: $showingDeleteRangeSheet) {
            DeleteByRangeSheet(allWorkouts: allWorkouts) { start, end in
                deleteWorkoutsInRange(from: start, to: end)
            }
        }
    }

    // MARK: - Muscle group section

    private var personalRecordsLink: some View {
        NavigationLink {
            PersonalRecordsView()
        } label: {
            Label("Personal Records", systemImage: "trophy.fill")
                .foregroundStyle(.yellow)
        }
    }

    private var healthDataLink: some View {
        NavigationLink {
            HealthDataSettingsView()
        } label: {
            Label("Health Data", systemImage: "heart.text.square.fill")
                .foregroundStyle(.red)
        }
    }

    private func sortedExercises(in group: MuscleGroup) -> [Exercise] {
        group.exercises.sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private func muscleGroupSection(_ group: MuscleGroup) -> some View {
        Section {
            ForEach(sortedExercises(in: group)) { exercise in
                exerciseRow(exercise)
            }
            Button {
                groupForNewExercise = group
                newExerciseName = ""
            } label: {
                Label("Add Exercise", systemImage: "plus.circle")
                    .foregroundStyle(.blue)
            }
        } header: {
            groupHeader(group)
        }
    }

    // MARK: - Group header

    private func groupHeader(_ group: MuscleGroup) -> some View {
        HStack(spacing: 12) {
            Text(group.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
            Spacer()
            Button {
                renameGroupText = group.name
                groupToRename = group
            } label: {
                Image(systemName: "pencil").foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            Button {
                groupToDelete = group
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Exercise row

    private func exerciseRow(_ exercise: Exercise) -> some View {
        Text(exercise.name)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    exerciseToDelete = exercise
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    renameExerciseText = exercise.name
                    exerciseToRename = exercise
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }

    // MARK: - Library actions

    private func addGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(MuscleGroup(name: name))
        newGroupName = ""
    }

    private func saveGroupRename() {
        let name = renameGroupText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let group = groupToRename else { return }
        group.name = name
        groupToRename = nil
    }

    private func addExercise() {
        let name = newExerciseName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let group = groupForNewExercise else { return }
        modelContext.insert(Exercise(name: name, muscleGroup: group))
        newExerciseName = ""
        groupForNewExercise = nil
    }

    private func saveExerciseRename() {
        let name = renameExerciseText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let exercise = exerciseToRename else { return }
        exercise.name = name
        exerciseToRename = nil
    }

    // MARK: - Data deletion

    private func deleteAllData() {
        for workout in allWorkouts { modelContext.delete(workout) }
        let allPRs = (try? modelContext.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        for pr in allPRs { modelContext.delete(pr) }
        try? modelContext.save()
    }

    private func deleteWorkoutsInRange(from start: Date, to end: Date) {
        let dayStart = Calendar.current.startOfDay(for: start)
        let dayEnd   = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: end)!

        let targets = allWorkouts.filter { $0.date >= dayStart && $0.date <= dayEnd }
        let affectedNames = Set(targets.flatMap { $0.exerciseEntries.map(\.exerciseName) })

        for workout in targets { modelContext.delete(workout) }
        try? modelContext.save()

        if !affectedNames.isEmpty {
            recomputePRs(for: affectedNames)
            try? modelContext.save()
        }
    }

    private func recomputePRs(for exerciseNames: Set<String>) {
        let existingPRs = (try? modelContext.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        for pr in existingPRs where exerciseNames.contains(pr.exerciseName) {
            modelContext.delete(pr)
        }

        let remaining = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []

        struct PRKey: Hashable { let name: String; let reps: Int }
        typealias Candidate = (weight: Double, unit: WeightUnit, date: Date, set: SetEntry)
        var best: [PRKey: Candidate] = [:]

        for workout in remaining {
            for entry in workout.exerciseEntries {
                guard exerciseNames.contains(entry.exerciseName) else { continue }
                for set in entry.sets {
                    set.isPR = false
                    guard set.reps > 0, set.weight > 0 else { continue }
                    let key = PRKey(name: entry.exerciseName, reps: set.reps)
                    let lbs = entry.unit == .kg ? set.weight * 2.20462 : set.weight
                    if let cur = best[key] {
                        let curLbs = cur.unit == .kg ? cur.weight * 2.20462 : cur.weight
                        if lbs > curLbs { best[key] = (set.weight, entry.unit, workout.date, set) }
                    } else {
                        best[key] = (set.weight, entry.unit, workout.date, set)
                    }
                }
            }
        }

        for (key, c) in best {
            modelContext.insert(PersonalRecord(
                exerciseName: key.name, repCount: key.reps,
                weight: c.weight, unit: c.unit, dateAchieved: c.date))
            c.set.isPR = true
        }
    }
}

// MARK: - DeleteByRangeSheet

struct DeleteByRangeSheet: View {
    let allWorkouts: [Workout]
    let onDelete: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showingConfirm = false

    // MARK: Computed properties (keep complex logic out of @ViewBuilder closures)

    private var workoutsInRange: [Workout] {
        let dayStart = Calendar.current.startOfDay(for: startDate)
        let dayEnd   = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
        return allWorkouts.filter { $0.date >= dayStart && $0.date <= dayEnd }
    }

    private var rangeCount: Int {
        workoutsInRange.count
    }

    private var earliestInRange: Date? {
        workoutsInRange.map(\.date).min()
    }

    private var latestInRange: Date? {
        workoutsInRange.map(\.date).max()
    }

    private var deleteButtonLabel: String {
        rangeCount == 0 ? "No Workouts in Range" : "Delete \(rangeCount) Workout\(rangeCount == 1 ? "" : "s")"
    }

    private var confirmDialogTitle: String {
        "Delete \(rangeCount) Workout\(rangeCount == 1 ? "" : "s")?"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $startDate,
                               in: ...endDate,
                               displayedComponents: .date)
                    DatePicker("To", selection: $endDate,
                               in: startDate...,
                               displayedComponents: .date)
                }

                Section {
                    previewCountRow
                    previewDatesRow
                } header: {
                    Text("Preview")
                }

                Section {
                    Button(role: .destructive) {
                        showingConfirm = true
                    } label: {
                        Text(deleteButtonLabel)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(rangeCount == 0)
                }
            }
            .navigationTitle("Delete by Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(confirmDialogTitle,
                                isPresented: $showingConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete(startDate, endDate)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("These workouts will be permanently deleted and personal records will be recalculated.")
            }
        }
    }

    // MARK: Preview sub-views

    private var previewCountRow: some View {
        HStack {
            Text("Workouts in range")
            Spacer()
            Text("\(rangeCount)")
                .fontWeight(rangeCount > 0 ? .semibold : .regular)
                .foregroundStyle(rangeCount > 0 ? .red : .secondary)
        }
    }

    @ViewBuilder
    private var previewDatesRow: some View {
        if let first = earliestInRange {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                Text(first, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let last = latestInRange, last != earliestInRange {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.right").foregroundStyle(.secondary)
                Text(last, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
