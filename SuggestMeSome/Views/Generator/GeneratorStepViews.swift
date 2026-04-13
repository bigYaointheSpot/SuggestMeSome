import SwiftUI

struct SuggestMeSomeConfigurationStepView: View {
    @Bindable var viewModel: SuggestMeSomeGeneratorFlowViewModel
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                modeSection
                goalSection
                equipmentSection
                DurationPickerView(duration: viewModel.configuration.durationMinutes) {
                    viewModel.updateDuration($0)
                }
                IntensitySelectorView(intensity: viewModel.configuration.intensity) {
                    viewModel.updateIntensity($0)
                }
                continueButton
            }
            .padding()
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mode", systemImage: "dial.high")
                .font(.headline)

            let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SuggestMeSomeSessionMode.allCases) { mode in
                    selectionChip(
                        title: mode.title,
                        isSelected: viewModel.configuration.mode == mode
                    ) {
                        viewModel.configuration.mode = mode
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Goal", systemImage: "target")
                .font(.headline)

            let columns = [GridItem(.adaptive(minimum: 130), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(SuggestMeSomeGenerationGoal.allCases) { goal in
                    selectionChip(
                        title: goal.title,
                        isSelected: viewModel.configuration.goal == goal
                    ) {
                        viewModel.configuration.goal = goal
                    }
                }
            }
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Equipment Profile", systemImage: "dumbbell")
                .font(.headline)

            Picker("Equipment", selection: $viewModel.configuration.equipmentProfile) {
                ForEach(SuggestMeSomeEquipmentProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var continueButton: some View {
        Button {
            onContinue()
        } label: {
            Label("Get Recommendation", systemImage: "sparkles")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.purple)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 4)
    }

    private func selectionChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 42)
                .padding(.horizontal, 8)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Recommendation Step

struct SuggestMeSomeRecommendationStepView: View {
    @Bindable var viewModel: SuggestMeSomeGeneratorFlowViewModel
    let onBuildWorkout: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let recommendation = viewModel.recommendation {
                    recommendationCard(recommendation)
                    buildArea(recommendation)
                } else {
                    ContentUnavailableView(
                        "No Recommendation",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Go back and try different inputs to generate a session recommendation.")
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Recommendation card

    private func recommendationCard(_ recommendation: SuggestMeSomeSessionRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Label("Recommended Session", systemImage: "lightbulb.max.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            // Session title
            Text(recommendation.title)
                .font(.title3.weight(.semibold))

            // Reason chips — compact horizontal scroll row
            if !recommendation.reasonChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recommendation.reasonChips, id: \.self) { chip in
                            reasonChip(chip)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            // Summary — plain-English "why this session"
            Text(recommendation.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            continuitySection(recommendation)

            // Redirect notice — shown only when mode was adjusted
            if recommendation.wasRedirected {
                redirectNotice(recommendation)
            }

            // Session plan section
            if recommendation.isBuildableIntoWorkout {
                Divider()
                sessionPlanSection(recommendation)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func continuitySection(_ recommendation: SuggestMeSomeSessionRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTINUITY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(recommendation.continuitySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Next: \(recommendation.nextActionGuidance)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reasonChip(_ text: String) -> some View {
        let isConflict = text.contains("avoided") || text == "Mode adjusted"
            || text == "High recent overlap" || text == "Program-aware"

        return Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isConflict ? Color.orange.opacity(0.15) : Color(.tertiarySystemBackground))
            .foregroundStyle(isConflict ? Color.orange : Color.secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    isConflict ? Color.orange.opacity(0.35) : Color(.separator),
                    lineWidth: 0.5
                )
            )
    }

    private func redirectNotice(_ recommendation: SuggestMeSomeSessionRecommendation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 2)
            Text(recommendation.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sessionPlanSection(_ recommendation: SuggestMeSomeSessionRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SESSION PLAN")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            // Key lifts as chips
            if !recommendation.candidateAnchorLifts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(recommendation.candidateAnchorLifts, id: \.self) { lift in
                        Text(lift)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }

            // Movement priorities (up to 3)
            ForEach(Array(recommendation.recommendedMovementPriorities.prefix(3)), id: \.self) { priority in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green.opacity(0.7))
                        .padding(.top, 1)
                    Text(priority)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Build area

    @ViewBuilder
    private func buildArea(_ recommendation: SuggestMeSomeSessionRecommendation) -> some View {
        if recommendation.isBuildableIntoWorkout {
            Button {
                onBuildWorkout()
            } label: {
                Label("Build This Session", systemImage: "hammer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else {
            notBuildableNotice
        }
    }

    private var notBuildableNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Duration too short")
                    .font(.subheadline.weight(.semibold))
                Text("Go back and set at least 20 minutes to build a session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
