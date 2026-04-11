//
//  DataExportView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

struct DataExportView: View {
    @Query(sort: \Workout.date) private var allWorkouts: [Workout]
    @Query(sort: \MuscleGroup.name) private var muscleGroups: [MuscleGroup]

    @State private var exportURL: URL?
    @State private var isGenerating = false

    // MARK: - Computed

    private var exerciseGroupLookup: [String: String] {
        muscleGroups.reduce(into: [:]) { result, group in
            for exercise in group.exercises {
                result[exercise.name] = group.name
            }
        }
    }

    private var totalExercises: Int {
        allWorkouts.flatMap(\.exerciseEntries).count
    }

    private var totalSets: Int {
        allWorkouts.flatMap(\.exerciseEntries).flatMap(\.sets).count
    }

    private func buildCSV() -> String {
        var rows: [String] = ["Date,Duration,Exercise,Muscle Group,Set,Weight,Unit,Reps,PR"]
        let groupLookup = exerciseGroupLookup
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]

        for workout in allWorkouts {
            let dateStr  = df.string(from: workout.date)
            let duration = workout.formattedDuration
            let entries  = workout.exerciseEntries.sorted { $0.orderIndex < $1.orderIndex }

            for entry in entries {
                let name  = csvEscape(entry.exerciseName)
                let group = csvEscape(groupLookup[entry.exerciseName] ?? "")

                if entry.isCardio {
                    let secs = entry.cardioDurationSeconds ?? 0
                    rows.append("\(dateStr),\(duration),\(name),\(group),1,\(secs),sec,1,false")
                } else {
                    for set in entry.sets.sorted(by: { $0.setNumber < $1.setNumber }) {
                        rows.append(
                            "\(dateStr),\(duration),\(name),\(group),\(set.setNumber),\(set.weight),\(entry.unit.rawValue),\(set.reps),\(set.isPR ? "true" : "false")"
                        )
                    }
                }
            }
        }
        return rows.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    // MARK: - Body

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Workouts", value: "\(allWorkouts.count)")
                LabeledContent("Exercise Entries", value: "\(totalExercises)")
                LabeledContent("Total Sets", value: "\(totalSets)")
            }

            Section {
                Button {
                    generate()
                } label: {
                    if isGenerating {
                        HStack(spacing: 10) {
                            ProgressView().scaleEffect(0.85)
                            Text("Generating…")
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Label(
                            exportURL == nil ? "Generate CSV Export" : "Re-generate Export",
                            systemImage: "doc.text"
                        )
                    }
                }
                .disabled(isGenerating || allWorkouts.isEmpty)

                if let url = exportURL {
                    ShareLink(
                        item: url,
                        subject: Text("SuggestMeSome Workout Data"),
                        message: Text("My workout history exported from SuggestMeSome.")
                    ) {
                        Label("Share CSV File", systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                if allWorkouts.isEmpty {
                    Text("No workout data to export.")
                } else {
                    Text("CSV includes date, duration, exercise, muscle group, set, weight, unit, reps, and PR status for every logged set.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Export Workout Data")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Actions

    private func generate() {
        isGenerating = true
        let csv = buildCSV()
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuggestMeSome_Workouts.csv")
        do {
            try csv.write(to: tmpURL, atomically: true, encoding: .utf8)
            exportURL = tmpURL
        } catch {
            // File write failed; leave exportURL nil so user sees no Share button
        }
        isGenerating = false
    }
}
