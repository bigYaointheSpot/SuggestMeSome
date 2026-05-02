//
//  WorkoutSubviews.swift
//  SuggestMeSome
//
//  Subviews extracted from WorkoutView in Feature 22 Prompt 1.
//  Behavior unchanged.
//

import SwiftUI
import SwiftData

struct WorkoutSessionChromeSection: View {
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore

    let startTime: Date?
    let isActive: Bool
    let lifecycleState: WatchWorkoutLifecycleState
    let onTogglePauseResume: () -> Void
    let onStartWorkout: () -> Void

    private var timerPresentation: WorkoutElapsedTimerPresentation {
        WorkoutElapsedTimerPresentation(
            isActive: isActive,
            startTime: startTime,
            session: activeWorkoutSessionStore.session
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            WorkoutElapsedTimerText(presentation: timerPresentation)

            if isActive {
                WorkoutSessionStatusRow(
                    lifecycleState: lifecycleState,
                    usesLinkedWatchHealthSession: activeWorkoutSessionStore.session?.usesLinkedWatchHealthSession == true,
                    latestWatchMetrics: activeWorkoutSessionStore.latestWatchMetrics
                )

                Button(action: onTogglePauseResume) {
                    Label(
                        lifecycleState == .paused ? "Resume Workout" : "Pause Workout",
                        systemImage: lifecycleState == .paused ? "play.circle.fill" : "pause.circle.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(lifecycleState == .paused ? .green : .orange)
                }
            } else {
                Button(action: onStartWorkout) {
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
}

struct WorkoutSessionStatusRow: View {
    let lifecycleState: WatchWorkoutLifecycleState
    let usesLinkedWatchHealthSession: Bool
    let latestWatchMetrics: WatchWorkoutMetricsPayload?

    @ViewBuilder
    var body: some View {
        if lifecycleState == .paused {
            Label("Workout Paused", systemImage: "pause.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        } else if usesLinkedWatchHealthSession, let latestWatchMetrics {
            HStack(spacing: 16) {
                if let heartRate = latestWatchMetrics.heartRateBPM {
                    Label("\(Int(heartRate.rounded())) bpm", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                }
                if let activeEnergy = latestWatchMetrics.activeEnergyKilocalories {
                    Label("\(Int(activeEnergy.rounded())) kcal", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline.weight(.medium))
        }
    }
}

struct WorkoutElapsedTimerText: View {
    let presentation: WorkoutElapsedTimerPresentation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(presentation.formattedElapsed(at: context.date))
                .dsMetricLarge()
                .fontWeight(.thin)
                .dsHeroGradientFill()
                .animation(.snappy(duration: 0.25), value: presentation.formattedElapsed(at: context.date))
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Elapsed time \(presentation.formattedElapsed(at: context.date))")
        }
    }
}

// MARK: - Focus identity for set-entry text fields

enum WorkoutSetField: Hashable {
    case reps(UUID)
    case weight(UUID)
}

// MARK: - ExerciseEntryCard

struct ExerciseEntryCard: View {
    @Binding var entry: DraftExerciseEntry
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool = true
    @State private var showRPEField: Bool = false
    @FocusState private var focusedField: WorkoutSetField?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: DSSpacing.m) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: DSSpacing.s) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.exerciseName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(progressSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(entry.exerciseName)" : "Expand \(entry.exerciseName)")
                Spacer()
                if !entry.isCardio {
                    Picker("Unit", selection: $entry.unit) {
                        ForEach(WeightUnit.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                    .accessibilityLabel("Weight unit")
                }
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(DSColor.signalCritical)
                }
                .accessibilityLabel("Remove \(entry.exerciseName)")
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s + 2)
            .background(DSColor.surface)

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
                        SetEntryRow(
                            set: $set,
                            focusedField: $focusedField,
                            onSubmitReps: { advanceFocusFromReps(setID: set.id) },
                            onSubmitWeight: { advanceFocusFromWeight(setID: set.id) },
                            onDelete: { deleteSet(id: set.id) },
                            onToggleWarmup: { toggleWarmup(id: set.id) }
                        )
                        if set.id != entry.sets.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }

                    // Effort capture — only show when there are actual working sets.
                    let hasWorkingSets = entry.sets.contains { !$0.isWarmup }
                    if hasWorkingSets {
                        Divider()
                        effortCaptureSection
                    }
                }
            }
            progressRail
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    // MARK: - Progress Helpers

    // MARK: - Focus & Set Mutation

    private func advanceFocusFromReps(setID: UUID) {
        focusedField = .weight(setID)
    }

    private func advanceFocusFromWeight(setID: UUID) {
        guard let idx = entry.sets.firstIndex(where: { $0.id == setID }) else {
            focusedField = nil
            return
        }
        let nextIdx = idx + 1
        if nextIdx < entry.sets.count {
            focusedField = .reps(entry.sets[nextIdx].id)
        } else {
            focusedField = nil
        }
    }

    private func deleteSet(id: UUID) {
        if case .reps(id) = focusedField { focusedField = nil }
        if case .weight(id) = focusedField { focusedField = nil }
        entry.sets.removeAll { $0.id == id }
        for idx in entry.sets.indices {
            entry.sets[idx].setNumber = idx + 1
        }
    }

    private func toggleWarmup(id: UUID) {
        guard let idx = entry.sets.firstIndex(where: { $0.id == id }) else { return }
        entry.sets[idx].isWarmup.toggle()
    }

    /// One-line subtitle under the exercise name. Summarizes logged/total
    /// sets for strength entries, or duration target for cardio. Mirrors
    /// the watch's exercise summary so the two surfaces read the same.
    private var progressSubtitle: String {
        if entry.isCardio {
            let minutes = Int(entry.cardioMinutesText) ?? 0
            let seconds = Int(entry.cardioSecondsText) ?? 0
            if minutes == 0 && seconds == 0 { return "Cardio" }
            return String(format: "Cardio · %d:%02d", minutes, seconds)
        }
        let total = entry.sets.count
        guard total > 0 else { return "No sets" }
        let logged = entry.sets.filter { WatchPayloadMapper.isSetLogged($0) }.count
        return "\(logged) of \(total) sets"
    }

    /// Fraction of the exercise completed, used by the progress rail. Cardio
    /// is binary (logged or not) because duration is captured in a single
    /// input rather than per-set increments.
    private var progressFraction: Double {
        if entry.isCardio {
            return WatchPayloadMapper.isExerciseComplete(entry) ? 1 : 0
        }
        let total = entry.sets.count
        guard total > 0 else { return 0 }
        let logged = entry.sets.filter { WatchPayloadMapper.isSetLogged($0) }.count
        return min(1, Double(logged) / Double(total))
    }

    private var progressRail: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DSColor.signalPositive.opacity(0.15))
                Capsule()
                    .fill(DSColor.signalPositive)
                    .frame(width: max(0, geo.size.width * progressFraction))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progressFraction)
            }
        }
        .frame(height: 2)
    }

    // MARK: - Effort Capture

    @ViewBuilder
    private var effortCaptureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Segmented effort picker
            HStack(spacing: 0) {
                ForEach([WorkoutEffortFeedback.tooEasy, .onTarget, .tooHard], id: \.self) { option in
                    let isSelected = entry.effortFeedback == option
                    Button {
                        // Tapping the active option deselects it.
                        entry.effortFeedback = isSelected ? nil : option
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSelected ? option.tintColor.opacity(0.2) : Color.clear)
                            .foregroundStyle(isSelected ? option.tintColor : Color(.secondaryLabel))
                    }
                    .buttonStyle(.plain)
                    if option != .tooHard {
                        Divider().frame(height: 24)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // RPE toggle row
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showRPEField.toggle()
                        if !showRPEField { entry.topSetRPE = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showRPEField ? "minus.circle" : "plus.circle")
                            .font(.caption)
                        Text("Top-set RPE")
                            .font(.caption)
                    }
                    .foregroundStyle(Color(.secondaryLabel))
                }
                .buttonStyle(.plain)

                if showRPEField {
                    Spacer()
                    RPEStepperField(rpe: Binding(
                        get: { entry.topSetRPE },
                        set: { entry.topSetRPE = $0 }
                    ))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - RPEStepperField

struct RPEStepperField: View {
    @Binding var rpe: Double?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                let current = rpe ?? 7.0
                rpe = max(1.0, current - 0.5)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease RPE")

            Text(rpe.map { String(format: $0.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", $0) } ?? "—")
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, alignment: .center)
                .accessibilityLabel(rpe.map { "RPE \(String(format: "%.1f", $0))" } ?? "RPE not set")

            Button {
                let current = rpe ?? 6.5
                rpe = min(10.0, current + 0.5)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase RPE")
        }
    }
}

// MARK: - WorkoutEffortFeedback UI extensions

private extension WorkoutEffortFeedback {
    var label: String {
        switch self {
        case .tooEasy:  return "Too Easy"
        case .onTarget: return "On Target"
        case .tooHard:  return "Too Hard"
        }
    }

    var tintColor: Color {
        switch self {
        case .tooEasy:  return .blue
        case .onTarget: return .green
        case .tooHard:  return .orange
        }
    }
}

// MARK: - SetEntryRow

struct SetEntryRow: View {
    @Binding var set: DraftSet
    @FocusState.Binding var focusedField: WorkoutSetField?
    let onSubmitReps: () -> Void
    let onSubmitWeight: () -> Void
    let onDelete: () -> Void
    let onToggleWarmup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var starScale: CGFloat = 1.0
    @State private var starGlowRadius: CGFloat = 0

    private var hasEntryData: Bool {
        !set.repsText.isEmpty && !set.weightText.isEmpty && !set.isWarmup
    }

    /// Single-swipe VoiceOver summary for the whole row. Individual fields
    /// stay focusable for editing (via `accessibilityElement(.contain)`);
    /// this label lets users scan the set log quickly before drilling in.
    private var rowAccessibilitySummary: String {
        let kind = set.isWarmup ? "Warm-up set \(set.setNumber)" : "Set \(set.setNumber)"
        let reps = set.repsText.isEmpty ? "no reps" : "\(set.repsText) reps"
        let weight = set.weightText.isEmpty ? "no weight" : "\(set.weightText) pounds"
        let prTag = set.isPR ? ", personal record" : ""
        return "\(kind), \(reps) at \(weight)\(prTag)"
    }

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
                .focused($focusedField, equals: .reps(set.id))
                .submitLabel(.next)
                .onSubmit(onSubmitReps)
                .onChange(of: set.repsText) { _, newValue in
                    let sanitized = SetEntryRow.sanitizeReps(newValue)
                    if sanitized != newValue { set.repsText = sanitized }
                }
                .accessibilityLabel("Reps for set \(set.setNumber)")

            TextField("–", text: $set.weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(set.isWarmup ? .secondary : .primary)
                .focused($focusedField, equals: .weight(set.id))
                .submitLabel(.done)
                .onSubmit(onSubmitWeight)
                .onChange(of: set.weightText) { _, newValue in
                    let sanitized = SetEntryRow.sanitizeWeight(newValue)
                    if sanitized != newValue { set.weightText = sanitized }
                }
                .accessibilityLabel("Weight for set \(set.setNumber)")

            Image(systemName: set.isPR ? "star.fill" : "star")
                .foregroundStyle(set.isPR ? .yellow : Color(.systemGray3))
                .frame(width: 22)
                .opacity(set.isWarmup ? 0 : 1)
                .scaleEffect(starScale)
                .shadow(color: Color.yellow.opacity(starGlowRadius > 0 ? 0.8 : 0), radius: starGlowRadius)
                .onChange(of: set.isPR) { _, newValue in
                    guard newValue else { return }
                    // Honor Reduce Motion — skip the scale-up/scale-down
                    // bounce entirely and keep the star visually stable.
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: 0.5)) {
                        starScale = 1.6
                        starGlowRadius = 12
                    }
                    withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
                        starScale = 1.0
                        starGlowRadius = 0
                    }
                }
                .accessibilityLabel(set.isPR ? "Personal record" : "Not a personal record")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onToggleWarmup()
            } label: {
                Label(
                    set.isWarmup ? "Mark as working set" : "Mark as warm-up",
                    systemImage: set.isWarmup ? "flame" : "flame.fill"
                )
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete set", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowAccessibilitySummary)
        .accessibilityHint("Long-press for warm-up or delete actions.")
        .sensoryFeedback(.success, trigger: hasEntryData)
        .sensoryFeedback(.increase, trigger: set.isPR)
    }

    // MARK: - Sanitizers

    /// Reps: digits only, capped at 4 characters. Mutates in place as a
    /// String (never round-trips through Int) so DraftSet persistence stays
    /// exact.
    static func sanitizeReps(_ input: String) -> String {
        String(input.filter(\.isNumber).prefix(4))
    }

    /// Weight: digits plus at most one decimal separator (`.` or `,` —
    /// whichever the user typed first). Capped at 6 characters. Mutates in
    /// place as a String so DraftSet persistence stays exact.
    static func sanitizeWeight(_ input: String) -> String {
        let separator: Character = (input.contains(",") && !input.contains(".")) ? "," : "."
        var seenSeparator = false
        var result = ""
        for char in input {
            if char.isNumber {
                result.append(char)
            } else if char == separator && !seenSeparator {
                result.append(char)
                seenSeparator = true
            }
        }
        return String(result.prefix(6))
    }
}

// MARK: - ExercisePickerSheet

struct ExercisePickerSheet: View {
    let muscleGroups: [MuscleGroup]
    /// Called with (exerciseName, isCardio, setCount). setCount is 0 for cardio entries.
    let onAdd: (String, Bool, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var expandedGroups: Set<String> = []
    @State private var selectedExercise: String?
    @State private var showingSetCount = false
    @State private var selectedSetCount: Int = 3

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var flatMatches: [(group: MuscleGroup, exercise: Exercise)] {
        guard !trimmedQuery.isEmpty else { return [] }
        var rows: [(MuscleGroup, Exercise)] = []
        for group in muscleGroups {
            for exercise in group.exercises.sorted(by: { $0.name < $1.name })
            where exercise.name.localizedCaseInsensitiveContains(trimmedQuery) {
                rows.append((group, exercise))
            }
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    groupedList
                } else if flatMatches.isEmpty {
                    DSEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No exercises match '\(trimmedQuery)'",
                        message: "Add a new exercise with this name and we'll configure its sets next.",
                        cta: .init(
                            title: "Create '\(trimmedQuery)'",
                            systemImage: "plus.circle.fill"
                        ) {
                            selectedExercise = trimmedQuery
                            showingSetCount = true
                        }
                    )
                } else {
                    matchesList
                }
            }
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search exercises"
            )
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

    private var groupedList: some View {
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
                        Button { selectExercise(exercise) } label: {
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
    }

    private var matchesList: some View {
        List {
            ForEach(Array(flatMatches.enumerated()), id: \.offset) { _, row in
                Button { selectExercise(row.exercise) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.exercise.name)
                            .foregroundStyle(.primary)
                        Text(row.group.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func selectExercise(_ exercise: Exercise) {
        if exercise.exerciseType == .cardio {
            onAdd(exercise.name, true, 0)
            dismiss()
        } else {
            selectedExercise = exercise.name
            showingSetCount = true
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

// MARK: - List row helpers

extension View {
    /// Applies the baseline row treatment used by the live-workout List:
    /// zero separator, transparent row background, and token-driven insets.
    /// Centralized so every section row reads consistently without
    /// repeating five modifiers.
    func plainWorkoutRow(
        horizontalInset: CGFloat = DSSpacing.l,
        verticalInset: CGFloat = DSSpacing.s
    ) -> some View {
        self
            .listRowInsets(EdgeInsets(
                top: verticalInset,
                leading: horizontalInset,
                bottom: verticalInset,
                trailing: horizontalInset
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
