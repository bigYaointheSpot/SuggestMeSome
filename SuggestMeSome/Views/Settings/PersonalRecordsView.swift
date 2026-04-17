//
//  PersonalRecordsView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

struct PersonalRecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersonalRecord.exerciseName) private var records: [PersonalRecord]
    @State private var showingClearAllConfirmation = false

    /// Records grouped by exercise name, each group sorted by rep count ascending.
    var grouped: [(exerciseName: String, records: [PersonalRecord])] {
        let dict = Dictionary(grouping: records, by: \.exerciseName)
        return dict
            .map { (exerciseName: $0.key, records: $0.value.sorted { $0.repCount < $1.repCount }) }
            .sorted { $0.exerciseName < $1.exerciseName }
    }

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Personal Records Yet",
                    systemImage: "trophy",
                    description: Text("PRs are recorded automatically when you hit a new best weight for a given rep count.")
                )
            } else {
                List {
                    ForEach(grouped, id: \.exerciseName) { group in
                        Section(group.exerciseName) {
                            ForEach(group.records) { record in
                                PRRow(record: record)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Personal Records")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Wipe PR Data", role: .destructive) {
                        showingClearAllConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Wipe All PR Data?",
            isPresented: $showingClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Wipe PR Data", role: .destructive) {
                try? PersonalRecordMaintenanceService.clearAllPRData(context: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all personal record rows and clears the PR markers on saved sets.")
        }
    }
}

// MARK: - PRRow

struct PRRow: View {
    let record: PersonalRecord

    var formattedWeight: String {
        let w = record.weight
        let num = w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : "\(w)"
        return "\(num) \(record.unit.rawValue)"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Rep count badge
            Text("\(record.repCount)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .frame(width: 36, alignment: .center)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.repCount) \(record.repCount == 1 ? "rep" : "reps")")
                    .font(.subheadline.weight(.semibold))
                Text(record.dateAchieved, format: .dateTime
                    .weekday(.abbreviated)
                    .month(.abbreviated)
                    .day()
                    .year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text(formattedWeight)
                    .font(.headline)
            }
        }
        .padding(.vertical, 2)
    }
}
