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
        _exerciseEntries = State(initialValue: drafts)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                datePicker
                exerciseList
                addExerciseButton
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
                    }
                }
            }
        }
    }

    private var addExerciseButton: some View {
        Button { showingExercisePicker = true } label: {
            Label("Add Exercise", systemImage: "plus.circle.fill")
                .font(.headline)
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
                .font(.headline)
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
                .font(.headline)
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
        recomputePRs(for: affectedNames)

        try? modelContext.save()
        dismiss()
    }

    // MARK: - Global PR recomputation
    //
    // When editing may lower or remove a weight, the previous PR might no longer
    // be the best. This function:
    //   1. Deletes all PersonalRecord rows for affected exercises.
    //   2. Scans every SetEntry across every workout for those exercises.
    //   3. Finds the global best weight per (exerciseName, repCount) pair.
    //   4. Recreates PersonalRecord rows and marks isPR on the winning SetEntries.
    //
    // All weight comparisons are normalised to lbs (1 kg = 2.20462 lbs).

    private func recomputePRs(for exerciseNames: Set<String>) {
        // 1. Remove stale PRs
        let existingPRs = (try? modelContext.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        for pr in existingPRs where exerciseNames.contains(pr.exerciseName) {
            modelContext.delete(pr)
        }

        // 2. Scan all workouts
        let allWorkouts = (try? modelContext.fetch(FetchDescriptor<Workout>())) ?? []

        struct PRKey: Hashable { let exerciseName: String; let repCount: Int }
        typealias Candidate = (weight: Double, unit: WeightUnit, date: Date, setEntry: SetEntry)
        var best: [PRKey: Candidate] = [:]

        for w in allWorkouts {
            for entry in w.exerciseEntries {
                guard exerciseNames.contains(entry.exerciseName) else { continue }
                for set in entry.sets {
                    set.isPR = false           // reset every set we touch
                    guard set.reps > 0, set.weight > 0 else { continue }

                    let key      = PRKey(exerciseName: entry.exerciseName, repCount: set.reps)
                    let newLbs   = toLbs(set.weight, unit: entry.unit)

                    if let current = best[key] {
                        if newLbs > toLbs(current.weight, unit: current.unit) {
                            best[key] = (set.weight, entry.unit, w.date, set)
                        }
                    } else {
                        best[key] = (set.weight, entry.unit, w.date, set)
                    }
                }
            }
        }

        // 3. Recreate PRs and mark winners
        for (key, candidate) in best {
            let pr = PersonalRecord(
                exerciseName: key.exerciseName,
                repCount: key.repCount,
                weight: candidate.weight,
                unit: candidate.unit,
                dateAchieved: candidate.date
            )
            modelContext.insert(pr)
            candidate.setEntry.isPR = true
        }
    }

    private func toLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
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
