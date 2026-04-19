//
//  ManageExercisesView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

struct ManageExercisesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]

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
    @State private var exerciseUsageSummary = ExerciseUsageSummary.empty

    // MARK: - Helpers

    private func groupDeleteTitle(_ group: MuscleGroup) -> String {
        let n = group.exercises.count
        if n == 0 { return "Delete Group" }
        return "Delete Group and \(n) Exercise\(n == 1 ? "" : "s")"
    }

    private func groupDeleteMessage(_ group: MuscleGroup) -> String {
        let n = group.exercises.count
        return "All \(n) exercise\(n == 1 ? "" : "s") in this group will also be deleted. Historical workout data is not affected."
    }

    private func exerciseDeleteMessage(for summary: ExerciseUsageSummary) -> String {
        let n = summary.workoutCount
        if n > 0 {
            return "\"\(summary.exerciseName)\" has been logged in \(n) workout\(n == 1 ? "" : "s"). Historical data will not be affected."
        }
        return "This exercise has not been used in any workouts."
    }

    private var exerciseUsageRefreshToken: String {
        exerciseToDelete?.name ?? ""
    }

    // MARK: - Body

    var body: some View {
        List {
            ForEach(muscleGroups) { group in
                muscleGroupSection(group)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Manage Exercises")
        .navigationBarTitleDisplayMode(.large)
        .task(id: exerciseUsageRefreshToken) {
            refreshExerciseUsageSummary()
        }
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
            if exerciseToDelete != nil {
                Text(exerciseDeleteMessage(for: exerciseUsageSummary))
            }
        }
    }

    // MARK: - Muscle group section

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

    private func refreshExerciseUsageSummary() {
        guard let exercise = exerciseToDelete else {
            exerciseUsageSummary = .empty
            return
        }

        exerciseUsageSummary = TrainingReadRepository.exerciseUsageSummary(
            for: exercise.name,
            context: modelContext
        )
    }
}
