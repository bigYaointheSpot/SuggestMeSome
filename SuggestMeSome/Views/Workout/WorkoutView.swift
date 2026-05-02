//
//  WorkoutView.swift
//  SuggestMeSome
//
//  Live workout editor with draft persistence and isolated timer chrome.
//

import SwiftUI
import SwiftData

// MARK: - WorkoutView

struct WorkoutView: View {
    var generatedWorkout: GeneratedWorkout? = nil
    var programWorkout: ProgramWorkoutContext? = nil
    /// Pre-built draft supplied by Daily Coach prepared workout flow.
    /// When set, this overrides building the draft from `programWorkout.exercises`.
    var preparedDraft: [DraftExerciseEntry]? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ActiveWorkoutSessionStore.self) private var activeWorkoutSessionStore
    @Environment(PurchaseManager.self) private var purchaseManager

    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]
    @AppStorage("healthkit.enabled") private var healthKitEnabled = false
    @AppStorage("healthkit.writeWorkouts") private var writeAppWorkoutsToHealthKit = false

    // Timer
    @State private var isActive = false
    @State private var startTime: Date?
    @State private var lifecycleState: WatchWorkoutLifecycleState = .running

    // Workout data
    @State private var exerciseEntries: [DraftExerciseEntry] = []
    @State private var caloriesText: String = ""
    @State private var comments: String = ""

    // Sheets / alerts
    @State private var showingExercisePicker = false
    @State private var showingEndConfirmation = false

    // PR celebration
    @State private var showPRCelebration = false
    @State private var newPRCount = 0
    @State private var celebrationScale: CGFloat = 0.5

    // Block review — auto-presented when the final workout completes the program run
    @State private var showBlockReview = false
    @State private var pendingBlockReviewSnapshot: MesocycleReviewSnapshot?
    @State private var blockJustCompleted = false
    @State private var draftPersistenceTask: Task<Void, Never>?

    var body: some View {
        List {
            dateHeader
                .plainWorkoutRow()
            timerSection
                .plainWorkoutRow(horizontalInset: 0, verticalInset: DSSpacing.s)
            Divider()
                .plainWorkoutRow(horizontalInset: DSSpacing.l, verticalInset: 0)
            ForEach($exerciseEntries) { $entry in
                ExerciseEntryCard(entry: $entry) {
                    exerciseEntries.removeAll { $0.id == entry.id }
                    exerciseEntries = exerciseEntries.normalizedExerciseOrder()
                }
                .plainWorkoutRow(horizontalInset: DSSpacing.l, verticalInset: DSSpacing.xs)
                .moveDisabled(!canMoveExercise(entry))
            }
            .onMove(perform: handleExerciseMove)
            if isActive {
                addExerciseButton
                    .plainWorkoutRow()
            }
            caloriesField
                .plainWorkoutRow()
            notesField
                .plainWorkoutRow()
            if isActive {
                endWorkoutButton
                    .plainWorkoutRow(verticalInset: DSSpacing.m)
            }
        }
        .listStyle(.plain)
        .sensoryFeedback(.selection, trigger: exerciseEntries.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: exerciseEntries.map(\.id))
        .overlay {
            if showPRCelebration {
                prCelebrationOverlay
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Log Workout")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(muscleGroups: muscleGroups) { name, isCardio, setCount in
                let sets: [DraftSet] = isCardio ? [] : (1...max(1, setCount)).map { DraftSet(setNumber: $0) }
                let entry = DraftExerciseEntry(
                    exerciseName: name,
                    unit: AppPreferences.defaultWeightUnit,
                    orderIndex: exerciseEntries.count,
                    sets: sets,
                    isCardio: isCardio
                )
                exerciseEntries.append(entry)
                exerciseEntries = exerciseEntries.normalizedExerciseOrder()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBlockReview, onDismiss: {
            pendingBlockReviewSnapshot = nil
            dismiss()
        }) {
            NavigationStack {
                if let pendingBlockReviewSnapshot {
                    MesocycleReviewView(snapshot: pendingBlockReviewSnapshot)
                }
            }
        }
        .confirmationDialog("End Workout?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("Save & End Workout", role: .destructive) { saveWorkout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will save your workout and mark any new personal records.")
        }
        .onAppear {
            configureWorkoutSession()
        }
        .onDisappear {
            flushPendingDraftPersistence(broadcastWatchIfNeeded: true)
        }
        .onChange(of: exerciseEntries) { _, _ in
            scheduleDraftPersistence()
        }
        .onChange(of: caloriesText) { _, _ in
            scheduleDraftPersistence()
        }
        .onChange(of: comments) { _, _ in
            scheduleDraftPersistence()
        }
        .onChange(of: activeWorkoutSessionStore.session) { _, newSession in
            syncWithActiveSessionIfNeeded(newSession)
        }
    }

    // MARK: - Sub-views

    private var dateHeader: some View {
        Text(startTime ?? Date.now, format: .dateTime.weekday(.wide).month(.wide).day().year())
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var timerSection: some View {
        WorkoutSessionChromeSection(
            startTime: startTime,
            isActive: isActive,
            lifecycleState: lifecycleState,
            onTogglePauseResume: {
                if lifecycleState == .paused {
                    resumeWorkout()
                } else {
                    pauseWorkout()
                }
            },
            onStartWorkout: {
                startActiveSession(with: [], programContext: nil)
            }
        )
    }

    private var addExerciseButton: some View {
        Button {
            showingExercisePicker = true
        } label: {
            Label("Add Exercise", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DSColor.primaryAction.opacity(0.12))
                .foregroundStyle(DSColor.primaryAction)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
        }
    }

    private var caloriesField: some View {
        HStack {
            Label("Calories Burned", systemImage: "flame.fill")
                .foregroundStyle(DSColor.signalCaution)
            Spacer()
            TextField("Optional", text: $caloriesText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
        .padding(DSSpacing.l)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Label("Workout Notes", systemImage: "note.text")
                .font(.headline)
            TextEditor(text: $comments)
                .frame(minHeight: 120)
                .padding(6)
                .background(DSColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.s + 2))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.s + 2)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
        }
    }

    private var endWorkoutButton: some View {
        Button {
            showingEndConfirmation = true
        } label: {
            Label("End Workout", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DSColor.signalCritical)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.m))
        }
    }

    // MARK: - Reorder

    /// The currently-active exercise is the first exercise whose sets are
    /// not all logged. Matches `WatchSessionCoordinator.resolveCurrentExerciseIndex`
    /// so the iPhone UI and watch cursor agree on which card is locked.
    private var activeExerciseID: UUID? {
        exerciseEntries.first(where: { !WatchPayloadMapper.isExerciseComplete($0) })?.id
    }

    private func canMoveExercise(_ entry: DraftExerciseEntry) -> Bool {
        guard isActive else { return true }
        if WatchPayloadMapper.isExerciseComplete(entry) { return false }
        return entry.id != activeExerciseID
    }

    /// Lowest index a movable row may land on, so the user can't drop an
    /// upcoming exercise above the locked (completed + active) prefix.
    private var firstMovableIndex: Int {
        exerciseEntries.firstIndex(where: canMoveExercise) ?? exerciseEntries.count
    }

    private func handleExerciseMove(from source: IndexSet, to destination: Int) {
        let clamped = max(firstMovableIndex, destination)
        exerciseEntries.move(fromOffsets: source, toOffset: clamped)
        exerciseEntries = exerciseEntries.normalizedExerciseOrder()
    }

    // MARK: - Helpers

    private func formatGeneratedWeight(_ w: Double?) -> String {
        guard let w = w else { return "" }
        return w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
    }

    private func configureWorkoutSession() {
        if let activeSession = activeWorkoutSessionStore.session {
            applyActiveSession(activeSession)
            healPersistedExerciseOrderIfNeeded(for: activeSession)
            broadcastActiveSessionToWatch(includeLaunch: true)
            return
        }

        guard exerciseEntries.isEmpty else { return }

        if let draft = preparedDraft {
            startActiveSession(with: draft, programContext: activeProgramContext(from: programWorkout))
        } else if let generatedWorkout {
            startActiveSession(with: draftEntries(from: generatedWorkout), programContext: nil)
        } else if let programWorkout {
            startActiveSession(
                with: draftEntries(from: programWorkout),
                programContext: activeProgramContext(from: programWorkout)
            )
        }
    }

    private func startActiveSession(
        with entries: [DraftExerciseEntry],
        programContext: ActiveWorkoutProgramContext?
    ) {
        let normalizedEntries = entries.normalizedExerciseOrder()
        let now = Date.now
        let workoutID = programWorkout?.workoutID ?? UUID()
        let sourceLabels = watchSourceLabels()
        let sessionVersionStableID = watchSessionVersionStableID(workoutID: workoutID)
        let usesLinkedWatchHealthSession = WatchSessionCoordinator.shared.shouldUseLinkedWatchHealthSession(
            healthKitEnabled: healthKitEnabled && purchaseManager.isPremiumUnlocked
        )
        startTime = now
        lifecycleState = .running
        exerciseEntries = normalizedEntries
        caloriesText = ""
        comments = ""
        isActive = true
        activeWorkoutSessionStore.startSession(
            id: workoutID,
            startTime: now,
            exerciseEntries: normalizedEntries,
            programContext: programContext,
            sessionPlanKind: programWorkout?.watchSessionPlanKind ?? (programContext == nil ? nil : .planned),
            sessionSourceLabels: sourceLabels,
            sessionVersionStableID: sessionVersionStableID,
            usesLinkedWatchHealthSession: usesLinkedWatchHealthSession
        )
        broadcastActiveSessionToWatch(includeLaunch: true)
    }

    private func applyActiveSession(_ session: ActiveWorkoutSession) {
        startTime = session.startTime
        exerciseEntries = session.exerciseEntries.normalizedExerciseOrder()
        caloriesText = session.caloriesText
        comments = session.comments
        lifecycleState = session.lifecycleState
        isActive = true
    }

    private func healPersistedExerciseOrderIfNeeded(for session: ActiveWorkoutSession) {
        let normalizedEntries = session.exerciseEntries.normalizedExerciseOrder()
        guard normalizedEntries != session.exerciseEntries else { return }
        _ = activeWorkoutSessionStore.updateSession(
            startTime: session.startTime,
            exerciseEntries: normalizedEntries,
            caloriesText: session.caloriesText,
            comments: session.comments,
            programContext: session.programContext,
            sessionPlanKind: session.sessionPlanKind,
            sessionSourceLabels: session.sessionSourceLabels,
            sessionVersionStableID: session.sessionVersionStableID
        )
    }

    private func scheduleDraftPersistence() {
        guard isActive, startTime != nil else { return }
        draftPersistenceTask?.cancel()
        draftPersistenceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            persistActiveSessionIfNeeded()
            draftPersistenceTask = nil
        }
    }

    private func cancelPendingDraftPersistence() {
        draftPersistenceTask?.cancel()
        draftPersistenceTask = nil
    }

    private func flushPendingDraftPersistence(broadcastWatchIfNeeded: Bool) {
        cancelPendingDraftPersistence()
        persistActiveSessionIfNeeded(broadcastWatchIfNeeded: broadcastWatchIfNeeded)
    }

    private func persistActiveSessionIfNeeded(broadcastWatchIfNeeded: Bool = true) {
        guard isActive, let startTime else { return }
        let mutation = activeWorkoutSessionStore.updateSession(
            startTime: startTime,
            exerciseEntries: exerciseEntries,
            caloriesText: caloriesText,
            comments: comments,
            programContext: activeProgramContext(from: programWorkout) ?? activeWorkoutSessionStore.session?.programContext,
            sessionPlanKind: programWorkout?.watchSessionPlanKind,
            sessionSourceLabels: programWorkout?.watchSessionSourceLabels,
            sessionVersionStableID: programWorkout?.watchSessionVersionStableID
        )
        guard mutation.didChangeSession else { return }
        if broadcastWatchIfNeeded && mutation.shouldBroadcastWatch {
            broadcastActiveSessionToWatch()
        }
    }

    private func syncWithActiveSessionIfNeeded(_ session: ActiveWorkoutSession?) {
        guard let session else { return }
        cancelPendingDraftPersistence()
        guard isActive else {
            applyActiveSession(session)
            return
        }
        if startTime == session.startTime,
           exerciseEntries == session.exerciseEntries,
           caloriesText == session.caloriesText,
           comments == session.comments,
           lifecycleState == session.lifecycleState {
            return
        }
        applyActiveSession(session)
    }

    private func broadcastActiveSessionToWatch(includeLaunch: Bool = false) {
        guard let session = activeWorkoutSessionStore.session else { return }
        Task { @MainActor in
            await WatchSessionCoordinator.shared.broadcastActiveSessionState(
                session,
                includeLaunch: includeLaunch
            )
        }
    }

    private func pauseWorkout() {
        guard isActive else { return }
        flushPendingDraftPersistence(broadcastWatchIfNeeded: false)
        let now = Date.now
        activeWorkoutSessionStore.pauseSession(at: now)
        lifecycleState = .paused
        broadcastActiveSessionToWatch()
    }

    private func resumeWorkout() {
        guard isActive else { return }
        flushPendingDraftPersistence(broadcastWatchIfNeeded: false)
        let now = Date.now
        activeWorkoutSessionStore.resumeSession(at: now)
        lifecycleState = .running
        broadcastActiveSessionToWatch()
    }

    private func activeProgramContext(from programWorkout: ProgramWorkoutContext?) -> ActiveWorkoutProgramContext? {
        guard let programWorkout else { return nil }
        return ActiveWorkoutProgramContext(
            programRunID: programWorkout.programRun.id,
            programRunStableID: programWorkout.programRun.syncStableID,
            weekNumber: programWorkout.weekNumber,
            sessionNumber: programWorkout.sessionNumber
        )
    }

    private func watchSourceLabels() -> [String] {
        if let labels = WatchPayloadMapper.normalizeSourceLabels(programWorkout?.watchSessionSourceLabels) {
            return labels
        }
        if programWorkout != nil {
            return ["Program"]
        }
        if generatedWorkout != nil {
            return ["SuggestMeSome Generated"]
        }
        return ["Manual Workout"]
    }

    private func watchSessionVersionStableID(workoutID: UUID) -> String {
        if let versionID = programWorkout?.watchSessionVersionStableID {
            return versionID
        }
        if let programWorkout {
            return TodayPlanActionCoordinator.watchSessionVersionStableID(
                runStableID: programWorkout.programRun.syncStableID,
                path: .planned,
                weekNumber: programWorkout.weekNumber,
                sessionNumber: programWorkout.sessionNumber
            )
        }
        if generatedWorkout != nil {
            return "generated::\(workoutID.uuidString)"
        }
        return "manual::\(workoutID.uuidString)"
    }

    private func workoutSaveProgramContext() -> WorkoutSaveProgramContext? {
        if let programWorkout {
            return WorkoutSaveProgramContext(
                run: programWorkout.programRun,
                weekNumber: programWorkout.weekNumber,
                sessionNumber: programWorkout.sessionNumber
            )
        }

        guard let activeProgramContext = activeWorkoutSessionStore.session?.programContext,
              let run = fetchProgramRun(id: activeProgramContext.programRunID) else {
            return nil
        }

        return WorkoutSaveProgramContext(
            run: run,
            weekNumber: activeProgramContext.weekNumber,
            sessionNumber: activeProgramContext.sessionNumber
        )
    }

    private func fetchProgramRun(id: UUID) -> ProgramRun? {
        var descriptor = FetchDescriptor<ProgramRun>(
            predicate: #Predicate<ProgramRun> { run in
                run.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func draftEntries(from generatedWorkout: GeneratedWorkout) -> [DraftExerciseEntry] {
        generatedWorkout.exercises.enumerated().map { index, genExercise in
            if genExercise.exercise.exerciseType == .cardio {
                let totalSeconds = Int(genExercise.effectiveTimeMinutes * 60)
                let mins = totalSeconds / 60
                let secs = totalSeconds % 60
                return DraftExerciseEntry(
                    exerciseName: genExercise.exercise.name,
                    unit: AppPreferences.defaultWeightUnit,
                    orderIndex: index,
                    sets: [],
                    isCardio: true,
                    cardioMinutesText: mins > 0 ? "\(mins)" : "",
                    cardioSecondsText: secs > 0 ? "\(secs)" : ""
                )
            }

            let unit = genExercise.sets.first?.unit ?? AppPreferences.defaultWeightUnit
            let draftSets = genExercise.sets.map { genSet in
                DraftSet(
                    setNumber: genSet.setNumber,
                    repsText: "\(genSet.suggestedReps)",
                    weightText: formatGeneratedWeight(genSet.suggestedWeight),
                    isWarmup: genSet.isWarmup,
                    isPrefilledFromPrescription: true
                )
            }
            return DraftExerciseEntry(
                exerciseName: genExercise.exercise.name,
                unit: unit,
                orderIndex: index,
                sets: draftSets
            )
        }
    }

    private func draftEntries(from programWorkout: ProgramWorkoutContext) -> [DraftExerciseEntry] {
        return ProgramWorkoutDraftBuilder.buildEntries(from: programWorkout.exercises) { anchor in
            TrainingReadRepository.preferredUnit(
                for: anchor.exerciseName,
                context: modelContext
            )
        }
    }

    // MARK: - Save

    private func saveWorkout() {
        guard isActive, let start = startTime else { return }
        flushPendingDraftPersistence(broadcastWatchIfNeeded: false)
        let endTime = Date.now
        let saveProgramContext = workoutSaveProgramContext()
        let runForSave = saveProgramContext?.run
        let wasAlreadyComplete = runForSave?.isCompleted ?? false
        let activeSessionForCompletion = activeWorkoutSessionStore.session
        let coordinator = WorkoutSaveCoordinator(modelContext: modelContext)
        let resolvedDurationSeconds = activeWorkoutSessionStore.resolvedElapsedSeconds(at: endTime)
        let resolvedCaloriesText = resolvedCaloriesTextForSave()
        let skipHealthKitWriteback = activeSessionForCompletion?.usesLinkedWatchHealthSession == true
        let request = WorkoutSaveRequest(
            workoutID: activeSessionForCompletion?.id,
            startTime: start,
            endTime: endTime,
            durationSeconds: resolvedDurationSeconds,
            caloriesText: resolvedCaloriesText,
            comments: comments,
            exerciseEntries: exerciseEntries,
            programContext: saveProgramContext,
            healthKitEnabled: healthKitEnabled && purchaseManager.isPremiumUnlocked,
            healthKitWritebackEnabled: writeAppWorkoutsToHealthKit && purchaseManager.isPremiumUnlocked,
            skipHealthKitWriteback: skipHealthKitWriteback
        )
        let savedWorkout = coordinator.saveWorkout(using: request)
        let prCount = savedWorkout.exerciseEntries
            .flatMap { $0.sets }
            .filter { $0.isPR }
            .count
        let didCompleteBlock = !wasAlreadyComplete && (runForSave?.isCompleted ?? false)
        blockJustCompleted = didCompleteBlock
        pendingBlockReviewSnapshot = didCompleteBlock ? mesocycleReviewSnapshot(for: runForSave) : nil
        broadcastWatchCompletion(
            activeSession: activeSessionForCompletion,
            savedWorkout: savedWorkout,
            prCount: prCount
        )
        activeWorkoutSessionStore.discardSession()
        isActive = false
        lifecycleState = .running

        if prCount > 0 {
            newPRCount = prCount
            withAnimation(.dsExpressive) {
                showPRCelebration = true
                celebrationScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismissCelebration()
            }
        } else if didCompleteBlock {
            showBlockReview = pendingBlockReviewSnapshot != nil
            if pendingBlockReviewSnapshot == nil {
                dismiss()
            }
        } else {
            dismiss()
        }
    }

    private func broadcastWatchCompletion(
        activeSession: ActiveWorkoutSession?,
        savedWorkout: Workout,
        prCount: Int
    ) {
        let workoutID = activeSession?.id ?? savedWorkout.id
        let label = watchCompletionLabel(activeSession: activeSession)
        Task { @MainActor in
            await WatchSessionCoordinator.shared.broadcastSessionCompletion(
                workoutID: workoutID,
                completedAt: savedWorkout.date,
                totalElapsedSeconds: savedWorkout.durationSeconds,
                entries: exerciseEntries,
                sessionLabel: label,
                sessionPlanKind: activeSession?.sessionPlanKind,
                sessionSourceLabels: activeSession?.sessionSourceLabels,
                sessionVersionStableID: activeSession?.sessionVersionStableID,
                newPersonalRecordCount: prCount
            )
        }
    }

    private func watchCompletionLabel(activeSession: ActiveWorkoutSession?) -> String {
        if let programContext = activeSession?.programContext {
            return "W\(programContext.weekNumber) · S\(programContext.sessionNumber)"
        }
        if generatedWorkout != nil {
            return "Suggested workout"
        }
        return "Workout"
    }

    private func resolvedCaloriesTextForSave() -> String {
        let trimmed = caloriesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let activeEnergy = activeWorkoutSessionStore.latestWatchMetrics?.activeEnergyKilocalories {
            return "\(Int(activeEnergy.rounded()))"
        }
        if let activeEnergy = activeWorkoutSessionStore.latestWatchHealthSummary?.totalActiveEnergyKilocalories {
            return "\(Int(activeEnergy.rounded()))"
        }
        return caloriesText
    }

    private func dismissCelebration() {
        withAnimation(.easeOut(duration: 0.3)) {
            celebrationScale = 0.5
            showPRCelebration = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if blockJustCompleted, pendingBlockReviewSnapshot != nil {
                showBlockReview = true
            } else {
                dismiss()
            }
        }
    }

    private func mesocycleReviewSnapshot(for run: ProgramRun?) -> MesocycleReviewSnapshot? {
        guard let run else { return nil }
        return TrainingReadRepository.mesocycleReviewSnapshot(
            for: run,
            context: modelContext
        )
    }

    // MARK: - PR Celebration Overlay

    private var prCelebrationOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { dismissCelebration() }

            VStack(spacing: 20) {
                Image(systemName: "star.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(DSGradient.prCelebration)
                    .shadow(color: DSColor.signalCaution.opacity(0.55), radius: 24)

                VStack(spacing: 8) {
                    Text(newPRCount == 1 ? "New Personal Record!" : "\(newPRCount) Personal Records!")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Tap to continue")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .scaleEffect(celebrationScale)
        }
    }
}

