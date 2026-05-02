//
//  AIProgramGeneratorView.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/7/26.
//

import SwiftUI
import SwiftData

// MARK: - AIProgramGeneratorView

struct AIProgramGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Query private var allPRs: [PersonalRecord]
    private let initialPrefill: MesocycleNextBlockPrefill?

    // MARK: AppStorage (persists across sessions)

    @AppStorage("generator.ai.focus")     private var savedFocusRaw  = ""
    @AppStorage("generator.ai.level")     private var savedLevelRaw  = ""
    @AppStorage("generator.ai.duration")  private var savedDuration  = 0
    @AppStorage("generator.ai.frequency") private var savedFrequency = 0

    // MARK: Step

    @State private var step = 1

    // MARK: Screen 1 State

    @State private var selectedFocus: ProgramFocus?
    @State private var selectedLevel: ProgramLevel?
    @State private var selectedDuration = 0
    @State private var selectedFrequency = 0
    @State private var steeringProfile: AdaptiveSteeringProfile

    // MARK: Screen 2 State

    @State private var oneRMValues: [String: String] = [:]
    @State private var oneRMUnits: [String: WeightUnit] = [:]

    // MARK: Generation State

    @State private var isGenerating = false
    @State private var generatedProgram: TrainingProgram?
    @State private var lastInput: ProgramGenerationInput?
    @State private var derivedState = ProgramGeneratorDerivedState.placeholder

    private let service = ProgramGenerationService()

    init(prefill: MesocycleNextBlockPrefill? = nil) {
        self.initialPrefill = prefill
        _selectedFocus = State(initialValue: prefill?.focus)
        _selectedLevel = State(initialValue: prefill?.level)
        _selectedDuration = State(initialValue: prefill?.durationWeeks ?? 0)
        _selectedFrequency = State(initialValue: prefill?.sessionsPerWeek ?? 0)
        _steeringProfile = State(initialValue: prefill?.resolvedSteeringProfile ?? .balanced)
        _oneRMValues = State(initialValue: Dictionary(
            uniqueKeysWithValues: (prefill?.oneRepMaxSuggestions ?? []).map { suggestion in
                let value: String
                switch suggestion.unit {
                case .lbs:
                    value = String(Int(suggestion.weight.rounded()))
                case .kg:
                    let rounded = suggestion.weight.rounded(toPlaces: 1)
                    value = rounded == rounded.rounded(.towardZero)
                        ? String(Int(rounded))
                        : String(format: "%.1f", rounded)
                }
                return (suggestion.exerciseName, value)
            }
        ))
        _oneRMUnits = State(initialValue: Dictionary(
            uniqueKeysWithValues: (prefill?.oneRepMaxSuggestions ?? []).map {
                ($0.exerciseName, $0.unit)
            }
        ))
    }

    // MARK: Computed Helpers

    private var focusTemplate: FocusTemplate? {
        selectedFocus.map { FocusTemplateLibrary.template(for: $0) }
    }

    private var minimumFrequency: Int {
        focusTemplate?.minimumFrequency ?? 2
    }

    private var isCardioFocus: Bool {
        selectedFocus == .cardioEndurance
    }

    private var step1Valid: Bool {
        selectedFocus != nil && selectedLevel != nil && selectedDuration > 0 && selectedFrequency > 0
    }

    private var step2Valid: Bool {
        guard let lifts = focusTemplate?.requiredLifts, !lifts.isEmpty else { return false }
        return lifts.allSatisfy { lift in
            guard let val = oneRMValues[lift], !val.isEmpty else { return false }
            return Double(val) != nil
        }
    }

    private var generatorDerivedStateRefreshToken: Int {
        ProgramGeneratorDerivedState.refreshToken(
            selectedFocus: selectedFocus,
            selectedLevel: selectedLevel,
            durationWeeks: selectedDuration,
            sessionsPerWeek: selectedFrequency,
            steeringProfile: steeringProfile,
            carryForwardContext: initialPrefill?.carryForwardContext,
            personalRecords: allPRs
        )
    }

    // MARK: Body

    var body: some View {
        Group {
            if FeatureAccessPolicy.isAccessible(
                .trainingPrograms,
                entitlementState: purchaseManager.entitlementState
            ) {
                NavigationStack {
                    Group {
                        if isGenerating {
                            loadingView
                        } else if let program = generatedProgram, let input = lastInput {
                            ProgramReviewView(
                                program: program,
                                input: input,
                                onStartProgram: { dismiss() },
                                onRegenerate: {
                                    modelContext.delete(program)
                                    generatedProgram = nil
                                    isGenerating = true
                                    Task { @MainActor in
                                        await Task.yield()
                                        generatedProgram = service.regenerateProgram(input: input, context: modelContext)
                                        lastInput = input
                                        isGenerating = false
                                    }
                                }
                            )
                        } else if step == 2 {
                            oneRMView
                        } else {
                            configurationView
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { cancelOrBackButton }
                        ToolbarItem(placement: .principal) {
                            Text(navigationTitle).dsHeadline()
                        }
                    }
                }
                .interactiveDismissDisabled(isGenerating)
                .onAppear { restoreState() }
                .task(id: generatorDerivedStateRefreshToken) {
                    refreshDerivedState()
                }
                .onChange(of: selectedFocus) { _, new in
                    savedFocusRaw = new?.rawValue ?? ""
                    if let f = new {
                        let minFreq = FocusTemplateLibrary.template(for: f).minimumFrequency
                        if selectedFrequency > 0 && selectedFrequency < minFreq {
                            selectedFrequency = 0
                        }
                    }
                }
                .onChange(of: selectedLevel)     { _, new in savedLevelRaw  = new?.rawValue ?? "" }
                .onChange(of: selectedDuration)  { _, new in savedDuration  = new }
                .onChange(of: selectedFrequency) { _, new in savedFrequency = new }
            } else {
                NavigationStack {
                    PremiumGateView(feature: .trainingPrograms)
                }
            }
        }
    }

    private var cancelOrBackButton: some View {
        let isVisible = generatedProgram == nil && !isGenerating
        return Button(step == 2 ? "Back" : "Cancel") {
            if step == 2 { step = 1 } else { dismiss() }
        }
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
    }

    private var navigationTitle: String {
        if isGenerating            { return "Generating..." }
        if generatedProgram != nil { return "Review Program" }
        return step == 1 ? "Configure Program" : "Enter 1RMs"
    }

    // MARK: Configuration Screen

    private var configurationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                focusSection
                levelSection
                durationSection
                frequencySection
                AdaptiveSteeringControlsCard(
                    profile: steeringProfile,
                    title: "Coach Steering",
                    subtitle: "High-level controls only. Big block-shape changes still stay review-driven."
                ) { steeringProfile = $0 }
                if let adaptivePreviewBundle = derivedState.adaptiveExplanationBundle {
                    AdaptiveExplanationCard(
                        bundle: adaptivePreviewBundle,
                        title: "Coach Preview",
                        compact: true
                    )
                }

                Button(action: handleNextTapped) {
                    Text(isCardioFocus ? "Generate Program" : "Next")
                        .dsHeadline()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(step1Valid ? Color.teal : Color(.systemGray4))
                        .foregroundStyle(step1Valid ? .white : Color(.secondaryLabel))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!step1Valid)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    // MARK: Focus Section

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Program Focus")
                .dsHeadline()

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(ProgramFocus.allCases, id: \.self) { focus in
                    focusCard(for: focus)
                }
            }
        }
    }

    private func focusCard(for focus: ProgramFocus) -> some View {
        let name = FocusTemplateLibrary.template(for: focus).displayName
        let isSelected = selectedFocus == focus
        return Button(action: { selectedFocus = focus }) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 8)
                .background(isSelected ? Color.teal : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.teal : Color(.separator), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Level Section

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Experience Level")
                .dsHeadline()

            HStack(spacing: 0) {
                ForEach(ProgramLevel.allCases, id: \.self) { level in
                    let isSelected = selectedLevel == level
                    Button(action: { selectedLevel = level }) {
                        Text(level.rawValue.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))

            if let level = selectedLevel {
                Text(levelDescription(for: level))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func levelDescription(for level: ProgramLevel) -> String {
        switch level {
        case .beginner:     return "Linear Progression — steady weekly increases"
        case .intermediate: return "Undulating Periodization — varies intensity each session"
        case .advanced:     return "Block Periodization — phased training with peaking"
        }
    }

    // MARK: Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Program Duration")
                .dsHeadline()

            HStack(spacing: 0) {
                ForEach([6, 8, 10, 12], id: \.self) { weeks in
                    let isSelected = selectedDuration == weeks
                    Button(action: { selectedDuration = weeks }) {
                        Text("\(weeks) wks")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
        }
    }

    // MARK: Frequency Section

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions Per Week")
                .dsHeadline()

            HStack(spacing: 0) {
                ForEach(2...6, id: \.self) { freq in
                    let isSelected = selectedFrequency == freq
                    let isDisabled = freq < minimumFrequency
                    Button(action: { selectedFrequency = freq }) {
                        Text("\(freq)")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
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

            if minimumFrequency > 2, let focus = selectedFocus {
                Text("\(FocusTemplateLibrary.template(for: focus).displayName) requires at least \(minimumFrequency) sessions/week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 1RM Screen

    private var oneRMView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter your 1 Rep Max for key lifts")
                        .dsHeadline()
                    Text("Pre-filled from your PR history. Edit any value to override.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let lifts = focusTemplate?.requiredLifts {
                    ForEach(lifts, id: \.self) { lift in
                        oneRMRow(for: lift)
                    }
                }

                Button(action: triggerGeneration) {
                    Text("Generate Program")
                        .dsHeadline()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(step2Valid ? Color.teal : Color(.systemGray4))
                        .foregroundStyle(step2Valid ? .white : Color(.secondaryLabel))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!step2Valid)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    private func oneRMRow(for lift: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lift)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                TextField("Enter 1RM", text: Binding(
                    get: { oneRMValues[lift] ?? "" },
                    set: { oneRMValues[lift] = $0 }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)

                Picker("Unit", selection: Binding(
                    get: { oneRMUnits[lift] ?? .lbs },
                    set: { oneRMUnits[lift] = $0 }
                )) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 88)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Loading View

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Building your personalized program...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func handleNextTapped() {
        guard step1Valid else { return }
        if isCardioFocus {
            triggerGeneration()
        } else {
            initializeOneRMs()
            step = 2
        }
    }

    private func restoreState() {
        if selectedFocus == nil, let f = ProgramFocus(rawValue: savedFocusRaw) {
            selectedFocus = f
        }
        if selectedLevel == nil, let l = ProgramLevel(rawValue: savedLevelRaw) {
            selectedLevel = l
        }
        if selectedDuration == 0 && savedDuration > 0 {
            selectedDuration = savedDuration
        }
        if selectedFrequency == 0 && savedFrequency > 0 {
            let minFreq = focusTemplate?.minimumFrequency ?? 2
            if savedFrequency >= minFreq {
                selectedFrequency = savedFrequency
            }
        }
    }

    private func initializeOneRMs() {
        guard let lifts = focusTemplate?.requiredLifts else { return }
        for lift in lifts {
            guard oneRMValues[lift] == nil else { continue }

            guard let bestPR = resolvedGeneratorDerivedState().bestPRByExerciseName[lift] else {
                oneRMUnits[lift] = .lbs
                continue
            }

            oneRMUnits[lift] = bestPR.unit

            switch bestPR.unit {
            case .lbs:
                oneRMValues[lift] = String(Int(bestPR.roundedOneRepMax))
            case .kg:
                let hasDecimal = bestPR.roundedOneRepMax != bestPR.roundedOneRepMax.rounded(.towardZero)
                oneRMValues[lift] = hasDecimal
                    ? String(format: "%.1f", bestPR.roundedOneRepMax)
                    : String(Int(bestPR.roundedOneRepMax))
            }
        }
    }

    private func triggerGeneration() {
        guard let focus = selectedFocus, let level = selectedLevel,
              selectedDuration > 0, selectedFrequency > 0 else { return }

        var oneRMs: [String: (weight: Double, unit: String)] = [:]
        if !isCardioFocus, let lifts = focusTemplate?.requiredLifts {
            for lift in lifts {
                if let valStr = oneRMValues[lift], let val = Double(valStr) {
                    oneRMs[lift] = (weight: val, unit: (oneRMUnits[lift] ?? .lbs).rawValue)
                }
            }
        }

        var input = ProgramGenerationInput(
            focus: focus,
            level: level,
            durationWeeks: selectedDuration,
            sessionsPerWeek: selectedFrequency,
            oneRepMaxes: oneRMs,
            carryForwardContext: initialPrefill?.carryForwardContext,
            steeringProfile: steeringProfile
        )
        let adaptivePreview = resolvedGeneratorDerivedState().adaptivePreview
        input = ProgramGenerationInput(
            focus: input.focus,
            level: input.level,
            durationWeeks: input.durationWeeks,
            sessionsPerWeek: input.sessionsPerWeek,
            oneRepMaxes: input.oneRepMaxes,
            carryForwardContext: input.carryForwardContext,
            stateSnapshotOverride: input.stateSnapshotOverride,
            steeringProfile: input.steeringProfile,
            explanationBundle: adaptivePreview?.explanationBundle
        )

        lastInput = input
        isGenerating = true

        Task { @MainActor in
            await Task.yield()
            let program = service.generateProgram(input: input, context: modelContext)
            isGenerating = false
            generatedProgram = program
        }
    }

    private func refreshDerivedState() {
        derivedState = ProgramGeneratorDerivedState.build(
            selectedFocus: selectedFocus,
            selectedLevel: selectedLevel,
            durationWeeks: selectedDuration,
            sessionsPerWeek: selectedFrequency,
            steeringProfile: steeringProfile,
            carryForwardContext: initialPrefill?.carryForwardContext,
            personalRecords: allPRs,
            fallbackExplanationBundle: initialPrefill?.explanationBundle,
            context: modelContext,
            previous: derivedState
        )
    }

    private func resolvedGeneratorDerivedState() -> ProgramGeneratorDerivedState {
        if derivedState.refreshToken == generatorDerivedStateRefreshToken {
            return derivedState
        }

        return ProgramGeneratorDerivedState.build(
            selectedFocus: selectedFocus,
            selectedLevel: selectedLevel,
            durationWeeks: selectedDuration,
            sessionsPerWeek: selectedFrequency,
            steeringProfile: steeringProfile,
            carryForwardContext: initialPrefill?.carryForwardContext,
            personalRecords: allPRs,
            fallbackExplanationBundle: initialPrefill?.explanationBundle,
            context: modelContext,
            previous: derivedState
        )
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        guard places >= 0 else { return self }
        let scale = pow(10.0, Double(places))
        return (self * scale).rounded() / scale
    }
}
