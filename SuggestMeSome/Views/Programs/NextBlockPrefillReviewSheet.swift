//
//  NextBlockPrefillReviewSheet.swift
//  SuggestMeSome
//
//  Feature 13 — Editable prefill review sheet shown before entering
//  AIProgramGeneratorView. Lets the user inspect "why," tweak defaults,
//  and explicitly confirm before generation.
//

import SwiftUI

struct NextBlockPrefillReviewSheet: View {
    let recommendation: MesocycleNextBlockRecommendation
    let onConfirm: (MesocycleNextBlockPrefill) -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: Editable State

    @State private var focus: ProgramFocus
    @State private var level: ProgramLevel
    @State private var durationWeeks: Int
    @State private var sessionsPerWeek: Int
    @State private var steeringProfile: AdaptiveSteeringProfile
    @State private var oneRMValues: [String: String]
    @State private var oneRMUnits: [String: WeightUnit]

    private let original: MesocycleNextBlockPrefill
    private let orderedLiftNames: [String]
    private let explainabilityService = AdaptiveExplainabilityService()

    init(
        recommendation: MesocycleNextBlockRecommendation,
        onConfirm: @escaping (MesocycleNextBlockPrefill) -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.recommendation = recommendation
        self.onConfirm = onConfirm
        self.onDecline = onDecline

        let prefill = recommendation.prefill
        self.original = prefill
        self.orderedLiftNames = prefill.oneRepMaxSuggestions.map(\.exerciseName)

        _focus = State(initialValue: prefill.focus)
        _level = State(initialValue: prefill.level)
        _durationWeeks = State(initialValue: prefill.durationWeeks)
        _sessionsPerWeek = State(initialValue: prefill.sessionsPerWeek)
        _steeringProfile = State(initialValue: prefill.resolvedSteeringProfile)
        _oneRMValues = State(initialValue: Dictionary(
            uniqueKeysWithValues: prefill.oneRepMaxSuggestions.map {
                ($0.exerciseName, Self.formatWeight($0.weight, unit: $0.unit))
            }
        ))
        _oneRMUnits = State(initialValue: Dictionary(
            uniqueKeysWithValues: prefill.oneRepMaxSuggestions.map { ($0.exerciseName, $0.unit) }
        ))
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    whySection
                    carriedForwardSection
                    planShapeSection
                    AdaptiveSteeringControlsCard(
                        profile: steeringProfile,
                        title: "Coach Steering",
                        subtitle: "High-level guidance only. Focus, frequency, and major block-shape changes still stay review-gated."
                    ) { steeringProfile = $0 }
                    AdaptiveExplanationCard(
                        bundle: liveExplanationBundle,
                        title: "Why this block fits",
                        compact: false
                    )
                    if !orderedLiftNames.isEmpty {
                        oneRMSection
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .navigationTitle("Review Next Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDecline() }
                }
            }
            .safeAreaInset(edge: .bottom) { ctaBar }
        }
    }

    // MARK: Why Section

    private var whySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.teal)
                Text("Why this is recommended")
                    .dsHeadline()
            }
            Text(recommendation.title)
                .font(.subheadline.weight(.semibold))
            if !recommendation.summary.isEmpty {
                Text(recommendation.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !recommendation.rationale.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recommendation.rationale, id: \.self) { point in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.teal)
                            Text(point)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Carried Forward Section

    @ViewBuilder
    private var carriedForwardSection: some View {
        let preservedNames = original.preservedExerciseNames
        let styleText = original.style?.rawValue.uppercased()
        let intensityText = original.intensityContext?.suggestedProgressionModel?.rawValue.uppercased()
        let notableLifts = original.intensityContext?.notableLiftDisplayNames ?? []

        if !preservedNames.isEmpty || styleText != nil || intensityText != nil || !notableLifts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(DSColor.primaryAction)
                    Text("Carried Forward")
                        .dsHeadline()
                }
                FlowingBadges(items: carriedForwardBadges(
                    preservedNames: preservedNames,
                    styleText: styleText,
                    intensityText: intensityText,
                    notableLifts: notableLifts
                ))
                if !original.rationaleText.isEmpty {
                    Text(original.rationaleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func carriedForwardBadges(
        preservedNames: [String],
        styleText: String?,
        intensityText: String?,
        notableLifts: [String]
    ) -> [BadgeItem] {
        var items: [BadgeItem] = []
        if let styleText {
            items.append(BadgeItem(label: "Style · \(styleText)", color: DSColor.primaryAction))
        }
        if let intensityText, intensityText != styleText {
            items.append(BadgeItem(label: "Intensity · \(intensityText)", color: .purple))
        }
        for lift in notableLifts {
            items.append(BadgeItem(label: "PR · \(lift)", color: .yellow))
        }
        for name in preservedNames {
            items.append(BadgeItem(label: name, color: .teal))
        }
        return items
    }

    // MARK: Plan Shape Section

    private var planShapeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.teal)
                Text("Program Shape")
                    .dsHeadline()
            }

            editorRow(label: "Focus", isEdited: focus != original.focus) {
                Picker("Focus", selection: $focus) {
                    ForEach(ProgramFocus.allCases, id: \.self) { focusCase in
                        Text(FocusTemplateLibrary.template(for: focusCase).displayName)
                            .tag(focusCase)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            editorRow(label: "Level", isEdited: level != original.level) {
                Picker("Level", selection: $level) {
                    ForEach(ProgramLevel.allCases, id: \.self) { lvl in
                        Text(lvl.rawValue.capitalized).tag(lvl)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            editorRow(label: "Duration", isEdited: durationWeeks != original.durationWeeks) {
                segmentedPills(options: [6, 8, 10, 12], selected: $durationWeeks) { "\($0)w" }
            }

            let minFreq = FocusTemplateLibrary.template(for: focus).minimumFrequency
            editorRow(label: "Sessions / wk", isEdited: sessionsPerWeek != original.sessionsPerWeek) {
                segmentedPills(
                    options: Array(2...6),
                    selected: $sessionsPerWeek,
                    disabled: { $0 < minFreq }
                ) { "\($0)" }
            }
            if minFreq > 2 {
                Text("\(FocusTemplateLibrary.template(for: focus).displayName) requires at least \(minFreq) sessions/week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: focus) { _, newFocus in
            let newMin = FocusTemplateLibrary.template(for: newFocus).minimumFrequency
            if sessionsPerWeek < newMin {
                sessionsPerWeek = newMin
            }
        }
    }

    // MARK: 1RM Section

    private var oneRMSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "scalemass.fill")
                    .foregroundStyle(.orange)
                Text("Starting 1RMs")
                    .dsHeadline()
            }
            ForEach(orderedLiftNames, id: \.self) { name in
                oneRMRow(for: name)
                if name != orderedLiftNames.last { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func oneRMRow(for name: String) -> some View {
        let originalSuggestion = original.oneRepMaxSuggestions.first(where: { $0.exerciseName == name })
        let isEdited = isOneRMEdited(name: name, originalSuggestion: originalSuggestion)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                editedBadge(isEdited: isEdited)
            }
            HStack(spacing: 8) {
                TextField("Weight", text: Binding(
                    get: { oneRMValues[name] ?? "" },
                    set: { oneRMValues[name] = $0 }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)

                Picker("Unit", selection: Binding(
                    get: { oneRMUnits[name] ?? .lbs },
                    set: { oneRMUnits[name] = $0 }
                )) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue.uppercased()).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 130)

                Spacer()
            }
            if let source = originalSuggestion?.sourceSummary, !source.isEmpty {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isOneRMEdited(name: String, originalSuggestion: MesocycleOneRepMaxPrefill?) -> Bool {
        guard let originalSuggestion else { return true }
        let currentUnit = oneRMUnits[name] ?? originalSuggestion.unit
        if currentUnit != originalSuggestion.unit { return true }
        let currentText = oneRMValues[name] ?? ""
        let originalText = Self.formatWeight(originalSuggestion.weight, unit: originalSuggestion.unit)
        return currentText != originalText
    }

    // MARK: CTA Bar

    private var ctaBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: onDecline) {
                    Text("Not now")
                        .dsHeadline()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 0.5))
                }
                Button(action: confirm) {
                    Text("Continue")
                        .dsHeadline()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canContinue ? Color.teal : Color.teal.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canContinue)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .background(Color(.systemBackground))
        }
    }

    private var canContinue: Bool {
        durationWeeks > 0 &&
        sessionsPerWeek >= FocusTemplateLibrary.template(for: focus).minimumFrequency
    }

    private func confirm() {
        onConfirm(liveEditedPrefill)
    }

    private var liveExplanationBundle: AdaptiveExplanationBundle {
        let provisionalPrefill = buildEditedPrefill(explanationBundle: nil)
        let provisionalRecommendation = MesocycleNextBlockRecommendation(
            stableID: recommendation.stableID,
            rank: recommendation.rank,
            kind: recommendation.kind,
            title: recommendation.title,
            summary: recommendation.summary,
            rationale: recommendation.rationale,
            targetFocus: focus,
            targetFocusDisplayName: FocusTemplateLibrary.template(for: focus).displayName,
            suggestedLevel: level,
            suggestedDurationWeeks: durationWeeks,
            suggestedSessionsPerWeek: sessionsPerWeek,
            decision: recommendation.decision,
            prefill: provisionalPrefill,
            isPrimaryRecommendation: recommendation.isPrimaryRecommendation,
            fitScore: recommendation.fitScore,
            fitNote: recommendation.fitNote,
            requiresExplicitAcceptance: recommendation.requiresExplicitAcceptance
        )

        return explainabilityService.buildNextBlockExplanation(
            recommendation: provisionalRecommendation,
            steeringProfile: steeringProfile
        )
    }

    private var liveEditedPrefill: NextBlockPrefillContext {
        buildEditedPrefill(explanationBundle: liveExplanationBundle)
    }

    private func buildEditedPrefill(
        explanationBundle: AdaptiveExplanationBundle?
    ) -> NextBlockPrefillContext {
        let editedSuggestions: [MesocycleOneRepMaxPrefill] = orderedLiftNames.compactMap { name in
            let originalSuggestion = original.oneRepMaxSuggestions.first(where: { $0.exerciseName == name })
            let unit = oneRMUnits[name] ?? originalSuggestion?.unit ?? .lbs
            let text = oneRMValues[name] ?? ""
            guard let weight = Double(text), weight > 0 else {
                return originalSuggestion
            }
            return MesocycleOneRepMaxPrefill(
                exerciseName: name,
                weight: weight,
                unit: unit,
                sourceSummary: originalSuggestion?.sourceSummary ?? ""
            )
        }

        let edited = NextBlockPrefillContext(
            sourceProgramRunStableID: original.sourceProgramRunStableID,
            recommendationStableID: original.recommendationStableID,
            focus: focus,
            style: original.style,
            level: level,
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            oneRepMaxSuggestions: editedSuggestions,
            preservedExerciseNames: original.preservedExerciseNames,
            rationaleText: original.rationaleText,
            valueSources: original.valueSources,
            intensityContext: original.intensityContext,
            notes: original.notes,
            steeringProfile: steeringProfile,
            explanationBundle: explanationBundle
        )
        return edited
    }

    // MARK: Helpers

    @ViewBuilder
    private func editorRow<Editor: View>(
        label: String,
        isEdited: Bool,
        @ViewBuilder editor: () -> Editor
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                editedBadge(isEdited: isEdited)
            }
            editor()
        }
    }

    @ViewBuilder
    private func editedBadge(isEdited: Bool) -> some View {
        Text(isEdited ? "Edited" : "Recommended")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background((isEdited ? Color.orange : Color.secondary).opacity(0.15))
            .foregroundStyle(isEdited ? Color.orange : Color.secondary)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func segmentedPills<T: Hashable>(
        options: [T],
        selected: Binding<T>,
        disabled: ((T) -> Bool)? = nil,
        label: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = selected.wrappedValue == option
                let isDisabled = disabled?(option) ?? false
                Button {
                    selected.wrappedValue = option
                } label: {
                    Text(label(option))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? DSColor.primaryAction : Color(.systemBackground))
                        .foregroundStyle(
                            isDisabled
                                ? Color(.tertiaryLabel)
                                : (isSelected ? .white : .primary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
    }

    private static func formatWeight(_ weight: Double, unit: WeightUnit) -> String {
        switch unit {
        case .lbs:
            return String(Int(weight.rounded()))
        case .kg:
            let rounded = (weight * 10).rounded() / 10
            return rounded == rounded.rounded(.towardZero)
                ? String(Int(rounded))
                : String(format: "%.1f", rounded)
        }
    }
}

// MARK: - Small helpers

private struct BadgeItem: Identifiable {
    let id = UUID()
    let label: String
    let color: Color
}

private struct FlowingBadges: View {
    let items: [BadgeItem]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { item in
                Text(item.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(item.color.opacity(0.15))
                    .foregroundStyle(item.color)
                    .clipShape(Capsule())
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            totalWidth = max(totalWidth, x)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
