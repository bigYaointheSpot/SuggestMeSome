//
//  ContentView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - Main Tab Identity

/// Single source of truth for the root tab bar. Keeping identity, labels, and
/// icons here lets tests validate tab copy without instantiating SwiftUI views
/// and keeps `ContentView` free of magic numbers.
enum MainTab: Int, CaseIterable {
    case dailyCoach = 0
    case dashboard  = 1
    case workouts   = 2
    case programs   = 3
    case settings   = 4

    var label: String {
        switch self {
        case .dailyCoach: return "Daily Coach"
        case .dashboard:  return "Dashboard"
        case .workouts:   return "Workouts"
        case .programs:   return "Training Programs"
        case .settings:   return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dailyCoach: return "brain.head.profile"
        case .dashboard:  return "square.grid.2x2.fill"
        case .workouts:   return "dumbbell"
        case .programs:   return "list.clipboard"
        case .settings:   return "gear"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
    @State private var selectedTab: Int = MainTab.dailyCoach.rawValue
    @State private var showingActiveWorkout = false
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"

    private var preferredColorScheme: ColorScheme? {
        AppAppearancePreferenceService.preferredColorScheme(for: appColorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            if activeWorkoutSessionStore.hasActiveSession {
                ActiveWorkoutBanner {
                    showingActiveWorkout = true
                }
            }

            TabView(selection: $selectedTab) {
                DailyCoachView()
                    .tabItem {
                        Label(MainTab.dailyCoach.label, systemImage: MainTab.dailyCoach.systemImage)
                    }
                    .tag(MainTab.dailyCoach.rawValue)
                DashboardView(selectedTab: $selectedTab)
                    .tabItem {
                        Label(MainTab.dashboard.label, systemImage: MainTab.dashboard.systemImage)
                    }
                    .tag(MainTab.dashboard.rawValue)
                WorkoutsTab()
                    .tabItem {
                        Label(MainTab.workouts.label, systemImage: MainTab.workouts.systemImage)
                    }
                    .tag(MainTab.workouts.rawValue)
                TrainingProgramsTab()
                    .tabItem {
                        Label(MainTab.programs.label, systemImage: MainTab.programs.systemImage)
                    }
                    .tag(MainTab.programs.rawValue)
                SettingsTab()
                    .tabItem {
                        Label(MainTab.settings.label, systemImage: MainTab.settings.systemImage)
                    }
                    .tag(MainTab.settings.rawValue)
            }
        }
        .tint(.indigo)
        .preferredColorScheme(preferredColorScheme)
        .sheet(isPresented: $showingActiveWorkout) {
            NavigationStack {
                WorkoutView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingActiveWorkout = false
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - Active Workout Banner

struct ActiveWorkoutBanner: View {
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
    @State private var elapsedSeconds = 0

    let onResume: () -> Void

    var body: some View {
        if let session = activeWorkoutSessionStore.session {
            Button(action: onResume) {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout in Progress")
                            .font(.subheadline.weight(.semibold))
                        Text("\(formattedElapsed) · \(exerciseCountLabel(session.exerciseEntries.count))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Text("Resume")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(Color.indigo)
            }
            .buttonStyle(.plain)
            .onAppear {
                elapsedSeconds = Int(Date.now.timeIntervalSince(session.startTime))
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                elapsedSeconds = Int(Date.now.timeIntervalSince(session.startTime))
            }
        }
    }

    private var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func exerciseCountLabel(_ count: Int) -> String {
        count == 1 ? "1 exercise" : "\(count) exercises"
    }
}

// MARK: - WorkoutsTab

struct WorkoutsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
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
    @State private var showingEmptyWorkout = false
    @State private var showingGeneratorSheet   = false
    @State private var pendingGeneratedWorkout: GeneratedWorkout?
    @State private var showingGeneratedWorkout = false

    // MARK: Program workout flow
    @State private var showingCompleteProgramSheet = false
    @State private var pendingProgramWorkout: ProgramWorkoutContext?
    @State private var showingProgramWorkout = false
    @State private var pendingWorkoutStart: PendingWorkoutStart?

    private enum PendingWorkoutStart {
        case empty
        case generatedWorkout
        case programWorkout
    }

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
            .navigationDestination(isPresented: $showingEmptyWorkout) {
                WorkoutView()
            }
            .sheet(isPresented: $showingExerciseFilter) {
                ExerciseFilterSheet(
                    muscleGroups: muscleGroups,
                    selectedGroupNames: $selectedGroupNames,
                    selectedExerciseNames: $selectedExerciseNames
                )
            }
            .sheet(isPresented: $showingGeneratorSheet, onDismiss: {
                DeferredNavigationService.launchAfterSheetDismissIfNeeded(
                    hasPendingDestination: pendingGeneratedWorkout != nil
                ) {
                    if activeWorkoutSessionStore.hasActiveSession {
                        pendingWorkoutStart = .generatedWorkout
                    } else {
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
                DeferredNavigationService.launchAfterSheetDismissIfNeeded(
                    hasPendingDestination: pendingProgramWorkout != nil
                ) {
                    if activeWorkoutSessionStore.hasActiveSession {
                        pendingWorkoutStart = .programWorkout
                    } else {
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
            .confirmationDialog(
                "Discard Active Workout?",
                isPresented: .init(
                    get: { pendingWorkoutStart != nil },
                    set: {
                        if !$0 {
                            discardPendingReplacement(start: pendingWorkoutStart)
                            pendingWorkoutStart = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Discard Active Workout", role: .destructive) {
                    let start = pendingWorkoutStart
                    pendingWorkoutStart = nil
                    activeWorkoutSessionStore.discardSession()
                    if let start {
                        performWorkoutStart(start)
                    }
                }
                Button("Cancel", role: .cancel) {
                    discardPendingReplacement(start: pendingWorkoutStart)
                    pendingWorkoutStart = nil
                }
            } message: {
                Text("Starting a new workout will delete the in-progress draft.")
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
            Button {
                requestWorkoutStart(.empty)
            } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                pendingGeneratedWorkout = nil
                showingGeneratorSheet = true
            } label: {
                Label("SuggestMeSome", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !activeProgramRuns.isEmpty {
                Button {
                    pendingProgramWorkout = nil
                    showingCompleteProgramSheet = true
                } label: {
                    Label("Complete Program", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func requestWorkoutStart(_ start: PendingWorkoutStart) {
        if activeWorkoutSessionStore.hasActiveSession {
            pendingWorkoutStart = start
        } else {
            performWorkoutStart(start)
        }
    }

    private func performWorkoutStart(_ start: PendingWorkoutStart) {
        switch start {
        case .empty:
            showingEmptyWorkout = true
        case .generatedWorkout:
            showingGeneratedWorkout = true
        case .programWorkout:
            showingProgramWorkout = true
        }
    }

    private func discardPendingReplacement(start: PendingWorkoutStart?) {
        switch start {
        case .generatedWorkout:
            pendingGeneratedWorkout = nil
        case .programWorkout:
            pendingProgramWorkout = nil
        case .empty, nil:
            break
        }
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
                    .background(exerciseFilterActive ? Color.indigo.opacity(0.25) : Color(.secondarySystemBackground))
                    .foregroundStyle(exerciseFilterActive ? Color.indigo : Color.primary)
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
        tint: Color = .indigo,
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
                        .foregroundStyle(groupSelected ? .indigo : Color(.systemGray3))
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
                    .foregroundStyle(isSelected ? .indigo : Color(.systemGray3))
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
