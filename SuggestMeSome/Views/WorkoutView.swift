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
    var isWarmup: Bool

    init(setNumber: Int, repsText: String = "", weightText: String = "", isPR: Bool = false, isWarmup: Bool = false) {
        self.id = UUID()
        self.setNumber = setNumber
        self.repsText = repsText
        self.weightText = weightText
        self.isPR = isPR
        self.isWarmup = isWarmup
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

    // Optional prescription snapshot for program-driven workouts.
    var sourceProgramSessionExerciseID: UUID?
    var prescribedTargetSets: Int?
    var prescribedTargetReps: Int?
    var prescribedTargetPercentage1RM: Double?
    var prescribedTargetRPE: Double?
    var prescribedTargetRIR: Double?
    var prescribedWeight: Double?
    var prescribedWeightUnit: String?
    var prescribedWorkingSetStyle: ProgramWorkingSetStyle?
    var prescribedTargetEffortType: ProgramTargetEffortType?

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
        cardioSecondsText: String = "",
        sourceProgramSessionExerciseID: UUID? = nil,
        prescribedTargetSets: Int? = nil,
        prescribedTargetReps: Int? = nil,
        prescribedTargetPercentage1RM: Double? = nil,
        prescribedTargetRPE: Double? = nil,
        prescribedTargetRIR: Double? = nil,
        prescribedWeight: Double? = nil,
        prescribedWeightUnit: String? = nil,
        prescribedWorkingSetStyle: ProgramWorkingSetStyle? = nil,
        prescribedTargetEffortType: ProgramTargetEffortType? = nil
    ) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.unit = unit
        self.orderIndex = orderIndex
        self.sets = sets
        self.isCardio = isCardio
        self.cardioMinutesText = cardioMinutesText
        self.cardioSecondsText = cardioSecondsText
        self.sourceProgramSessionExerciseID = sourceProgramSessionExerciseID
        self.prescribedTargetSets = prescribedTargetSets
        self.prescribedTargetReps = prescribedTargetReps
        self.prescribedTargetPercentage1RM = prescribedTargetPercentage1RM
        self.prescribedTargetRPE = prescribedTargetRPE
        self.prescribedTargetRIR = prescribedTargetRIR
        self.prescribedWeight = prescribedWeight
        self.prescribedWeightUnit = prescribedWeightUnit
        self.prescribedWorkingSetStyle = prescribedWorkingSetStyle
        self.prescribedTargetEffortType = prescribedTargetEffortType
    }
}

// MARK: - WorkoutView

struct WorkoutView: View {
    var generatedWorkout: GeneratedWorkout? = nil
    var programWorkout: ProgramWorkoutContext? = nil

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
        .onAppear {
            guard exerciseEntries.isEmpty else { return }
            if let gw = generatedWorkout {
                exerciseEntries = gw.exercises.enumerated().map { index, genExercise in
                    if genExercise.exercise.exerciseType == .cardio {
                        let totalSeconds = Int(genExercise.effectiveTimeMinutes * 60)
                        let mins = totalSeconds / 60
                        let secs = totalSeconds % 60
                        return DraftExerciseEntry(
                            exerciseName: genExercise.exercise.name,
                            unit: .lbs,
                            orderIndex: index,
                            sets: [],
                            isCardio: true,
                            cardioMinutesText: mins > 0 ? "\(mins)" : "",
                            cardioSecondsText: secs > 0 ? "\(secs)" : ""
                        )
                    }
                    let unit = genExercise.sets.first?.unit ?? .lbs
                    let draftSets = genExercise.sets.map { genSet in
                        DraftSet(
                            setNumber: genSet.setNumber,
                            repsText: "\(genSet.suggestedReps)",
                            weightText: formatGeneratedWeight(genSet.suggestedWeight),
                            isWarmup: genSet.isWarmup
                        )
                    }
                    return DraftExerciseEntry(
                        exerciseName: genExercise.exercise.name,
                        unit: unit,
                        orderIndex: index,
                        sets: draftSets
                    )
                }
                startTime = Date.now
                isActive = true
            } else if let pw = programWorkout {
                exerciseEntries = buildDraftEntries(from: pw.exercises)
                startTime = Date.now
                isActive = true
            }
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

    private func formatGeneratedWeight(_ w: Double?) -> String {
        guard let w = w else { return "" }
        return w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }

    private func buildDraftEntries(from sessionExercises: [ProgramSessionExercise]) -> [DraftExerciseEntry] {
        let ordered = sessionExercises.sorted { $0.orderIndex < $1.orderIndex }
        let grouped = groupProgramExercises(ordered)

        return grouped.enumerated().map { index, rows in
            let anchor = rows.first(where: { !$0.isWarmup }) ?? rows[0]
            let unit = allPersonalRecords
                .first(where: { $0.exerciseName == anchor.exerciseName })?.unit ?? .lbs

            // Cardio rows carry duration in targetReps (minutes) and no set structure.
            if anchor.targetSets == nil && anchor.targetPercentage1RM == nil && anchor.targetRPE != nil {
                let totalSeconds = (anchor.targetReps ?? 0) * 60
                let mins = totalSeconds / 60
                let secs = totalSeconds % 60
                return DraftExerciseEntry(
                    exerciseName: anchor.exerciseName,
                    unit: unit,
                    orderIndex: index,
                    sets: [],
                    isCardio: true,
                    cardioMinutesText: mins > 0 ? "\(mins)" : "",
                    cardioSecondsText: secs > 0 ? "\(secs)" : "",
                    sourceProgramSessionExerciseID: anchor.id,
                    prescribedTargetSets: anchor.targetSets,
                    prescribedTargetReps: anchor.targetReps,
                    prescribedTargetPercentage1RM: anchor.targetPercentage1RM,
                    prescribedTargetRPE: anchor.targetRPE,
                    prescribedTargetRIR: anchor.targetRIR,
                    prescribedWeight: anchor.prescribedWeight,
                    prescribedWeightUnit: anchor.prescribedWeightUnit,
                    prescribedWorkingSetStyle: anchor.workingSetStyle,
                    prescribedTargetEffortType: anchor.targetEffortType
                )
            }

            var setNumber = 1
            var mergedSets: [DraftSet] = []
            for row in rows {
                let rowSetCount = max(1, row.targetSets ?? (row.isWarmup ? 1 : 3))
                let repsText = row.targetReps.map { "\($0)" } ?? ""
                let weightText = formatGeneratedWeight(row.prescribedWeight)
                for _ in 0..<rowSetCount {
                    mergedSets.append(
                        DraftSet(
                            setNumber: setNumber,
                            repsText: repsText,
                            weightText: weightText,
                            isWarmup: row.isWarmup
                        )
                    )
                    setNumber += 1
                }
            }

            return DraftExerciseEntry(
                exerciseName: anchor.exerciseName,
                unit: unit,
                orderIndex: index,
                sets: mergedSets,
                sourceProgramSessionExerciseID: anchor.id,
                prescribedTargetSets: anchor.targetSets,
                prescribedTargetReps: anchor.targetReps,
                prescribedTargetPercentage1RM: anchor.targetPercentage1RM,
                prescribedTargetRPE: anchor.targetRPE,
                prescribedTargetRIR: anchor.targetRIR,
                prescribedWeight: anchor.prescribedWeight,
                prescribedWeightUnit: anchor.prescribedWeightUnit,
                prescribedWorkingSetStyle: anchor.workingSetStyle,
                prescribedTargetEffortType: anchor.targetEffortType
            )
        }
    }

    private func groupProgramExercises(_ ordered: [ProgramSessionExercise]) -> [[ProgramSessionExercise]] {
        var groups: [[ProgramSessionExercise]] = []

        for exercise in ordered {
            guard let lastGroup = groups.last, let last = lastGroup.last else {
                groups.append([exercise])
                continue
            }

            let shareTopBackoffGroup = {
                guard let a = last.topBackoffGroupID, let b = exercise.topBackoffGroupID else { return false }
                return a == b
            }()
            let contiguousSameExercise =
                last.topBackoffGroupID == nil &&
                exercise.topBackoffGroupID == nil &&
                last.exerciseName == exercise.exerciseName

            if shareTopBackoffGroup || contiguousSameExercise {
                groups[groups.count - 1].append(exercise)
            } else {
                groups.append([exercise])
            }
        }

        return groups
    }

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
            comments: comments.isEmpty ? nil : comments,
            programRun: programWorkout?.programRun,
            programWeekNumber: programWorkout?.weekNumber,
            programSessionNumber: programWorkout?.sessionNumber
        )
        modelContext.insert(workout)

        for draftEntry in exerciseEntries {
            let entry = ExerciseEntry(
                exerciseName: draftEntry.exerciseName,
                unit: draftEntry.unit,
                orderIndex: draftEntry.orderIndex,
                isCardio: draftEntry.isCardio,
                cardioDurationSeconds: draftEntry.isCardio ? draftEntry.cardioDurationSeconds : nil,
                sourceProgramSessionExerciseID: draftEntry.sourceProgramSessionExerciseID,
                prescribedTargetSets: draftEntry.prescribedTargetSets,
                prescribedTargetReps: draftEntry.prescribedTargetReps,
                prescribedTargetPercentage1RM: draftEntry.prescribedTargetPercentage1RM,
                prescribedTargetRPE: draftEntry.prescribedTargetRPE,
                prescribedTargetRIR: draftEntry.prescribedTargetRIR,
                prescribedWeight: draftEntry.prescribedWeight,
                prescribedWeightUnit: draftEntry.prescribedWeightUnit,
                prescribedWorkingSetStyle: draftEntry.prescribedWorkingSetStyle,
                prescribedTargetEffortType: draftEntry.prescribedTargetEffortType
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

        if let pw = programWorkout {
            checkProgramCompletion(run: pw.programRun)
        }

        dismiss()
    }

    private func checkProgramCompletion(run: ProgramRun) {
        guard let program = run.program else { return }
        let expected = program.lengthInWeeks * program.sessionsPerWeek
        let descriptor = FetchDescriptor<Workout>()
        guard let all = try? modelContext.fetch(descriptor) else { return }
        let count = all.filter { $0.programRun?.id == run.id }.count
        if count >= expected {
            run.isCompleted = true
            run.endDate = Date.now
            try? modelContext.save()
        }
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
            Text(set.isWarmup ? "W\(set.setNumber)" : "\(set.setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(set.isWarmup ? Color(.systemGray3) : .secondary)
                .frame(width: 36, alignment: .center)

            TextField("–", text: $set.repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(set.isWarmup ? .secondary : .primary)

            TextField("–", text: $set.weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(set.isWarmup ? .secondary : .primary)

            Image(systemName: set.isPR ? "star.fill" : "star")
                .foregroundStyle(set.isPR ? .yellow : Color(.systemGray3))
                .frame(width: 22)
                .opacity(set.isWarmup ? 0 : 1)
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
