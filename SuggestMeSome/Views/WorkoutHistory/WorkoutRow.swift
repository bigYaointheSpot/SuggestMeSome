import SwiftUI

struct WorkoutRow: View {
    let workout: Workout

    private var hasPersonalRecord: Bool {
        workout.exerciseEntries.contains { entry in
            entry.sets.contains(where: \.isPR)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(
                        workout.date,
                        format: .dateTime
                            .weekday(.abbreviated)
                            .month(.abbreviated)
                            .day()
                            .year()
                    )
                    .font(.headline)

                    if hasPersonalRecord {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }

                    if let badge = workout.sourceBadgeLabel {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(workout.formattedDuration)
                    Text("·")

                    if workout.isHealthKitImported {
                        if let importedType = workout.importedWorkoutTypeLabel {
                            Text(importedType)
                        } else {
                            Text(exerciseCountLabel)
                        }
                    } else {
                        Text(exerciseCountLabel)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var exerciseCountLabel: String {
        let count = workout.exerciseEntries.count
        return "\(count) \(count == 1 ? "exercise" : "exercises")"
    }
}
