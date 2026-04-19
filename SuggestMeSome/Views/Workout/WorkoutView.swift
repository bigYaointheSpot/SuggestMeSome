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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
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
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.7), radius: 24)

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

private struct WorkoutSessionChromeSection: View {
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

private struct WorkoutSessionStatusRow: View {
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

private struct WorkoutElapsedTimerText: View {
    let presentation: WorkoutElapsedTimerPresentation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(presentation.formattedElapsed(at: context.date))
                .font(.system(size: 56, weight: .thin, design: .monospaced))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: presentation.formattedElapsed(at: context.date))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - ExerciseEntryCard

struct ExerciseEntryCard: View {
    @Binding var entry: DraftExerciseEntry
    let onDelete: () -> Void

    @State private var isExpanded: Bool = true
    @State private var showRPEField: Bool = false

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
                        .foregroundStyle(DSColor.signalCritical)
                }
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
                        SetEntryRow(set: $set)
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
                    .animation(.easeOut(duration: 0.25), value: progressFraction)
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

private struct RPEStepperField: View {
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

            Text(rpe.map { String(format: $0.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", $0) } ?? "—")
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, alignment: .center)

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

    @State private var starScale: CGFloat = 1.0
    @State private var starGlowRadius: CGFloat = 0

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
                .scaleEffect(starScale)
                .shadow(color: Color.yellow.opacity(starGlowRadius > 0 ? 0.8 : 0), radius: starGlowRadius)
                .onChange(of: set.isPR) { _, newValue in
                    guard newValue else { return }
                    withAnimation(.easeOut(duration: 0.5)) {
                        starScale = 1.6
                        starGlowRadius = 12
                    }
                    withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
                        starScale = 1.0
                        starGlowRadius = 0
                    }
                }
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

// MARK: - List row helpers

private extension View {
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
