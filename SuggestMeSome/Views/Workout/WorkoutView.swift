//
//  WorkoutView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData
import Combine

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

    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]
    @AppStorage("healthkit.enabled") private var healthKitEnabled = false
    @AppStorage("healthkit.writeWorkouts") private var writeAppWorkoutsToHealthKit = false

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

    // PR celebration
    @State private var showPRCelebration = false
    @State private var newPRCount = 0
    @State private var celebrationScale: CGFloat = 0.5

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
        .overlay {
            if showPRCelebration {
                prCelebrationOverlay
            }
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
                    unit: AppPreferences.defaultWeightUnit,
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
            configureWorkoutSession()
        }
        .onChange(of: isActive) { persistActiveSessionIfNeeded() }
        .onChange(of: startTime) { persistActiveSessionIfNeeded() }
        .onChange(of: exerciseEntries) { persistActiveSessionIfNeeded() }
        .onChange(of: caloriesText) { persistActiveSessionIfNeeded() }
        .onChange(of: comments) { persistActiveSessionIfNeeded() }
        .onChange(of: activeWorkoutSessionStore.session) { syncWithActiveSessionIfNeeded($0) }
    }

    // MARK: - Sub-views

    private var dateHeader: some View {
        Text(startTime ?? Date.now, format: .dateTime.weekday(.wide).month(.wide).day().year())
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
                    startActiveSession(with: [], programContext: nil)
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

    private func configureWorkoutSession() {
        if let activeSession = activeWorkoutSessionStore.session {
            applyActiveSession(activeSession)
            broadcastActiveSessionToWatch()
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
        let now = Date.now
        let workoutID = programWorkout?.workoutID ?? UUID()
        let sourceLabels = watchSourceLabels()
        let sessionVersionStableID = watchSessionVersionStableID(workoutID: workoutID)
        startTime = now
        elapsedSeconds = 0
        exerciseEntries = entries
        caloriesText = ""
        comments = ""
        isActive = true
        activeWorkoutSessionStore.startSession(
            id: workoutID,
            startTime: now,
            exerciseEntries: entries,
            programContext: programContext,
            sessionPlanKind: programWorkout?.watchSessionPlanKind ?? (programContext == nil ? nil : .planned),
            sessionSourceLabels: sourceLabels,
            sessionVersionStableID: sessionVersionStableID
        )
        broadcastActiveSessionToWatch()
    }

    private func applyActiveSession(_ session: ActiveWorkoutSession) {
        startTime = session.startTime
        elapsedSeconds = max(0, Int(Date.now.timeIntervalSince(session.startTime)))
        exerciseEntries = session.exerciseEntries
        caloriesText = session.caloriesText
        comments = session.comments
        isActive = true
    }

    private func persistActiveSessionIfNeeded() {
        guard isActive, let startTime else { return }
        activeWorkoutSessionStore.updateSession(
            startTime: startTime,
            exerciseEntries: exerciseEntries,
            caloriesText: caloriesText,
            comments: comments,
            programContext: activeProgramContext(from: programWorkout) ?? activeWorkoutSessionStore.session?.programContext,
            sessionPlanKind: programWorkout?.watchSessionPlanKind,
            sessionSourceLabels: programWorkout?.watchSessionSourceLabels,
            sessionVersionStableID: programWorkout?.watchSessionVersionStableID
        )
        broadcastActiveSessionToWatch()
    }

    private func syncWithActiveSessionIfNeeded(_ session: ActiveWorkoutSession?) {
        guard let session else { return }
        guard isActive else {
            applyActiveSession(session)
            return
        }
        if startTime == session.startTime,
           exerciseEntries == session.exerciseEntries,
           caloriesText == session.caloriesText,
           comments == session.comments {
            return
        }
        applyActiveSession(session)
    }

    private func broadcastActiveSessionToWatch() {
        guard let session = activeWorkoutSessionStore.session else { return }
        Task { @MainActor in
            await WatchSessionCoordinator.shared.broadcastActiveSessionState(session)
        }
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
        let allPersonalRecords = TrainingContextQueryService.fetchPersonalRecords(context: modelContext)
        return ProgramWorkoutDraftBuilder.buildEntries(from: programWorkout.exercises) { anchor in
            TrainingContextQueryService.preferredUnit(
                for: anchor.exerciseName,
                in: allPersonalRecords
            )
        }
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
        let activeSessionForCompletion = activeWorkoutSessionStore.session
        let coordinator = WorkoutSaveCoordinator(modelContext: modelContext)
        let request = WorkoutSaveRequest(
            startTime: start,
            endTime: Date.now,
            caloriesText: caloriesText,
            comments: comments,
            exerciseEntries: exerciseEntries,
            programContext: workoutSaveProgramContext(),
            healthKitEnabled: healthKitEnabled,
            healthKitWritebackEnabled: writeAppWorkoutsToHealthKit
        )
        let savedWorkout = coordinator.saveWorkout(using: request)
        let prCount = savedWorkout.exerciseEntries.flatMap(\.sets).filter(\.isPR).count
        broadcastWatchCompletion(
            activeSession: activeSessionForCompletion,
            savedWorkout: savedWorkout,
            prCount: prCount
        )
        activeWorkoutSessionStore.discardSession()
        isActive = false

        if prCount > 0 {
            newPRCount = prCount
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                showPRCelebration = true
                celebrationScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismissCelebration()
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

    private func dismissCelebration() {
        withAnimation(.easeOut(duration: 0.3)) {
            celebrationScale = 0.5
            showPRCelebration = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            dismiss()
        }
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

// MARK: - ExerciseEntryCard

struct ExerciseEntryCard: View {
    @Binding var entry: DraftExerciseEntry
    let onDelete: () -> Void

    @State private var isExpanded: Bool = true
    @State private var showRPEField: Bool = false

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

                    // Effort capture — only show when there are actual working sets.
                    let hasWorkingSets = entry.sets.contains { !$0.isWarmup }
                    if hasWorkingSets {
                        Divider()
                        effortCaptureSection
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
