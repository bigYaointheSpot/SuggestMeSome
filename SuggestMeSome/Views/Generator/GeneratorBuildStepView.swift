import SwiftUI

struct SuggestMeSomeBuildStepView: View {
    @Bindable var viewModel: SuggestMeSomeGeneratorFlowViewModel
    let onStart: (GeneratedWorkout) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryHeader

                if let workout = viewModel.generatedWorkout {
                    if workout.exercises.isEmpty {
                        ContentUnavailableView(
                            "No Exercises Generated",
                            systemImage: "dumbbell",
                            description: Text("Try a different mode or a longer duration.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(workout.exercises.indices, id: \.self) { index in
                            exerciseCard(workout.exercises[index])
                        }
                        startButton(workout)
                    }
                } else {
                    ProgressView("Building workout...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.reshuffleWorkout()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .disabled(viewModel.generatedWorkout == nil)
            }
        }
    }

    private var summaryHeader: some View {
        let request = viewModel.recommendation?.request
        let duration = Int(request?.durationMinutes ?? 0)
        let intensity = request?.intensity ?? viewModel.configuration.intensity
        let count = viewModel.generatedWorkout?.exercises.count ?? 0

        return HStack(spacing: 12) {
            Label("\(duration)m", systemImage: "clock")
            Text("·").foregroundStyle(.secondary)
            Label("Intensity \(intensity)", systemImage: "bolt.fill")
            Text("·").foregroundStyle(.secondary)
            Label("\(count) \(count == 1 ? "exercise" : "exercises")", systemImage: "dumbbell")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func exerciseCard(_ exercise: GeneratedExercise) -> some View {
        if exercise.exercise.exerciseType == .cardio {
            cardioCard(exercise)
        } else {
            strengthCard(exercise)
        }
    }

    private func cardioCard(_ exercise: GeneratedExercise) -> some View {
        let totalSeconds = Int(exercise.effectiveTimeMinutes * 60)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        let durationText = secs > 0
            ? String(format: "%d min %02d sec", mins, secs)
            : "\(mins) min"

        return HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exercise.name).font(.headline)
                Text(durationText).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Cardio")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func strengthCard(_ exercise: GeneratedExercise) -> some View {
        let warmupSets = exercise.sets.filter(\.isWarmup)
        let workingSets = exercise.sets.filter { !$0.isWarmup }
        let unit = exercise.sets.first?.unit ?? .lbs

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(exercise.exercise.name).font(.headline)
                Spacer()
                Text(exercise.exercise.exerciseType.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            HStack(spacing: 8) {
                Text("SET").frame(width: 40, alignment: .center)
                Text("REPS").frame(maxWidth: .infinity)
                Text("WEIGHT (\(unit.rawValue))").frame(maxWidth: .infinity)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground))

            if !warmupSets.isEmpty {
                sectionLabel("WARMUP")
                ForEach(warmupSets.indices, id: \.self) { index in
                    setRow(warmupSets[index], isWarmup: true)
                    if index < warmupSets.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }

            if !workingSets.isEmpty {
                sectionLabel("WORKING")
                ForEach(workingSets.indices, id: \.self) { index in
                    setRow(workingSets[index], isWarmup: false)
                    if index < workingSets.count - 1 {
                        Divider().padding(.leading, 12)
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
    }

    private func setRow(_ set: GeneratedSet, isWarmup: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isWarmup ? "W\(set.setNumber)" : "\(set.setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isWarmup ? Color(.systemGray3) : .secondary)
                .frame(width: 40, alignment: .center)

            Text("\(set.suggestedReps)")
                .frame(maxWidth: .infinity, alignment: .center)

            Text(set.suggestedWeight.map { formatWeight($0) } ?? "—")
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(set.suggestedWeight == nil ? Color(.systemGray3) : .primary)
        }
        .font(.subheadline)
        .foregroundStyle(isWarmup ? .secondary : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func startButton(_ workout: GeneratedWorkout) -> some View {
        Button {
            onStart(workout)
        } label: {
            Label("Start This Workout", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(weight))
            : String(format: "%.1f", weight)
    }
}
