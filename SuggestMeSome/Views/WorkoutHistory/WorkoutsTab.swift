import SwiftData
import SwiftUI

struct WorkoutsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]
    @Query(filter: #Predicate<ProgramRun> { run in run.isCompleted == false })
    private var activeProgramRuns: [ProgramRun]

    @State private var filterByDate = false
    @State private var filterStartDate = Calendar.current.startOfDay(for: Date())
    @State private var filterEndDate = Date()
    @State private var selectedGroupNames: Set<String> = []
    @State private var selectedExerciseNames: Set<String> = []
    @State private var filterPROnly = false
    @State private var showingExerciseFilter = false
    @State private var derivedState = WorkoutHistoryDerivedState.placeholder

    @State private var workoutToDelete: Workout?

    /// Ties each WorkoutRow to its pushed WorkoutDetailView for the iOS 18
    /// zoom transition. See `.navigationTransition(.zoom(sourceID:in:))`
    /// and `.matchedTransitionSource(id:in:)` below.
    @Namespace private var workoutTransitionNamespace

    @State private var showingEmptyWorkout = false
    @State private var showingGeneratorSheet = false
    @State private var pendingGeneratedWorkout: GeneratedWorkout?
    @State private var showingGeneratedWorkout = false

    @State private var showingCompleteProgramSheet = false
    @State private var pendingProgramWorkout: ProgramWorkoutContext?
    @State private var showingProgramWorkout = false
    @State private var pendingWorkoutStart: PendingWorkoutStart?
    @State private var paywallFeature: PremiumFeature?

    private enum PendingWorkoutStart {
        case empty
        case generatedWorkout
        case programWorkout
    }

    private var filterInputs: WorkoutHistoryFilterInputs {
        WorkoutHistoryFilterInputs(
            isDateFilterEnabled: filterByDate,
            startDate: filterStartDate,
            endDate: filterEndDate,
            selectedGroupNames: selectedGroupNames,
            selectedExerciseNames: selectedExerciseNames,
            isPersonalRecordOnly: filterPROnly
        )
    }

    private var derivedStateRefreshToken: Int {
        WorkoutHistoryDerivedState.refreshToken(
            workouts: workouts,
            muscleGroups: muscleGroups,
            filters: filterInputs
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                actionButtonRow
                filterBar
                Divider()
                workoutList
            }
            .navigationTitle("Workouts")
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
            .sheet(item: $paywallFeature) { feature in
                NavigationStack {
                    PaywallView(feature: feature)
                }
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
                GeneratorSheetRootView { generatedWorkout in
                    pendingGeneratedWorkout = generatedWorkout
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
                CompleteProgramWorkoutSheet(activeRuns: Array(activeProgramRuns)) { context in
                    pendingProgramWorkout = context
                    showingCompleteProgramSheet = false
                }
            }
            .navigationDestination(isPresented: $showingProgramWorkout) {
                if let pendingProgramWorkout {
                    WorkoutView(programWorkout: pendingProgramWorkout)
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
            .alert(
                "Delete Workout?",
                isPresented: .init(
                    get: { workoutToDelete != nil },
                    set: { if !$0 { workoutToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let workoutToDelete {
                        try? PersonalRecordMaintenanceService.deleteWorkout(
                            workoutToDelete,
                            context: modelContext
                        )
                    }
                    workoutToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    workoutToDelete = nil
                }
            } message: {
                Text("This workout and all its data will be permanently deleted. Personal records will be rebuilt from your remaining workouts.")
            }
            .task(id: derivedStateRefreshToken) {
                refreshDerivedState()
            }
        }
    }

    private var actionButtonRow: some View {
        VStack(spacing: 8) {
            Button {
                requestWorkoutStart(.empty)
            } label: {
                Label("New Workout", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                Button {
                    guard FeatureAccessPolicy.isAccessible(
                        .smartWorkoutGeneration,
                        entitlementState: purchaseManager.entitlementState
                    ) else {
                        paywallFeature = .smartWorkoutGeneration
                        return
                    }
                    pendingGeneratedWorkout = nil
                    showingGeneratorSheet = true
                } label: {
                    Label("Smart Session", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !activeProgramRuns.isEmpty {
                    Button {
                        guard FeatureAccessPolicy.isAccessible(
                            .trainingPrograms,
                            entitlementState: purchaseManager.entitlementState
                        ) else {
                            paywallFeature = .trainingPrograms
                            return
                        }
                        pendingProgramWorkout = nil
                        showingCompleteProgramSheet = true
                    } label: {
                        Label("Program Session", systemImage: "list.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
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
                filterChip(
                    label: filterByDate ? "Date On" : "Date Range",
                    systemImage: "calendar",
                    isActive: filterByDate
                ) {
                    filterByDate.toggle()
                }

                if filterByDate {
                    DatePicker("", selection: $filterStartDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    Text("–")
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $filterEndDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                Button {
                    showingExerciseFilter = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                        Text(derivedState.activeFilterSummary.exerciseFilterLabel)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        derivedState.activeFilterSummary.exerciseFilterActive
                            ? Color.indigo.opacity(0.25)
                            : Color(.secondarySystemBackground)
                    )
                    .foregroundStyle(
                        derivedState.activeFilterSummary.exerciseFilterActive
                            ? Color.indigo
                            : Color.primary
                    )
                    .clipShape(Capsule())
                }

                filterChip(
                    label: "PRs Only",
                    systemImage: derivedState.prOnlyState.isEnabled ? "star.fill" : "star",
                    isActive: derivedState.prOnlyState.isEnabled,
                    tint: .yellow
                ) {
                    filterPROnly.toggle()
                }

                if derivedState.activeFilterSummary.isFiltered {
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

    @ViewBuilder
    private var workoutList: some View {
        if derivedState.filteredWorkouts.isEmpty {
            DSEmptyState(
                systemImage: "dumbbell.fill",
                title: derivedState.activeFilterSummary.isFiltered ? "No Matching Workouts" : "No Workouts Yet",
                message: derivedState.activeFilterSummary.isFiltered
                    ? "Try adjusting your filters."
                    : "Tap New Workout above to begin."
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(derivedState.filteredWorkouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                            .navigationTransition(.zoom(sourceID: workout.id, in: workoutTransitionNamespace))
                    } label: {
                        WorkoutRow(workout: workout)
                    }
                    .matchedTransitionSource(id: workout.id, in: workoutTransitionNamespace)
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

    private func refreshDerivedState() {
        derivedState = WorkoutHistoryDerivedState.build(
            workouts: workouts,
            muscleGroups: muscleGroups,
            filters: filterInputs
        )
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
}
