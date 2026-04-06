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
            List {
                ForEach(sortedRuns) { run in
                    ProgramRunRow(run: run, allWorkouts: allWorkouts)
                }
            }
            .listStyle(.plain)
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
                    .foregroundStyle(run.isCompleted ? .secondary : .green)
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

// MARK: - Placeholder Views

struct CreateProgramView: View {
    var body: some View {
        Text("Create Program - Coming Soon")
            .foregroundStyle(.secondary)
            .navigationTitle("Create Program")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct SelectProgramView: View {
    var body: some View {
        Text("Select Program - Coming Soon")
            .foregroundStyle(.secondary)
            .navigationTitle("Use Existing Program")
            .navigationBarTitleDisplayMode(.inline)
    }
}
