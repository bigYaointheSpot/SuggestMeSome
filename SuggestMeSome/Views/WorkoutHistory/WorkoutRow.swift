import SwiftUI

struct WorkoutRow: View {
    let workout: Workout

    private var hasPersonalRecord: Bool {
        workout.exerciseEntries.contains { entry in
            entry.sets.contains(where: \.isPR)
        }
    }

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.xs) {
                    Text(
                        workout.date,
                        format: .dateTime
                            .weekday(.abbreviated)
                            .month(.abbreviated)
                            .day()
                            .year()
                    )
                    .dsHeadline()

                    if hasPersonalRecord {
                        Image(systemName: "star.fill")
                            .foregroundStyle(DSGradient.prCelebration)
                            .font(.caption)
                            .accessibilityHidden(true)
                    }

                    if let badge = workout.sourceBadgeLabel {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, DSSpacing.s)
                            .padding(.vertical, 2)
                            .background(DSSurface.elevated)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: DSSpacing.xs) {
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
                .dsCaption()
            }

            Spacer()
        }
        .padding(.vertical, DSSpacing.xs)
    }

    private var exerciseCountLabel: String {
        let count = workout.exerciseEntries.count
        return "\(count) \(count == 1 ? "exercise" : "exercises")"
    }
}
