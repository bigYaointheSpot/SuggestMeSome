//
//  WorkoutDetailView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

struct WorkoutDetailView: View {
    let workout: Workout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                sourceMetadataCard
                if workout.isHealthKitImported {
                    importedSummaryCard
                }
                exerciseSections
                if let notes = workout.comments, !notes.isEmpty {
                    notesCard(notes)
                }
            }
            .padding()
        }
        .navigationTitle("Workout Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Edit") {
                    WorkoutEditView(workout: workout)
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            Text(workout.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Divider()

            HStack(spacing: 0) {
                DetailStat(icon: "clock", label: "Duration", value: workout.formattedDuration)

                if let cals = workout.caloriesBurned {
                    Divider().frame(height: 44)
                    DetailStat(icon: "flame.fill", label: "Calories", value: "\(cals) kcal", iconColor: .orange)
                }

                Divider().frame(height: 44)
                if workout.isHealthKitImported, workout.exerciseEntries.isEmpty, let importedType = workout.importedWorkoutTypeLabel {
                    DetailStat(icon: "waveform.path.ecg", label: "Activity", value: importedType)
                } else {
                    let count = workout.exerciseEntries.count
                    DetailStat(icon: "dumbbell.fill", label: "Exercises", value: "\(count)")
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Exercise sections

    private var sourceMetadataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Source")
                Spacer()
                Text(workout.sourceLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if workout.sourceType == .loggedInApp {
                HStack {
                    Text("Apple Health Writeback")
                    Spacer()
                    if let exportedAt = workout.healthKitExportedAt {
                        Text(exportedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not exported")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)

                if let writebackID = workout.healthKitWritebackIdentifier, !writebackID.isEmpty {
                    HStack {
                        Text("Apple Health ID")
                        Spacer()
                        Text(writebackID)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var exerciseSections: some View {
        if workout.exerciseEntries.isEmpty {
            if workout.isHealthKitImported {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No set-by-set details imported", systemImage: "info.circle")
                        .font(.headline)
                    Text("This Apple Health workout was imported without native exercise or set structure.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        } else {
            ForEach(workout.exerciseEntries.sorted(by: { $0.orderIndex < $1.orderIndex })) { entry in
                ExerciseDetailCard(entry: entry)
            }
        }
    }

    private var importedSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.pink)
                Text("Imported from Apple Health")
                    .font(.headline)
                Spacer()
                if let badge = workout.sourceBadgeLabel {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }
            }

            if let importedType = workout.importedWorkoutTypeLabel {
                HStack {
                    Text("Activity")
                    Spacer()
                    Text(importedType)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            if let importedAt = workout.sourceImportedAt {
                HStack {
                    Text("Imported")
                    Spacer()
                    Text(importedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Notes

    private func notesCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Workout Notes", systemImage: "note.text")
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - DetailStat

struct DetailStat: View {
    let icon: String
    let label: String
    let value: String
    var iconColor: Color = .blue

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ExerciseDetailCard

struct ExerciseDetailCard: View {
    let entry: ExerciseEntry

    private var sortedSets: [SetEntry] {
        entry.sets.sorted { $0.setNumber < $1.setNumber }
    }

    var body: some View {
        if entry.isCardio {
            cardioCard
        } else {
            strengthCard
        }
    }

    // MARK: Cardio

    private var cardioCard: some View {
        HStack {
            Label(entry.exerciseName, systemImage: "figure.run")
                .font(.headline)
            Spacer()
            if let secs = entry.cardioDurationSeconds, secs > 0 {
                Text(formattedDuration(secs))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: Strength

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(entry.exerciseName)
                    .font(.headline)
                Spacer()
                Text(entry.unit.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            // Column headers
            HStack(spacing: 8) {
                Text("SET").frame(width: 36, alignment: .center)
                Text("REPS").frame(maxWidth: .infinity)
                Text("WEIGHT (\(entry.unit.rawValue))").frame(maxWidth: .infinity)
                Image(systemName: "star.fill").opacity(0).frame(width: 22)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground))

            // Set rows
            ForEach(Array(sortedSets.enumerated()), id: \.element.id) { item in
                HStack(spacing: 8) {
                    Text("\(item.element.setNumber)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .center)

                    Text("\(item.element.reps)")
                        .frame(maxWidth: .infinity)

                    Text(item.element.weight, format: .number)
                        .frame(maxWidth: .infinity)

                    Image(systemName: item.element.isPR ? "star.fill" : "star")
                        .foregroundStyle(item.element.isPR ? .yellow : Color(.systemGray3))
                        .frame(width: 22)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))

                if item.offset < sortedSets.count - 1 {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
    }
}
