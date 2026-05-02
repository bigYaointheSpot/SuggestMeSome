//
//  WorkoutEditView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

struct WorkoutEditView: View {
    let workout: Workout

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]

    @State private var workoutDate: Date
    @State private var exerciseEntries: [DraftExerciseEntry]
    @State private var caloriesText: String
    @State private var comments: String

    @State private var showingExercisePicker = false
    @State private var showingSaveConfirmation = false

    private var isImportedWorkout: Bool {
        !workout.allowsFullStructureEditing
    }

    init(workout: Workout) {
        self.workout = workout

        _workoutDate = State(initialValue: workout.date)
        _caloriesText = State(initialValue: workout.caloriesBurned.map { "\($0)" } ?? "")
        _comments = State(initialValue: workout.comments ?? "")

        let drafts: [DraftExerciseEntry] = workout.exerciseEntries
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { entry in
                if entry.isCardio {
                    let totalSecs = entry.cardioDurationSeconds ?? 0
                    let mins = totalSecs / 60
                    let secs = totalSecs % 60
                    return DraftExerciseEntry(
                        exerciseName: entry.exerciseName,
                        unit: entry.unit,
                        orderIndex: entry.orderIndex,
                        sets: [],
                        isCardio: true,
                        cardioMinutesText: mins > 0 ? "\(mins)" : "",
                        cardioSecondsText: secs > 0 ? "\(secs)" : ""
                    )
                } else {
                    return DraftExerciseEntry(
                        exerciseName: entry.exerciseName,
                        unit: entry.unit,
                        orderIndex: entry.orderIndex,
                        sets: entry.sets
                            .sorted { $0.setNumber < $1.setNumber }
                            .map { set in
                                DraftSet(
                                    setNumber: set.setNumber,
                                    repsText: set.reps > 0 ? "\(set.reps)" : "",
                                    weightText: weightString(set.weight),
                                    isPR: set.isPR
                                )
                            }
                    )
                }
            }
        _exerciseEntries = State(initialValue: drafts.normalizedExerciseOrder())
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                datePicker
                if isImportedWorkout {
                    importedEditingNotice
                } else {
                    exerciseList
                    addExerciseButton
                }
                caloriesField
                notesField
                saveButton
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(muscleGroups: muscleGroups) { name, isCardio, setCount in
                let sets: [DraftSet] = isCardio ? [] : (1...max(1, setCount)).map { DraftSet(setNumber: $0) }
                exerciseEntries.append(DraftExerciseEntry(
                    exerciseName: name,
                    unit: .lbs,
                    orderIndex: exerciseEntries.count,
                    sets: sets,
                    isCardio: isCardio
                ))
                exerciseEntries = exerciseEntries.normalizedExerciseOrder()
            }
        }
        .confirmationDialog("Save Changes?", isPresented: $showingSaveConfirmation, titleVisibility: .visible) {
            Button("Save") { saveChanges() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PR records will be recalculated across all your workouts for any affected exercises.")
        }
    }

    // MARK: - Sub-views

    private var datePicker: some View {
        HStack {
            Label("Date", systemImage: "calendar")
            Spacer()
            DatePicker("", selection: $workoutDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var exerciseList: some View {
        if !exerciseEntries.isEmpty {
            VStack(spacing: 12) {
                ForEach($exerciseEntries) { $entry in
                    ExerciseEntryCard(entry: $entry) {
                        exerciseEntries.removeAll { $0.id == entry.id }
                        exerciseEntries = exerciseEntries.normalizedExerciseOrder()
                    }
                }
            }
        }
    }

    private var importedEditingNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Limited editing for imported workouts", systemImage: "lock.fill")
                .dsHeadline()
            Text("You can edit date, calories, and notes. Exercise/set structure is read-only for Apple Health imports.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var addExerciseButton: some View {
        Button { showingExercisePicker = true } label: {
            Label("Add Exercise", systemImage: "plus.circle.fill")
                .dsHeadline()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var caloriesField: some View {
        HStack {
            Label("Calories Burned", systemImage: "flame.fill")
                .foregroundStyle(.orange)
            Spacer()
            TextField("Optional", text: $caloriesText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Workout Notes", systemImage: "note.text")
                .dsHeadline()
            TextEditor(text: $comments)
                .frame(minHeight: 120)
                .padding(6)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
        }
    }

    private var saveButton: some View {
        Button { showingSaveConfirmation = true } label: {
            Label("Save Changes", systemImage: "checkmark.circle.fill")
                .dsHeadline()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.bottom, 8)
    }

    // MARK: - Save logic

    private func saveChanges() {
        if isImportedWorkout {
            workout.date = workoutDate
            workout.caloriesBurned = Int(caloriesText)
            workout.comments = comments.isEmpty ? nil : comments
            try? modelContext.save()
            dismiss()
            return
        }

        // Collect affected exercise names (old ∪ new) so PR recomputation covers both
        let oldNames = Set(workout.exerciseEntries.map(\.exerciseName))
        let newNames = Set(exerciseEntries.map(\.exerciseName))
        let affectedNames = oldNames.union(newNames)

        // Update scalar fields
        workout.date = workoutDate
        workout.caloriesBurned = Int(caloriesText)
        workout.comments = comments.isEmpty ? nil : comments

        // Delete old exercise entries (cascades to their SetEntry children)
        for entry in workout.exerciseEntries {
            modelContext.delete(entry)
        }

        // Insert replacement entries and sets
        for (index, draft) in exerciseEntries.enumerated() {
            let entry = ExerciseEntry(
                exerciseName: draft.exerciseName,
                unit: draft.unit,
                orderIndex: index,
                isCardio: draft.isCardio,
                cardioDurationSeconds: draft.isCardio ? draft.cardioDurationSeconds : nil
            )
            entry.workout = workout
            modelContext.insert(entry)

            guard !draft.isCardio else { continue }

            for draftSet in draft.sets {
                let reps   = Int(draftSet.repsText)    ?? 0
                let weight = Double(draftSet.weightText) ?? 0.0
                let s = SetEntry(setNumber: draftSet.setNumber, reps: reps, weight: weight)
                s.exerciseEntry = entry
                modelContext.insert(s)
            }
        }

        // Persist before recomputing so fetches see the updated graph
        try? modelContext.save()

        // Recompute PRs globally for all affected exercises
        try? PersonalRecordMaintenanceService.recomputePRs(for: affectedNames, context: modelContext)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Helpers

/// Returns a clean string for a Double weight: "100" instead of "100.0", "52.5" as-is.
private func weightString(_ value: Double) -> String {
    guard value > 0 else { return "" }
    return value.truncatingRemainder(dividingBy: 1) == 0
        ? "\(Int(value))"
        : "\(value)"
}
