//
//  WorkoutView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - In-memory draft types (not persisted until the user saves)

struct DraftSet: Identifiable {
    let id: UUID
    var setNumber: Int
    var repsText: String
    var weightText: String
    var isPR: Bool

    init(setNumber: Int, repsText: String = "", weightText: String = "", isPR: Bool = false) {
        self.id = UUID()
        self.setNumber = setNumber
        self.repsText = repsText
        self.weightText = weightText
        self.isPR = isPR
    }
}

struct DraftExerciseEntry: Identifiable {
    let id: UUID
    var exerciseName: String
    var unit: WeightUnit
    var orderIndex: Int
    var sets: [DraftSet]
    var isCardio: Bool
    var cardioMinutesText: String
    var cardioSecondsText: String

    var cardioDurationSeconds: Int {
        (Int(cardioMinutesText) ?? 0) * 60 + (Int(cardioSecondsText) ?? 0)
    }

    init(
        exerciseName: String,
        unit: WeightUnit,
        orderIndex: Int,
        sets: [DraftSet],
        isCardio: Bool = false,
        cardioMinutesText: String = "",
        cardioSecondsText: String = ""
    ) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.unit = unit
        self.orderIndex = orderIndex
        self.sets = sets
        self.isCardio = isCardio
        self.cardioMinutesText = cardioMinutesText
        self.cardioSecondsText = cardioSecondsText
    }
}

// MARK: - WorkoutView

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]
    @Query private var allPersonalRecords: [PersonalRecord]

    // Timer
    @State private var isActive = false
    @State private var startTime: Date?
    @State private var elapsedSeconds: Int = 0

    // Workout data
    @State private var exerciseEntries: [DraftExerciseEntry] = []
    @State private var caloriesText: String = ""
    @State private var comments: String = ""

    // Sheets / alerts
    @State private var showingExercisePicker = false
    @State private var showingEndConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dateHeader
                timerSection
                Divider().padding(.horizontal)
                exerciseList
                addExerciseButton
                caloriesField
                notesField
                endWorkoutButton
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Log Workout")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard isActive, let start = startTime else { return }
            elapsedSeconds = Int(Date.now.timeIntervalSince(start))
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(muscleGroups: muscleGroups) { name, isCardio, setCount in
                let sets: [DraftSet] = isCardio ? [] : (1...max(1, setCount)).map { DraftSet(setNumber: $0) }
                let entry = DraftExerciseEntry(
                    exerciseName: name,
                    unit: .lbs,
                    orderIndex: exerciseEntries.count,
                    sets: sets,
                    isCardio: isCardio
                )
                exerciseEntries.append(entry)
            }
        }
        .confirmationDialog("End Workout?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("Save & End Workout", role: .destructive) { saveWorkout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will save your workout and mark any new personal records.")
        }
    }

    // MARK: - Sub-views

    private var dateHeader: some View {
        Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day().year())
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal)
    }

    private var timerSection: some View {
        VStack(spacing: 14) {
            Text(formattedElapsed)
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)

            if isActive {
                Button {
                    showingEndConfirmation = true
                } label: {
                    Label("End Workout", systemImage: "stop.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    startTime = Date.now
                    isActive = true
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
        }
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
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var addExerciseButton: some View {
        if isActive {
            Button {
                showingExercisePicker = true
            } label: {
                Label("Add Exercise", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
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
        .padding(.horizontal)
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
        .padding(.horizontal)
    }

    @ViewBuilder
    private var endWorkoutButton: some View {
        if isActive {
            Button {
                showingEndConfirmation = true
            } label: {
                Label("End Workout", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Save

    private func saveWorkout() {
        guard isActive, let start = startTime else { return }
        let now = Date.now

        let workout = Workout(
            date: now,
            startTime: start,
            durationSeconds: Int(now.timeIntervalSince(start)),
            caloriesBurned: Int(caloriesText),
            comments: comments.isEmpty ? nil : comments
        )
        modelContext.insert(workout)

        for draftEntry in exerciseEntries {
            let entry = ExerciseEntry(
                exerciseName: draftEntry.exerciseName,
                unit: draftEntry.unit,
                orderIndex: draftEntry.orderIndex,
                isCardio: draftEntry.isCardio,
                cardioDurationSeconds: draftEntry.isCardio ? draftEntry.cardioDurationSeconds : nil
            )
            entry.workout = workout
            modelContext.insert(entry)

            guard !draftEntry.isCardio else { continue }

            for draftSet in draftEntry.sets {
                let reps = Int(draftSet.repsText) ?? 0
                let weight = Double(draftSet.weightText) ?? 0.0
                let setEntry = SetEntry(setNumber: draftSet.setNumber, reps: reps, weight: weight)
                setEntry.exerciseEntry = entry
                modelContext.insert(setEntry)

                guard reps > 0, weight > 0 else { continue }
                evaluatePR(
                    exerciseName: draftEntry.exerciseName,
                    unit: draftEntry.unit,
                    setEntry: setEntry,
                    date: now
                )
            }
        }

        try? modelContext.save()
        dismiss()
    }

    /// Checks whether `setEntry` is a new personal record and updates the store accordingly.
    /// Weights are always compared in lbs to handle mixed-unit entries (1 kg = 2.20462 lbs).
    private func evaluatePR(exerciseName: String, unit: WeightUnit, setEntry: SetEntry, date: Date) {
        let newWeightLbs = inLbs(setEntry.weight, unit: unit)

        if let existing = allPersonalRecords.first(where: {
            $0.exerciseName == exerciseName && $0.repCount == setEntry.reps
        }) {
            guard newWeightLbs > inLbs(existing.weight, unit: existing.unit) else { return }
            existing.weight = setEntry.weight
            existing.unit = unit
            existing.dateAchieved = date
            setEntry.isPR = true
        } else {
            let pr = PersonalRecord(
                exerciseName: exerciseName,
                repCount: setEntry.reps,
                weight: setEntry.weight,
                unit: unit,
                dateAchieved: date
            )
            modelContext.insert(pr)
            setEntry.isPR = true
        }
    }

    private func inLbs(_ weight: Double, unit: WeightUnit) -> Double {
        unit == .kg ? weight * 2.20462 : weight
    }
}

// MARK: - ExerciseEntryCard

struct ExerciseEntryCard: View {
    @Binding var entry: DraftExerciseEntry
    let onDelete: () -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        Text(entry.exerciseName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !entry.isCardio {
                    Picker("Unit", selection: $entry.unit) {
                        ForEach(WeightUnit.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                }
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            if isExpanded {
                if entry.isCardio {
                    // Cardio: show a single duration input
                    HStack(spacing: 8) {
                        Label("Duration", systemImage: "timer")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("0", text: $entry.cardioMinutesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 52)
                            .padding(.vertical, 7)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("min")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        TextField("0", text: $entry.cardioSecondsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 52)
                            .padding(.vertical, 7)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("sec")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                } else {
                    // Strength: column headers + set rows
                    HStack(spacing: 8) {
                        Text("SET")
                            .frame(width: 36, alignment: .center)
                        Text("REPS")
                            .frame(maxWidth: .infinity)
                        Text("WEIGHT (\(entry.unit.rawValue))")
                            .frame(maxWidth: .infinity)
                        Image(systemName: "star.fill")
                            .opacity(0)
                            .frame(width: 22)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemBackground))

                    ForEach($entry.sets) { $set in
                        SetEntryRow(set: $set)
                        if set.id != entry.sets.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}

// MARK: - SetEntryRow

struct SetEntryRow: View {
    @Binding var set: DraftSet

    var body: some View {
        HStack(spacing: 8) {
            Text("\(set.setNumber)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .center)

            TextField("–", text: $set.repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("–", text: $set.weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Image(systemName: set.isPR ? "star.fill" : "star")
                .foregroundStyle(set.isPR ? .yellow : Color(.systemGray3))
                .frame(width: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - ExercisePickerSheet

struct ExercisePickerSheet: View {
    let muscleGroups: [MuscleGroup]
    /// Called with (exerciseName, isCardio, setCount). setCount is 0 for cardio entries.
    let onAdd: (String, Bool, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var expandedGroups: Set<String> = []
    @State private var selectedExercise: String?
    @State private var showingSetCount = false
    @State private var selectedSetCount: Int = 3

    var body: some View {
        NavigationStack {
            List {
                ForEach(muscleGroups) { group in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedGroups.contains(group.name) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedGroups.insert(group.name)
                                } else {
                                    expandedGroups.remove(group.name)
                                }
                            }
                        )
                    ) {
                        ForEach(group.exercises.sorted { $0.name < $1.name }) { exercise in
                            Button {
                                if exercise.exerciseType == .cardio {
                                    onAdd(exercise.name, true, 0)
                                    dismiss()
                                } else {
                                    selectedExercise = exercise.name
                                    showingSetCount = true
                                }
                            } label: {
                                Text(exercise.name)
                                    .foregroundStyle(.primary)
                            }
                        }
                    } label: {
                        Text(group.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingSetCount) {
                if let name = selectedExercise {
                    setCountView(for: name)
                }
            }
        }
    }

    @ViewBuilder
    private func setCountView(for exerciseName: String) -> some View {
        Form {
            Section {
                Text(exerciseName)
                    .font(.headline)
            } header: {
                Text("Exercise")
            }

            Section {
                Picker("Sets", selection: $selectedSetCount) {
                    ForEach(1...10, id: \.self) { n in
                        Text("\(n) \(n == 1 ? "set" : "sets")").tag(n)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
            } header: {
                Text("Number of Sets")
            }
        }
        .navigationTitle("Configure Sets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    onAdd(exerciseName, false, selectedSetCount)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }
}
