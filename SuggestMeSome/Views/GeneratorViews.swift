import SwiftUI
import SwiftData

// MARK: - Generator Inputs (passed from input view → preview)

struct GeneratorInputs {
    let type: WorkoutGenerationType
    let durationMinutes: Int
    let intensity: Int
    let muscleGroups: [MuscleGroup]
    let exercises: [Exercise]
}

// MARK: - Sheet Root (owns the NavigationStack for the generator flow)

struct GeneratorSheetRootView: View {
    let type: WorkoutGenerationType
    let onStart: (GeneratedWorkout) -> Void

    var body: some View {
        NavigationStack {
            if type == .custom {
                CustomWorkoutInputView(onStart: onStart)
            } else {
                FullBodyWorkoutInputView(onStart: onStart)
            }
        }
    }
}

// MARK: - Custom Workout Input

struct CustomWorkoutInputView: View {
    let onStart: (GeneratedWorkout) -> Void

    @AppStorage("generator.custom.duration")  private var duration  = 60
    @AppStorage("generator.custom.intensity") private var intensity = 3
    @AppStorage("generator.custom.groups")    private var savedGroups    = ""
    @AppStorage("generator.custom.exercises") private var savedExercises = ""

    @State private var selectedGroupNames:    Set<String> = []
    @State private var selectedExerciseNames: Set<String> = []
    @State private var showingExercisePicker = false
    @State private var generatedWorkout: GeneratedWorkout?
    @State private var showPreview = false

    @Query(sort: \MuscleGroup.name) private var allGroups: [MuscleGroup]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    private var nonCardioGroups: [MuscleGroup] {
        allGroups.filter { $0.name.lowercased() != "cardio" }
    }

    private var selectedGroupObjects: [MuscleGroup] {
        allGroups.filter { selectedGroupNames.contains($0.name) }
    }

    private var selectedExerciseObjects: [Exercise] {
        allGroups.flatMap(\.exercises).filter { selectedExerciseNames.contains($0.name) }
    }

    private var canGenerate: Bool {
        !selectedGroupNames.isEmpty || !selectedExerciseNames.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                muscleGroupSection
                exerciseSection
                DurationPickerView(duration: $duration)
                IntensitySelectorView(intensity: $intensity)
                generateButton
            }
            .padding()
        }
        .navigationTitle("Custom Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            selectedGroupNames    = decodeSet(savedGroups)
            selectedExerciseNames = decodeSet(savedExercises)
        }
        .sheet(isPresented: $showingExercisePicker) {
            GeneratorExercisePickerSheet(
                muscleGroups: nonCardioGroups,
                selectedNames: $selectedExerciseNames
            )
        }
        .navigationDestination(isPresented: $showPreview) {
            if let gw = generatedWorkout {
                GeneratedWorkoutPreviewView(
                    initialWorkout: gw,
                    inputs: GeneratorInputs(
                        type: .custom,
                        durationMinutes: duration,
                        intensity: intensity,
                        muscleGroups: selectedGroupObjects,
                        exercises: selectedExerciseObjects
                    ),
                    onStart: onStart
                )
            }
        }
    }

    // MARK: Sections

    private var muscleGroupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Muscle Groups", systemImage: "figure.strengthtraining.traditional")
                .font(.headline)
            let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(nonCardioGroups, id: \.name) { group in
                    chipButton(group.name, isOn: selectedGroupNames.contains(group.name)) {
                        toggle(&selectedGroupNames, value: group.name)
                    }
                }
            }
        }
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Specific Exercises", systemImage: "dumbbell")
                    .font(.headline)
                Spacer()
                Text("Optional").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                showingExercisePicker = true
            } label: {
                HStack {
                    Group {
                        if selectedExerciseNames.isEmpty {
                            Text("None selected").foregroundStyle(.secondary)
                        } else {
                            Text(selectedExerciseNames.sorted().joined(separator: ", "))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var generateButton: some View {
        Button {
            savedGroups    = encodeSet(selectedGroupNames)
            savedExercises = encodeSet(selectedExerciseNames)
            let service = WorkoutGeneratorService(context: modelContext)
            generatedWorkout = service.generateCustomWorkout(
                muscleGroups: selectedGroupObjects,
                selectedExercises: selectedExerciseObjects,
                durationMinutes: Double(duration),
                intensity: intensity
            )
            showPreview = true
        } label: {
            Label("Generate Workout", systemImage: "wand.and.stars")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canGenerate ? Color.purple : Color(.systemGray4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!canGenerate)
    }

    // MARK: Helpers

    private func chipButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isOn ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(isOn ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func toggle(_ set: inout Set<String>, value: String) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func decodeSet(_ s: String) -> Set<String> {
        Set(s.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func encodeSet(_ set: Set<String>) -> String {
        set.sorted().joined(separator: ",")
    }
}

// MARK: - Full Body Workout Input

struct FullBodyWorkoutInputView: View {
    let onStart: (GeneratedWorkout) -> Void

    @AppStorage("generator.fb.duration")  private var duration  = 60
    @AppStorage("generator.fb.intensity") private var intensity = 3

    @State private var generatedWorkout: GeneratedWorkout?
    @State private var showPreview = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DurationPickerView(duration: $duration)
                IntensitySelectorView(intensity: $intensity)
                generateButton
            }
            .padding()
        }
        .navigationTitle("Full Body Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .navigationDestination(isPresented: $showPreview) {
            if let gw = generatedWorkout {
                GeneratedWorkoutPreviewView(
                    initialWorkout: gw,
                    inputs: GeneratorInputs(
                        type: .fullBody,
                        durationMinutes: duration,
                        intensity: intensity,
                        muscleGroups: [],
                        exercises: []
                    ),
                    onStart: onStart
                )
            }
        }
    }

    private var generateButton: some View {
        Button {
            let service = WorkoutGeneratorService(context: modelContext)
            generatedWorkout = service.generateFullBodyWorkout(
                durationMinutes: Double(duration),
                intensity: intensity
            )
            showPreview = true
        } label: {
            Label("Generate Workout", systemImage: "wand.and.stars")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.purple)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Shared: Duration Picker

private let durationPresets = [30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180]

struct DurationPickerView: View {
    @Binding var duration: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Duration", systemImage: "clock")
                .font(.headline)
            let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(durationPresets, id: \.self) { preset in
                    Button {
                        duration = preset
                    } label: {
                        Text("\(preset)m")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(duration == preset ? Color.blue : Color(.secondarySystemBackground))
                            .foregroundStyle(duration == preset ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

// MARK: - Shared: Intensity Selector

private let intensityDescriptions: [Int: String] = [
    1: "Light / High Volume",
    2: "Moderate-Light",
    3: "Moderate",
    4: "Moderate-Heavy",
    5: "Heavy / Low Volume"
]

private func intensityAccentColor(_ level: Int) -> Color {
    switch level {
    case 1:  return .green
    case 2:  return Color(red: 0.1, green: 0.7, blue: 0.45)
    case 3:  return .blue
    case 4:  return .orange
    default: return .red
    }
}

struct IntensitySelectorView: View {
    @Binding var intensity: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Intensity", systemImage: "bolt.fill")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { intensity = level }
                    } label: {
                        Text("\(level)")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                intensity == level
                                    ? intensityAccentColor(level)
                                    : Color(.secondarySystemBackground)
                            )
                            .foregroundStyle(intensity == level ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if let desc = intensityDescriptions[intensity] {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .id(intensity)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Exercise Picker Sheet (for Custom workout's optional exercise selection)

struct GeneratorExercisePickerSheet: View {
    let muscleGroups: [MuscleGroup]
    @Binding var selectedNames: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(muscleGroups) { group in
                    let eligibleExercises = group.exercises
                        .filter { $0.exerciseType != .cardio }
                        .sorted { $0.name < $1.name }
                    if !eligibleExercises.isEmpty {
                        Section {
                            if expandedGroups.contains(group.name) {
                                ForEach(eligibleExercises) { exercise in
                                    exerciseRow(exercise)
                                }
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(selectedNames.isEmpty ? "Select Exercises" : "\(selectedNames.count) selected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !selectedNames.isEmpty {
                        Button("Clear All") { selectedNames = [] }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func groupHeader(_ group: MuscleGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.name)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded { expandedGroups.remove(group.name) }
                else          { expandedGroups.insert(group.name) }
            }
        } label: {
            HStack {
                Text(group.name).font(.headline).foregroundStyle(.primary).textCase(nil)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let isSelected = selectedNames.contains(exercise.name)
        return Button {
            if isSelected { selectedNames.remove(exercise.name) }
            else          { selectedNames.insert(exercise.name) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : Color(.systemGray3))
                    .font(.title3)
                Text(exercise.name).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.leading, 8)
        }
    }
}

// MARK: - Generated Workout Preview

struct GeneratedWorkoutPreviewView: View {
    @State private var currentWorkout: GeneratedWorkout
    let inputs: GeneratorInputs
    let onStart: (GeneratedWorkout) -> Void

    @Environment(\.modelContext) private var modelContext

    init(initialWorkout: GeneratedWorkout, inputs: GeneratorInputs, onStart: @escaping (GeneratedWorkout) -> Void) {
        self._currentWorkout = State(initialValue: initialWorkout)
        self.inputs = inputs
        self.onStart = onStart
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryHeader
                if currentWorkout.exercises.isEmpty {
                    ContentUnavailableView(
                        "No Exercises Generated",
                        systemImage: "dumbbell",
                        description: Text("Try a longer duration or add more muscle groups.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(currentWorkout.exercises.indices, id: \.self) { i in
                        previewExerciseCard(currentWorkout.exercises[i])
                    }
                }
                if !currentWorkout.exercises.isEmpty {
                    startButton
                }
            }
            .padding()
        }
        .navigationTitle("Workout Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    shuffle()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
            }
        }
    }

    // MARK: Summary header

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            Label("\(inputs.durationMinutes)m", systemImage: "clock")
            Text("·").foregroundStyle(.secondary)
            Label("Intensity \(inputs.intensity)", systemImage: "bolt.fill")
                .foregroundStyle(intensityAccentColor(inputs.intensity))
            Text("·").foregroundStyle(.secondary)
            let count = currentWorkout.exercises.count
            Label("\(count) \(count == 1 ? "exercise" : "exercises")", systemImage: "dumbbell")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Exercise card

    private func previewExerciseCard(_ genExercise: GeneratedExercise) -> some View {
        let warmupSets  = genExercise.sets.filter  { $0.isWarmup }
        let workingSets = genExercise.sets.filter  { !$0.isWarmup }
        let unit        = genExercise.sets.first?.unit ?? .lbs

        return VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack {
                Text(genExercise.exercise.name).font(.headline)
                Spacer()
                Text(genExercise.exercise.exerciseType.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            // Column headers
            HStack(spacing: 8) {
                Text("SET").frame(width: 40, alignment: .center)
                Text("REPS").frame(maxWidth: .infinity)
                Text("WEIGHT (\(unit.rawValue))").frame(maxWidth: .infinity)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground))

            // Warmup sets
            if !warmupSets.isEmpty {
                sectionLabel("WARMUP")
                ForEach(warmupSets.indices, id: \.self) { i in
                    previewSetRow(warmupSets[i], isWarmup: true)
                    if i < warmupSets.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }

            // Working sets
            if !workingSets.isEmpty {
                sectionLabel("WORKING")
                ForEach(workingSets.indices, id: \.self) { i in
                    previewSetRow(workingSets[i], isWarmup: false)
                    if i < workingSets.count - 1 {
                        Divider().padding(.leading, 12)
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
    }

    private func previewSetRow(_ set: GeneratedSet, isWarmup: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isWarmup ? "W\(set.setNumber)" : "\(set.setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isWarmup ? Color(.systemGray3) : .secondary)
                .frame(width: 40, alignment: .center)

            Text("\(set.suggestedReps)")
                .frame(maxWidth: .infinity, alignment: .center)

            Text(set.suggestedWeight.map { formatWeight($0) } ?? "—")
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(set.suggestedWeight == nil ? Color(.systemGray3) : .primary)
        }
        .font(.subheadline)
        .foregroundStyle(isWarmup ? .secondary : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: Start button

    private var startButton: some View {
        Button {
            onStart(currentWorkout)
        } label: {
            Label("Start This Workout", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }

    // MARK: Shuffle

    private func shuffle() {
        let service = WorkoutGeneratorService(context: modelContext)
        switch inputs.type {
        case .custom:
            currentWorkout = service.generateCustomWorkout(
                muscleGroups: inputs.muscleGroups,
                selectedExercises: inputs.exercises,
                durationMinutes: Double(inputs.durationMinutes),
                intensity: inputs.intensity
            )
        case .fullBody:
            currentWorkout = service.generateFullBodyWorkout(
                durationMinutes: Double(inputs.durationMinutes),
                intensity: inputs.intensity
            )
        }
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }
}
