//
//  PersonalRecordsView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/5/26.
//

import SwiftUI
import SwiftData

struct PersonalRecordListGroupSnapshot {
    let exerciseName: String
    let records: [PersonalRecord]
}

struct PersonalRecordListSnapshot {
    static let empty = PersonalRecordListSnapshot(groups: [])

    let groups: [PersonalRecordListGroupSnapshot]

    static func build(records: [PersonalRecord]) -> PersonalRecordListSnapshot {
        let grouped = Dictionary(grouping: records, by: \.exerciseName)
            .map { exerciseName, records in
                PersonalRecordListGroupSnapshot(
                    exerciseName: exerciseName,
                    records: records.sorted { lhs, rhs in
                        if lhs.repCount != rhs.repCount {
                            return lhs.repCount < rhs.repCount
                        }
                        if lhs.weight != rhs.weight {
                            return lhs.weight > rhs.weight
                        }
                        return lhs.dateAchieved > rhs.dateAchieved
                    }
                )
            }
            .sorted { $0.exerciseName < $1.exerciseName }

        return PersonalRecordListSnapshot(groups: grouped)
    }

    static func refreshToken(for records: [PersonalRecord]) -> Int {
        let fingerprints = records
            .map {
                PersonalRecordFingerprint(
                    id: $0.id,
                    exerciseName: $0.exerciseName,
                    repCount: $0.repCount,
                    weight: $0.weight,
                    unitRawValue: $0.unit.rawValue,
                    dateAchieved: $0.dateAchieved
                )
            }
            .sorted {
                if $0.exerciseName != $1.exerciseName {
                    return $0.exerciseName < $1.exerciseName
                }
                if $0.repCount != $1.repCount {
                    return $0.repCount < $1.repCount
                }
                return $0.id.uuidString < $1.id.uuidString
            }

        var hasher = Hasher()
        for fingerprint in fingerprints {
            hasher.combine(fingerprint.id)
            hasher.combine(fingerprint.exerciseName)
            hasher.combine(fingerprint.repCount)
            hasher.combine(fingerprint.weight)
            hasher.combine(fingerprint.unitRawValue)
            hasher.combine(fingerprint.dateAchieved)
        }
        return hasher.finalize()
    }
}

private struct PersonalRecordFingerprint {
    let id: UUID
    let exerciseName: String
    let repCount: Int
    let weight: Double
    let unitRawValue: String
    let dateAchieved: Date
}

struct PersonalRecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersonalRecord.exerciseName) private var records: [PersonalRecord]
    @State private var showingClearAllConfirmation = false
    @State private var snapshot = PersonalRecordListSnapshot.empty

    private var refreshToken: Int {
        PersonalRecordListSnapshot.refreshToken(for: records)
    }

    var body: some View {
        Group {
            if records.isEmpty {
                DSEmptyState(
                    systemImage: "trophy",
                    title: "No Personal Records Yet",
                    message: "PRs are recorded automatically when you hit a new best weight for a given rep count."
                )
            } else {
                List {
                    ForEach(snapshot.groups, id: \.exerciseName) { group in
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
        .task(id: refreshToken) {
            snapshot = PersonalRecordListSnapshot.build(records: records)
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
                    .dsHeadline()
            }
        }
        .padding(.vertical, 2)
    }
}
