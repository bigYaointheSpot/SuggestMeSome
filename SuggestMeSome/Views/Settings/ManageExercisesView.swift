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

    // Rename group
    @State private var groupToRename: MuscleGroup?

    // Delete group
    @State private var groupToDelete: MuscleGroup?

    // Add exercise
    @State private var groupForNewExercise: MuscleGroup?

    // Rename exercise
    @State private var exerciseToRename: Exercise?

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
                    showingAddGroup = true
                } label: {
                    Label("Add Group", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGroup) {
            NameEditorSheet(
                title: "New Muscle Group",
                placeholder: "Group name",
                actionLabel: "Add"
            ) { name in
                addGroup(named: name)
            }
        }
        .sheet(item: $groupToRename) { group in
            NameEditorSheet(
                title: "Rename Group",
                placeholder: "Group name",
                initialValue: group.name
            ) { name in
                group.name = name
            }
        }
        .sheet(item: $groupForNewExercise) { group in
            NameEditorSheet(
                title: "New Exercise",
                placeholder: "Exercise name",
                actionLabel: "Add",
                subtitle: "Adding to \(group.name)"
            ) { name in
                modelContext.insert(Exercise(name: name, muscleGroup: group))
            }
        }
        .sheet(item: $exerciseToRename) { exercise in
            NameEditorSheet(
                title: "Rename Exercise",
                placeholder: "Exercise name",
                initialValue: exercise.name
            ) { name in
                exercise.name = name
            }
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
                groupToRename = group
            } label: {
                Image(systemName: "pencil").foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(group.name)")
            Button {
                groupToDelete = group
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(group.name)")
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
                    exerciseToRename = exercise
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
    }

    // MARK: - Library actions

    private func addGroup(named name: String) {
        modelContext.insert(MuscleGroup(name: name))
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
