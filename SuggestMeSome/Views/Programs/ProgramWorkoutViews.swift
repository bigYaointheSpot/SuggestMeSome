//
//  ProgramWorkoutViews.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import SwiftUI
import SwiftData

// MARK: - ProgramWorkoutContext

struct ProgramWorkoutContext {
    var workoutID: UUID = UUID()
    var programRun: ProgramRun
    var weekNumber: Int
    var sessionNumber: Int
    var exercises: [ProgramSessionExercise]
    var watchSessionPlanKind: WatchSessionPlanKind? = nil
    var watchSessionSourceLabels: [String]? = nil
    var watchSessionVersionStableID: String? = nil
}

// MARK: - SelectProgramView

struct SelectProgramView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TrainingProgram.createdDate, order: .reverse) private var programs: [TrainingProgram]

    @State private var selectedProgram: TrainingProgram? = nil
    @State private var showingConfirmation = false

    var body: some View {
        Group {
            if programs.isEmpty {
                ContentUnavailableView(
                    "No Programs",
                    systemImage: "list.clipboard",
                    description: Text("Create a program first using the 'Create Your Own Program' button.")
                )
            } else {
                List {
                    ForEach(programs) { program in
                        Button {
                            selectedProgram = program
                            showingConfirmation = true
                        } label: {
                            ProgramListRow(program: program)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Use Existing Program")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog(
            selectedProgram.map { "Start \($0.name)?" } ?? "Start Program?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Start Program") {
                if let program = selectedProgram { startProgram(program) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let program = selectedProgram {
                Text("This will begin a \(program.lengthInWeeks)-week program with \(program.sessionsPerWeek) sessions per week.")
            }
        }
    }

    private func startProgram(_ program: TrainingProgram) {
        let run = ProgramRun(startDate: Date.now)
        run.program = program
        modelContext.insert(run)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - ProgramListRow

struct ProgramListRow: View {
    let program: TrainingProgram

    var sourceLabel: String {
        switch program.source {
        case .userCreated: return "Custom"
        case .template: return "Template"
        case .aiGenerated: return "Smart Generated"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(program.name).font(.headline)
            Text("\(program.lengthInWeeks) weeks · \(program.sessionsPerWeek) sessions/week · \(sourceLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ProgramRunDetailView

struct ProgramRunDetailView: View {
    @Bindable var run: ProgramRun

    var body: some View {
        ProgramRunDetailScreen(run: run)
    }
}

// MARK: - CompleteProgramWorkoutSheet

struct CompleteProgramWorkoutSheet: View {
    let activeRuns: [ProgramRun]
    let onStart: (ProgramWorkoutContext) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedRun: ProgramRun? = nil

    /// Returns the run to display a session preview for, without waiting for onAppear.
    var effectiveRun: ProgramRun? {
        selectedRun ?? (activeRuns.count == 1 ? activeRuns[0] : nil)
    }

    var body: some View {
        NavigationStack {
            if let run = effectiveRun {
                ProgramRunSessionPreviewView(
                    run: run,
                    onStart: onStart
                )
                    .navigationTitle("Next Session")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            if activeRuns.count > 1 {
                                Button("Back") { selectedRun = nil }
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
            } else {
                runSelectionList
                    .navigationTitle("Select Program")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
            }
        }
    }

    // MARK: Run selection list

    private var runSelectionList: some View {
        List {
            ForEach(activeRuns) { run in
                Button {
                    selectedRun = run
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(run.program?.name ?? "Unknown Program")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Started \(run.startDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }
}

private struct ProgramRunDetailScreen: View {
    let run: ProgramRun

    @Environment(\.modelContext) private var modelContext
    @Query private var observedRunWorkouts: [Workout]
    @State private var progressSnapshot: ProgramRunProgressReadSnapshot?
    @State private var showingEndConfirmation = false

    init(run: ProgramRun) {
        self.run = run
        let runID = run.id
        _observedRunWorkouts = Query(
            filter: #Predicate<Workout> { $0.programRun?.id == runID },
            sort: [SortDescriptor(\Workout.date, order: .forward)]
        )
    }

    private var refreshToken: Int {
        ProgramRunProgressReadSnapshot.refreshToken(
            for: run,
            observedWorkouts: observedRunWorkouts
        )
    }

    private var completedCount: Int {
        progressSnapshot?.completedWorkoutCount ?? 0
    }

    private var totalSessions: Int {
        progressSnapshot?.totalSessions ?? max(0, (run.program?.lengthInWeeks ?? 0) * (run.program?.sessionsPerWeek ?? 0))
    }

    var body: some View {
        List {
            Section("Program") {
                if let program = run.program {
                    LabeledContent("Name", value: program.name)
                    LabeledContent("Length", value: "\(program.lengthInWeeks) weeks")
                    LabeledContent("Sessions / Week", value: "\(program.sessionsPerWeek)")
                }
            }

            Section("Progress") {
                LabeledContent("Status", value: run.isCompleted ? "Completed" : "Active")
                LabeledContent("Started", value: run.startDate.formatted(date: .abbreviated, time: .omitted))
                if let endDate = run.endDate {
                    LabeledContent("Ended", value: endDate.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("Workouts", value: "\(completedCount) / \(totalSessions)")
            }

            if !run.isCompleted {
                Section {
                    Button("End Program Early") {
                        showingEndConfirmation = true
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(run.program?.name ?? "Program")
        .navigationBarTitleDisplayMode(.large)
        .task(id: refreshToken) {
            progressSnapshot = TrainingReadRepository.programRunProgressSnapshot(
                for: run,
                context: modelContext
            )
        }
        .confirmationDialog("End Program?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End Program", role: .destructive) {
                run.isCompleted = true
                run.endDate = Date.now
                try? modelContext.save()
                progressSnapshot = TrainingReadRepository.programRunProgressSnapshot(
                    for: run,
                    context: modelContext
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark the program as completed.")
        }
    }
}

private struct ProgramRunSessionPreviewView: View {
    let run: ProgramRun
    let onStart: (ProgramWorkoutContext) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var observedRunWorkouts: [Workout]

    @State private var progressSnapshot: ProgramRunProgressReadSnapshot?
    @State private var weekNumber = 1
    @State private var sessionNumber = 1
    @State private var showingSessionPicker = false
    @State private var hasInitializedSelection = false

    init(
        run: ProgramRun,
        onStart: @escaping (ProgramWorkoutContext) -> Void
    ) {
        self.run = run
        self.onStart = onStart
        let runID = run.id
        _observedRunWorkouts = Query(
            filter: #Predicate<Workout> { $0.programRun?.id == runID },
            sort: [SortDescriptor(\Workout.date, order: .forward)]
        )
    }

    private var refreshToken: Int {
        ProgramRunProgressReadSnapshot.refreshToken(
            for: run,
            observedWorkouts: observedRunWorkouts
        )
    }

    private var exercises: [ProgramSessionExercise] {
        ProgramOverlayResolutionService.resolvedExercises(
            for: run,
            week: weekNumber,
            session: sessionNumber,
            context: modelContext
        )
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(run.program?.name ?? "Program")
                        .font(.headline)
                    Spacer()
                    Text("Week \(weekNumber), Session \(sessionNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Exercises") {
                if exercises.isEmpty {
                    Text("No exercises for this session.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(exercises) { exercise in
                        HStack {
                            Text(exercise.exerciseName)
                            Spacer()
                            if let sets = exercise.targetSets, let reps = exercise.targetReps {
                                Text("\(sets)×\(reps)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else if let sets = exercise.targetSets {
                                Text("\(sets) sets")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Choose Different Session") {
                    showingSessionPicker = true
                }
                .foregroundStyle(.blue)
            }
        }
        .listStyle(.insetGrouped)
        .task(id: refreshToken) {
            refreshProgressSnapshot()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let ctx = ProgramWorkoutContext(
                    programRun: run,
                    weekNumber: weekNumber,
                    sessionNumber: sessionNumber,
                    exercises: exercises
                )
                onStart(ctx)
                dismiss()
            } label: {
                Text("Start Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingSessionPicker) {
            if let program = run.program {
                SessionPickerSheet(
                    lengthInWeeks: program.lengthInWeeks,
                    sessionsPerWeek: program.sessionsPerWeek,
                    weekNumber: $weekNumber,
                    sessionNumber: $sessionNumber
                )
            }
        }
    }

    private func refreshProgressSnapshot() {
        let snapshot = TrainingReadRepository.programRunProgressSnapshot(
            for: run,
            context: modelContext
        )
        progressSnapshot = snapshot

        guard !hasInitializedSelection else { return }
        applyInitialSelection(using: snapshot)
        hasInitializedSelection = true
    }

    private func applyInitialSelection(using snapshot: ProgramRunProgressReadSnapshot) {
        if let nextIncompleteSession = snapshot.nextIncompleteSession {
            weekNumber = nextIncompleteSession.weekNumber
            sessionNumber = nextIncompleteSession.sessionNumber
            return
        }

        weekNumber = 1
        sessionNumber = 1
    }
}

// MARK: - SessionPickerSheet

private struct SessionPickerSheet: View {
    let lengthInWeeks: Int
    let sessionsPerWeek: Int
    @Binding var weekNumber: Int
    @Binding var sessionNumber: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Week", selection: $weekNumber) {
                        ForEach(1...lengthInWeeks, id: \.self) { wk in
                            Text("Week \(wk)").tag(wk)
                        }
                    }
                    Picker("Session", selection: $sessionNumber) {
                        ForEach(1...sessionsPerWeek, id: \.self) { sess in
                            Text("Session \(sess)").tag(sess)
                        }
                    }
                }
            }
            .navigationTitle("Choose Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
