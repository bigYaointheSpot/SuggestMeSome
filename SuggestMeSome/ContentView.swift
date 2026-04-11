//
//  ContentView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

// MARK: - ContentView

struct ContentView: View {
    @State private var selectedTab = 0
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"

    private var preferredColorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DailyCoachView()
                .tabItem {
                    Label("Daily Coach", systemImage: "brain.head.profile")
                }
                .tag(0)
            DashboardView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(1)
            WorkoutsTab()
                .tabItem {
                    Label("Workouts", systemImage: "dumbbell")
                }
                .tag(2)
            TrainingProgramsTab()
                .tabItem {
                    Label("Training Programs", systemImage: "list.clipboard")
                }
                .tag(3)
            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
        .preferredColorScheme(preferredColorScheme)
    }
}

// MARK: - WorkoutsTab

struct WorkoutsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]
    @Query(filter: #Predicate<ProgramRun> { run in run.isCompleted == false })
    private var activeProgramRuns: [ProgramRun]

    // MARK: Filter state
    @State private var filterByDate = false
    @State private var filterStartDate = Calendar.current.startOfDay(for: Date())
    @State private var filterEndDate = Date()
    @State private var selectedGroupNames: Set<String> = []
    @State private var selectedExerciseNames: Set<String> = []
    @State private var filterPROnly = false
    @State private var showingExerciseFilter = false

    // MARK: Delete confirmation
    @State private var workoutToDelete: Workout?

    // MARK: Generator flow
    @State private var showingGeneratorSheet   = false
    @State private var pendingGeneratedWorkout: GeneratedWorkout?
    @State private var showingGeneratedWorkout = false

    // MARK: Program workout flow
    @State private var showingCompleteProgramSheet = false
    @State private var pendingProgramWorkout: ProgramWorkoutContext?
    @State private var showingProgramWorkout = false

    // MARK: - Computed

    var exerciseFilterActive: Bool {
        !selectedGroupNames.isEmpty || !selectedExerciseNames.isEmpty
    }

    var exerciseFilterLabel: String {
        let total = selectedGroupNames.count + selectedExerciseNames.count
        switch total {
        case 0:  return "Exercise"
        case 1:  return selectedGroupNames.first ?? selectedExerciseNames.first ?? "Exercise"
        default: return "\(total) selected"
        }
    }

    var isFiltered: Bool {
        filterByDate || exerciseFilterActive || filterPROnly
    }

    var filteredWorkouts: [Workout] {
        workouts.filter { workout in
            if filterByDate {
                let dayStart = Calendar.current.startOfDay(for: filterStartDate)
                let dayEnd   = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: filterEndDate)!
                guard workout.date >= dayStart && workout.date <= dayEnd else { return false }
            }

            if exerciseFilterActive {
                let namesFromGroups: Set<String> = selectedGroupNames.reduce(into: []) { result, groupName in
                    if let group = muscleGroups.first(where: { $0.name == groupName }) {
                        result.formUnion(group.exercises.map(\.name))
                    }
                }
                let allAllowedNames = namesFromGroups.union(selectedExerciseNames)
                guard workout.exerciseEntries.contains(where: { allAllowedNames.contains($0.exerciseName) }) else { return false }
            }

            if filterPROnly {
                guard workout.exerciseEntries.contains(where: { $0.sets.contains(where: \.isPR) }) else { return false }
            }
            return true
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                actionButtonRow
                filterBar
                Divider()
                workoutList
            }
            .navigationTitle("SuggestMeSome")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingExerciseFilter) {
                ExerciseFilterSheet(
                    muscleGroups: muscleGroups,
                    selectedGroupNames: $selectedGroupNames,
                    selectedExerciseNames: $selectedExerciseNames
                )
            }
            .sheet(isPresented: $showingGeneratorSheet, onDismiss: {
                if pendingGeneratedWorkout != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingGeneratedWorkout = true
                    }
                }
            }) {
                GeneratorSheetRootView { gw in
                    pendingGeneratedWorkout = gw
                    showingGeneratorSheet = false
                }
            }
            .navigationDestination(isPresented: $showingGeneratedWorkout) {
                WorkoutView(generatedWorkout: pendingGeneratedWorkout)
            }
            .sheet(isPresented: $showingCompleteProgramSheet, onDismiss: {
                if pendingProgramWorkout != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showingProgramWorkout = true
                    }
                }
            }) {
                CompleteProgramWorkoutSheet(activeRuns: Array(activeProgramRuns)) { ctx in
                    pendingProgramWorkout = ctx
                    showingCompleteProgramSheet = false
                }
            }
            .navigationDestination(isPresented: $showingProgramWorkout) {
                if let pw = pendingProgramWorkout {
                    WorkoutView(programWorkout: pw)
                }
            }
            .alert("Delete Workout?", isPresented: .init(
                get: { workoutToDelete != nil },
                set: { if !$0 { workoutToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let w = workoutToDelete { modelContext.delete(w) }
                    workoutToDelete = nil
                }
                Button("Cancel", role: .cancel) { workoutToDelete = nil }
            } message: {
                Text("This workout and all its data will be permanently deleted.")
            }
        }
    }

    // MARK: - Sub-views

    private var actionButtonRow: some View {
        HStack(spacing: 8) {
            NavigationLink {
                WorkoutView()
            } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                showingGeneratorSheet = true
            } label: {
                Label("SuggestMeSome", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.purple)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !activeProgramRuns.isEmpty {
                Button {
                    showingCompleteProgramSheet = true
                } label: {
                    Label("Complete Program", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Date range chip
                filterChip(
                    label: filterByDate ? "Date On" : "Date Range",
                    systemImage: "calendar",
                    isActive: filterByDate
                ) { filterByDate.toggle() }

                if filterByDate {
                    DatePicker("", selection: $filterStartDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Text("–").foregroundStyle(.secondary)
                    DatePicker("", selection: $filterEndDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                // Exercise filter chip
                Button { showingExerciseFilter = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                        Text(exerciseFilterLabel).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(exerciseFilterActive ? Color.blue.opacity(0.25) : Color(.secondarySystemBackground))
                    .foregroundStyle(exerciseFilterActive ? Color.blue : Color.primary)
                    .clipShape(Capsule())
                }

                // PR toggle chip
                filterChip(
                    label: "PRs Only",
                    systemImage: filterPROnly ? "star.fill" : "star",
                    isActive: filterPROnly,
                    tint: .yellow
                ) { filterPROnly.toggle() }

                // Clear all filters
                if isFiltered {
                    Button {
                        filterByDate = false
                        selectedGroupNames = []
                        selectedExerciseNames = []
                        filterPROnly = false
                    } label: {
                        Text("Clear")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func filterChip(
        label: String,
        systemImage: String,
        isActive: Bool,
        tint: Color = .blue,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .foregroundStyle(isActive ? tint : .secondary)
                Text(label)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isActive ? tint.opacity(0.25) : Color(.secondarySystemBackground))
            .foregroundStyle(isActive ? tint : .primary)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var workoutList: some View {
        if filteredWorkouts.isEmpty {
            ContentUnavailableView(
                isFiltered ? "No Matching Workouts" : "No Workouts Yet",
                systemImage: "dumbbell.fill",
                description: Text(isFiltered
                    ? "Try adjusting your filters."
                    : "Tap Start Workout above to begin.")
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(filteredWorkouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        WorkoutRow(workout: workout)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            workoutToDelete = workout
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - ExerciseFilterSheet

struct ExerciseFilterSheet: View {
    let muscleGroups: [MuscleGroup]
    @Binding var selectedGroupNames: Set<String>
    @Binding var selectedExerciseNames: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var expandedGroups: Set<String> = []

    var totalSelected: Int { selectedGroupNames.count + selectedExerciseNames.count }

    var body: some View {
        NavigationStack {
            List {
                ForEach(muscleGroups) { group in
                    Section {
                        if expandedGroups.contains(group.name) {
                            ForEach(group.exercises.sorted { $0.name < $1.name }) { exercise in
                                exerciseRow(exercise)
                            }
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(totalSelected == 0 ? "Filter by Exercise" : "\(totalSelected) selected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if totalSelected > 0 {
                        Button("Clear All") {
                            selectedGroupNames = []
                            selectedExerciseNames = []
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Group header row
    // Left side tap  → toggle the whole group as a selection
    // Right chevron  → expand / collapse exercises

    private func groupHeader(_ group: MuscleGroup) -> some View {
        let groupSelected = selectedGroupNames.contains(group.name)
        let isExpanded    = expandedGroups.contains(group.name)

        return HStack(spacing: 0) {
            Button {
                if groupSelected {
                    selectedGroupNames.remove(group.name)
                } else {
                    selectedGroupNames.insert(group.name)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: groupSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(groupSelected ? .blue : Color(.systemGray3))
                        .font(.title3)
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedGroups.remove(group.name)
                    } else {
                        expandedGroups.insert(group.name)
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Exercise row

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let isSelected = selectedExerciseNames.contains(exercise.name)

        return Button {
            if isSelected {
                selectedExerciseNames.remove(exercise.name)
            } else {
                selectedExerciseNames.insert(exercise.name)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : Color(.systemGray3))
                    .font(.title3)
                Text(exercise.name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.leading, 8)
        }
    }
}

// MARK: - WorkoutRow

struct WorkoutRow: View {
    let workout: Workout

    var hasPR: Bool {
        workout.exerciseEntries.contains { $0.sets.contains(where: \.isPR) }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(workout.date, format: .dateTime
                        .weekday(.abbreviated)
                        .month(.abbreviated)
                        .day()
                        .year())
                        .font(.headline)
                    if hasPR {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                    if let badge = workout.sourceBadgeLabel {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.caption)
                    Text(workout.formattedDuration)
                    if workout.isHealthKitImported {
                        if let importedType = workout.importedWorkoutTypeLabel {
                            Text("·")
                            Text(importedType)
                        } else if !workout.exerciseEntries.isEmpty {
                            Text("·")
                            let count = workout.exerciseEntries.count
                            Text("\(count) \(count == 1 ? "exercise" : "exercises")")
                        }
                    } else {
                        Text("·")
                        let count = workout.exerciseEntries.count
                        Text("\(count) \(count == 1 ? "exercise" : "exercises")")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
