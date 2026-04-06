//
//  TrainingProgramsTab.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/6/26.
//

import SwiftUI
import SwiftData

// MARK: - TrainingProgramsTab

struct TrainingProgramsTab: View {
    @Query private var programRuns: [ProgramRun]
    @Query(sort: \Workout.date, order: .reverse) private var allWorkouts: [Workout]

    var sortedRuns: [ProgramRun] {
        let active = programRuns
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }
        let completed = programRuns
            .filter { $0.isCompleted }
            .sorted { ($0.endDate ?? $0.startDate) > ($1.endDate ?? $1.startDate) }
        return active + completed
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                programButtonRow
                Divider()
                programRunList
            }
            .navigationTitle("Training Programs")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Sub-views

    private var programButtonRow: some View {
        HStack(spacing: 8) {
            NavigationLink {
                CreateProgramView()
            } label: {
                Text("Create Your Own Program")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            NavigationLink {
                SelectProgramView()
            } label: {
                Text("Use Existing Program")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.purple)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var programRunList: some View {
        if sortedRuns.isEmpty {
            ContentUnavailableView(
                "No Programs Yet",
                systemImage: "list.clipboard",
                description: Text("Create or start a program above to track your progress.")
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedRuns) { run in
                        ProgramRunExpandableRow(run: run, allWorkouts: allWorkouts)
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - ProgramRunRow

struct ProgramRunRow: View {
    let run: ProgramRun
    let allWorkouts: [Workout]

    var completedWorkouts: Int {
        allWorkouts.filter { $0.programRun?.id == run.id }.count
    }

    var totalWorkouts: Int {
        guard let program = run.program else { return 0 }
        return program.lengthInWeeks * program.sessionsPerWeek
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.program?.name ?? "Unknown Program")
                    .font(.headline)
                Spacer()
                Text(run.isCompleted ? "Completed" : "Active")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(run.isCompleted ? Color.gray.opacity(0.25) : Color.green.opacity(0.25))
                    .foregroundStyle(run.isCompleted ? Color.secondary : Color.green)
                    .clipShape(Capsule())
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption)
                Text(run.startDate.formatted(date: .abbreviated, time: .omitted))
                Text("·")
                Text("\(completedWorkouts)/\(totalWorkouts) workouts")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ProgramRunExpandableRow

struct ProgramRunExpandableRow: View {
    @Bindable var run: ProgramRun
    let allWorkouts: [Workout]
    @Environment(\.modelContext) private var modelContext

    @State private var isExpanded = false
    @State private var selectedWeek = 1
    @State private var expandedSessions: Set<Int> = []
    @State private var showingEndConfirmation = false

    private var runWorkouts: [Workout] {
        allWorkouts.filter { $0.programRun?.id == run.id }
    }

    private var completedCount: Int { runWorkouts.count }

    private var totalWorkouts: Int {
        guard let p = run.program else { return 0 }
        return p.lengthInWeeks * p.sessionsPerWeek
    }

    private var sourceLabel: String {
        switch run.program?.source {
        case .userCreated: return "Custom Program"
        case .template: return "Template"
        case .aiGenerated: return "AI Generated"
        case nil: return "Unknown"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowHeader
            if isExpanded {
                expandedContent
                    .transition(.opacity)
            }
        }
        .confirmationDialog("End Program?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End Program", role: .destructive) {
                run.isCompleted = true
                run.endDate = Date.now
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark the program as completed.")
        }
    }

    // MARK: Row Header

    private var rowHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                ProgramRunRow(run: run, allWorkouts: allWorkouts)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            infoSection
            if !run.isCompleted {
                Divider()
                endProgramRow
            }
            Divider()
            weekPickerSection
            Divider()
            sessionSection
        }
    }

    // MARK: Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                infoRow(label: "Status") {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(run.isCompleted ? Color.gray : Color.green)
                            .frame(width: 7, height: 7)
                        Text(run.isCompleted ? "Completed" : "Active")
                            .foregroundStyle(run.isCompleted ? Color.secondary : Color.green)
                    }
                }
                infoRow(label: "Started") {
                    Text(run.startDate.formatted(date: .abbreviated, time: .omitted))
                }
                if let endDate = run.endDate {
                    infoRow(label: "Ended") {
                        Text(endDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                infoRow(label: "Length") {
                    Text("\(run.program?.lengthInWeeks ?? 0) weeks")
                }
                infoRow(label: "Progress") {
                    Text("\(completedCount) of \(totalWorkouts) workouts completed")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func infoRow<V: View>(label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            value()
        }
        .font(.subheadline)
    }

    // MARK: End Program Row

    private var endProgramRow: some View {
        Button {
            showingEndConfirmation = true
        } label: {
            Text("End Program")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Week Picker

    private var weekPickerSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...(run.program?.lengthInWeeks ?? 1), id: \.self) { week in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedWeek = week
                            expandedSessions = []
                        }
                    } label: {
                        Text("Week \(week)")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedWeek == week ? Color.blue : Color(.tertiarySystemBackground))
                            .foregroundStyle(selectedWeek == week ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Session Section

    @ViewBuilder
    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sessionsPerWeek = run.program?.sessionsPerWeek, sessionsPerWeek > 0 {
                ForEach(1...sessionsPerWeek, id: \.self) { sessionNumber in
                    sessionCard(sessionNumber: sessionNumber)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Session Card

    @ViewBuilder
    private func sessionCard(sessionNumber: Int) -> some View {
        let workout = runWorkouts.first {
            $0.programWeekNumber == selectedWeek && $0.programSessionNumber == sessionNumber
        }
        let isCompleted = workout != nil
        let isSessionExpanded = expandedSessions.contains(sessionNumber)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isSessionExpanded {
                        expandedSessions.remove(sessionNumber)
                    } else {
                        expandedSessions.insert(sessionNumber)
                    }
                }
            } label: {
                HStack {
                    Text("Session \(sessionNumber)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if isCompleted {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text("Not completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isSessionExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isSessionExpanded)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSessionExpanded {
                Divider().padding(.leading, 14)
                if let w = workout {
                    sessionWorkoutDetail(workout: w)
                } else {
                    sessionPlannedDetail(sessionNumber: sessionNumber)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
    }

    // MARK: Completed Session Detail

    @ViewBuilder
    private func sessionWorkoutDetail(workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(workout.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("View Full Workout", systemImage: "arrow.right.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
            }

            ForEach(workout.exerciseEntries.sorted { $0.orderIndex < $1.orderIndex }) { entry in
                ExerciseDetailCard(entry: entry)
            }
        }
        .padding(12)
    }

    // MARK: Planned Session Detail

    @ViewBuilder
    private func sessionPlannedDetail(sessionNumber: Int) -> some View {
        let weekTemplate = run.program?.weeks.first { $0.weekNumber == selectedWeek }
        let sessionTemplate = weekTemplate?.sessions.first { $0.sessionNumber == sessionNumber }
        let exercises = (sessionTemplate?.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }

        if exercises.isEmpty {
            Text("No exercises planned for this session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(exercises) { exercise in
                    HStack {
                        Text(exercise.exerciseName)
                            .font(.subheadline)
                        Spacer()
                        Group {
                            if let sets = exercise.targetSets, let reps = exercise.targetReps {
                                Text("\(sets)×\(reps) planned")
                            } else if let sets = exercise.targetSets {
                                Text("\(sets) sets planned")
                            } else {
                                Text("Planned")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if exercise.id != exercises.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }
}
