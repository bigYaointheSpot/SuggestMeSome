//
//  AdaptiveExplainabilityService.swift
//  SuggestMeSome
//
//  Feature 15 Prompt 3 — shared adaptive explanation assembly.
//

import Foundation

struct AdaptiveExplainabilityService {
    func buildProgramExplanation(
        input: ProgramGenerationInput,
        snapshot: TrainingStateSnapshot,
        doseTargetProfile: DoseTargetProfile,
        continuitySnapshot: ProgramBlockContinuitySnapshot? = nil
    ) -> AdaptiveExplanationBundle {
        let template = FocusTemplateLibrary.template(for: input.focus)
        let baseDeload = defaultDeloadInterval(for: input.focus, level: input.level)
        let steering = input.steeringProfile

        var topReasons: [AdaptiveReasonCode] = []
        if snapshot.hasSparseHistory {
            topReasons.append(.sparseHistoryFallback)
        }
        switch snapshot.adherenceTier {
        case .high:
            topReasons.append(.highAdherence)
        case .low:
            topReasons.append(.lowAdherence)
        case .moderate, .sparseHistory:
            break
        }
        if snapshot.shouldBiasRecovery || doseTargetProfile.sessionStressScale < 1.0 {
            topReasons.append(.fatigueProtection)
        }
        if input.carryForwardContext != nil {
            topReasons.append(.continuityCarryForward)
        }
        if continuitySnapshot?.selectedRecommendationStableID != nil {
            topReasons.append(.acceptedContinuityHistory)
        }
        if doseTargetProfile.deloadIntervalOverride != nil {
            topReasons.append(.deloadAdvanced)
        }
        topReasons.append(contentsOf: steeringReasonCodes(for: steering))
        if snapshot.activeProgramInterferenceRisk >= 0.65 {
            topReasons.append(.interferenceGuardrail)
        }

        let adjustments = [
            AdaptiveAdjustment(
                key: "weekly-volume",
                title: "Weekly Volume",
                baseValue: "100%",
                personalizedValue: percentText(doseTargetProfile.weeklyVolumeScale),
                reasonCodes: orderedReasonCodes(
                    doseTargetProfile.weeklyVolumeScale >= 1.01
                    ? [.volumeScaledUp]
                    : doseTargetProfile.weeklyVolumeScale <= 0.99
                        ? [.volumeScaledDown, snapshot.shouldBiasRecovery ? .fatigueProtection : nil].compactMap { $0 }
                        : [.continuityCarryForward]
                ),
                guardrailsApplied: ["\(template.displayName) session identity stays intact."]
            ),
            AdaptiveAdjustment(
                key: "intensity-target",
                title: "Intensity / Effort",
                baseValue: "100% · RIR 0.0",
                personalizedValue: "\(percentText(doseTargetProfile.intensityScale)) · RIR \(signedNumberText(doseTargetProfile.rirOffset))",
                reasonCodes: orderedReasonCodes(
                    doseTargetProfile.intensityScale < 1.0 || doseTargetProfile.rirOffset > 0
                    ? [.intensityScaledDown, .fatigueProtection]
                    : doseTargetProfile.intensityScale > 1.0
                        ? [.intensityScaledUp]
                        : steering.progressionBias == .push ? [.progressionBiasPush] : [.continuityCarryForward]
                ),
                guardrailsApplied: snapshot.shouldBiasRecovery
                    ? ["Recovery caps still win over push steering."]
                    : []
            ),
            AdaptiveAdjustment(
                key: "session-stress",
                title: "Session Stress",
                baseValue: "100%",
                personalizedValue: percentText(doseTargetProfile.sessionStressScale),
                reasonCodes: orderedReasonCodes(
                    doseTargetProfile.sessionStressScale < 1.0
                    ? [.fatigueProtection, .recoveryBiasProtect]
                    : steering.recoveryBias == .trainThrough ? [.recoveryBiasTrainThrough] : [.highAdherence]
                ),
                guardrailsApplied: [
                    "Focus-specific minimum exposures remain in place."
                ]
            ),
            AdaptiveAdjustment(
                key: "deload-cadence",
                title: "Step-Back Timing",
                baseValue: "Every \(baseDeload) working weeks",
                personalizedValue: doseTargetProfile.deloadIntervalOverride.map {
                    "Every \($0) working weeks"
                } ?? "Template default",
                reasonCodes: doseTargetProfile.deloadIntervalOverride == nil
                    ? orderedReasonCodes([.continuityCarryForward])
                    : orderedReasonCodes([.deloadAdvanced, .fatigueProtection]),
                guardrailsApplied: [
                    "Major deload direction changes stay review-gated."
                ]
            ),
            AdaptiveAdjustment(
                key: "anchor-continuity",
                title: "Anchor Continuity",
                baseValue: "Balanced rotation",
                personalizedValue: anchorContinuityText(
                    preserveBias: doseTargetProfile.preserveAnchorBias,
                    steering: steering
                ),
                reasonCodes: orderedReasonCodes(
                    steering.continuityBias == .rotateMore
                    ? [.continuityBiasRotate, .underusedRotation]
                    : [.continuityBiasPreserve, .preferredAnchorPreserved]
                ),
                guardrailsApplied: snapshot.preferredAnchorExerciseNames.isEmpty
                    ? []
                    : ["Recent reliable anchors remain available when they fit the block."]
            ),
        ]

        let protectedConstraints = orderedUniqueStrings([
            "Minimum \(template.minimumFrequency)x/week focus floor is preserved.",
            "Focus-specific exposure priorities remain intact.",
            snapshot.activeProgramInterferenceRisk >= 0.65
                ? "Interference guardrails block overly aggressive overlap with active program demands."
                : nil,
            input.focus == .cardioEndurance
                ? "Endurance intensity distribution stays inside the cardio archetype rules."
                : nil,
        ].compactMap { $0 })

        let carryForwardSources = buildCarryForwardSources(
            carryForwardContext: input.carryForwardContext,
            continuitySnapshot: continuitySnapshot
        )

        return AdaptiveExplanationBundle(
            category: .programGeneration,
            summary: "\(template.displayName) stays the base template, then the engine personalizes dose, recovery margin, and continuity from your recent training signals.",
            topReasons: orderedReasonCodes(topReasons),
            adjustments: adjustments,
            protectedConstraints: protectedConstraints,
            carryForwardSources: carryForwardSources,
            governance: .reviewRequired,
            steeringPreview: steeringPreview(for: steering, governance: .reviewRequired)
        )
    }

    func buildNextBlockExplanation(
        recommendation: MesocycleNextBlockRecommendation,
        input: MesocycleRecommendationInputPayload? = nil,
        continuitySnapshot: ProgramBlockContinuitySnapshot? = nil,
        steeringProfile: AdaptiveSteeringProfile
    ) -> AdaptiveExplanationBundle {
        let targetTemplate = FocusTemplateLibrary.template(for: recommendation.targetFocus)
        let currentFocusText = input?.currentFocus.map {
            FocusTemplateLibrary.template(for: $0).displayName
        } ?? "Current block"
        let carriedForward = recommendation.prefill.preservedExerciseNames

        var topReasons: [AdaptiveReasonCode] = []
        if let input {
            if input.sessionSummary.completedSessions == 0 || input.sessionSummary.missedSessions > 0 {
                topReasons.append(.lowAdherence)
            }
        }
        if !carriedForward.isEmpty {
            topReasons.append(.preferredAnchorPreserved)
        }
        if continuitySnapshot?.selectedRecommendationStableID != nil {
            topReasons.append(.acceptedContinuityHistory)
        }
        if !(continuitySnapshot?.declinedRecommendationStableIDs.isEmpty ?? true) {
            topReasons.append(.declinedContinuityHistory)
        }
        topReasons.append(.continuityCarryForward)
        topReasons.append(contentsOf: steeringReasonCodes(for: steeringProfile))

        let adjustments = [
            AdaptiveAdjustment(
                key: "focus-direction",
                title: "Focus Direction",
                baseValue: currentFocusText,
                personalizedValue: recommendation.targetFocusDisplayName,
                reasonCodes: orderedReasonCodes([
                    recommendation.kind == .pivotFocus ? .continuityCarryForward : nil,
                    recommendation.kind == .rebuildConsistency ? .lowAdherence : nil,
                    recommendation.kind == .repeatFocus ? .acceptedContinuityHistory : nil,
                ].compactMap { $0 }),
                guardrailsApplied: [
                    "Block-level focus changes always stay user-reviewed."
                ]
            ),
            AdaptiveAdjustment(
                key: "level-direction",
                title: "Level Direction",
                baseValue: input?.inferredCurrentLevel.rawValue.capitalized ?? recommendation.suggestedLevel.rawValue.capitalized,
                personalizedValue: recommendation.suggestedLevel.rawValue.capitalized,
                reasonCodes: orderedReasonCodes([
                    recommendation.suggestedLevel == input?.inferredCurrentLevel ? .continuityCarryForward : .lowAdherence
                ]),
                guardrailsApplied: []
            ),
            AdaptiveAdjustment(
                key: "program-style",
                title: "Progression Style",
                baseValue: ProgramGenerationService().progressionModel(
                    for: recommendation.targetFocus,
                    level: recommendation.suggestedLevel
                ).displayName,
                personalizedValue: recommendation.prefill.style?.displayName ?? "Template default",
                reasonCodes: orderedReasonCodes([.continuityCarryForward]),
                guardrailsApplied: [
                    "Progression-model changes stay in the review flow."
                ]
            ),
            AdaptiveAdjustment(
                key: "anchor-carry-forward",
                title: "Carried-Forward Anchors",
                baseValue: "Balanced continuity",
                personalizedValue: carriedForward.isEmpty
                    ? "No preserved anchors"
                    : "\(min(3, carriedForward.count)) familiar anchor\(carriedForward.count == 1 ? "" : "s") retained",
                reasonCodes: orderedReasonCodes(
                    carriedForward.isEmpty ? [.continuityCarryForward] : [.preferredAnchorPreserved]
                ),
                guardrailsApplied: carriedForward.isEmpty
                    ? []
                    : ["Replacing preserved anchors remains a review-required change."]
            ),
        ]

        let protectedConstraints = orderedUniqueStrings([
            "Minimum \(targetTemplate.minimumFrequency)x/week focus floor is preserved.",
            "Next-block changes stay editable before generation.",
            recommendation.requiresExplicitAcceptance
                ? "This recommendation requires explicit confirmation before it becomes a program."
                : nil,
        ].compactMap { $0 })

        let carryForwardSources = recommendation.prefill.valueSources.enumerated().map { index, source in
            AdaptiveCarryForwardSource(
                key: "prefill-source-\(index)",
                title: source.field.rawValue.capitalized,
                detail: source.note
            )
        }

        return AdaptiveExplanationBundle(
            category: .nextBlockRecommendation,
            summary: recommendation.summary,
            topReasons: orderedReasonCodes(topReasons),
            adjustments: adjustments,
            protectedConstraints: protectedConstraints,
            carryForwardSources: carryForwardSources,
            governance: .reviewRequired,
            steeringPreview: steeringPreview(for: steeringProfile, governance: .reviewRequired)
        )
    }

    func buildDailyRecommendationExplanation(
        configuration: SuggestMeSomeSessionConfiguration,
        finalMode: SuggestMeSomeSessionMode,
        adjustedIntensity: Int,
        snapshot: TrainingStateSnapshot,
        dailyProgramContext: DailyProgramContext,
        coachContext: SuggestMeSomeCoachContext?,
        steeringProfile: AdaptiveSteeringProfile,
        blockedLifts: Set<CanonicalLift>,
        overlapCount: Int,
        hasProgramConflict: Bool
    ) -> AdaptiveExplanationBundle {
        var topReasons: [AdaptiveReasonCode] = []
        if snapshot.shouldBiasRecovery || (coachContext?.hasPainOrDiscomfort == true) {
            topReasons.append(.fatigueProtection)
        }
        if dailyProgramContext.shouldSupportActiveProgram {
            topReasons.append(.activeProgramProtection)
        }
        if !dailyProgramContext.missedMovementFamilies.isEmpty {
            topReasons.append(.missedMovementBackfill)
        }
        if !snapshot.preferredAnchorExerciseNames.isEmpty {
            topReasons.append(.preferredAnchorPreserved)
        }
        topReasons.append(contentsOf: steeringReasonCodes(for: steeringProfile))
        if !blockedLifts.isEmpty || hasProgramConflict {
            topReasons.append(.interferenceGuardrail)
        }

        let adjustments = [
            AdaptiveAdjustment(
                key: "session-mode",
                title: "Session Direction",
                baseValue: configuration.mode.title,
                personalizedValue: finalMode.title,
                reasonCodes: orderedReasonCodes(
                    finalMode == configuration.mode
                    ? [.continuityCarryForward]
                    : [.activeProgramProtection, .fatigueProtection]
                ),
                guardrailsApplied: finalMode != configuration.mode
                    ? ["Mode was redirected only where conflict protection required it."]
                    : []
            ),
            AdaptiveAdjustment(
                key: "session-intensity",
                title: "Intensity",
                baseValue: "Intensity \(configuration.intensity)",
                personalizedValue: "Intensity \(adjustedIntensity)",
                reasonCodes: orderedReasonCodes(
                    adjustedIntensity < configuration.intensity
                    ? [.intensityScaledDown, .fatigueProtection]
                    : adjustedIntensity > configuration.intensity
                        ? [.intensityScaledUp]
                        : steeringProfile.progressionBias == .push ? [.progressionBiasPush] : [.continuityCarryForward]
                ),
                guardrailsApplied: [
                    "Interference and recovery caps still override steering."
                ]
            ),
            AdaptiveAdjustment(
                key: "recovery-margin",
                title: "Recovery Margin",
                baseValue: AdaptiveRecoveryBias.balanced.title,
                personalizedValue: steeringProfile.recoveryBias.title,
                reasonCodes: orderedReasonCodes(
                    steeringProfile.recoveryBias == .trainThrough
                    ? [.recoveryBiasTrainThrough]
                    : steeringProfile.recoveryBias == .protectRecovery
                        ? [.recoveryBiasProtect]
                        : [.continuityCarryForward]
                ),
                guardrailsApplied: snapshot.shouldBiasRecovery
                    ? ["High fatigue signals keep recovery protection active."]
                    : []
            ),
            AdaptiveAdjustment(
                key: "continuity-style",
                title: "Continuity Style",
                baseValue: AdaptiveContinuityBias.balanced.title,
                personalizedValue: steeringProfile.continuityBias.title,
                reasonCodes: orderedReasonCodes(
                    steeringProfile.continuityBias == .rotateMore
                    ? [.continuityBiasRotate, .underusedRotation]
                    : steeringProfile.continuityBias == .preserveAnchors
                        ? [.continuityBiasPreserve, .preferredAnchorPreserved]
                        : [.continuityCarryForward]
                ),
                guardrailsApplied: dailyProgramContext.shouldSupportActiveProgram
                    ? ["Next-session interference protection cannot be bypassed."]
                    : []
            ),
        ]

        let protectedConstraints = orderedUniqueStrings([
            !blockedLifts.isEmpty
                ? "Recent hard \(blockedLifts.map(\.displayName).sorted().joined(separator: ", ")) exposure is protected."
                : nil,
            hasProgramConflict || dailyProgramContext.interferenceScore >= 0.70
                ? "Active-program handoff protection stays on."
                : nil,
            overlapCount >= 2
                ? "Recent overlap keeps the session recovery-aware."
                : nil,
            coachContext?.hasPainOrDiscomfort == true
                ? "Pain/discomfort flags override any more aggressive steering."
                : nil,
        ].compactMap { $0 })

        let carryForwardSources = buildDailyCarryForwardSources(
            snapshot: snapshot,
            dailyProgramContext: dailyProgramContext
        )

        let summary: String
        if dailyProgramContext.shouldSupportActiveProgram {
            let nextSession = dailyProgramContext.nextSessionName ?? "your next planned session"
            summary = "Today’s recommendation supports the active program first, then uses steering to shape how hard the supporting work should feel."
            if nextSession.isEmpty == false {
                _ = nextSession
            }
        } else {
            summary = "Today’s recommendation starts from your requested setup, then applies adaptive recovery, continuity, and conflict checks before finalizing the session."
        }

        return AdaptiveExplanationBundle(
            category: .dailyRecommendation,
            summary: summary,
            topReasons: orderedReasonCodes(topReasons),
            adjustments: adjustments,
            protectedConstraints: protectedConstraints,
            carryForwardSources: carryForwardSources,
            governance: .automatic,
            steeringPreview: steeringPreview(for: steeringProfile, governance: .automatic)
        )
    }

    func buildDailyWorkoutExplanation(
        request: SuggestMeSomeGenerationRequest,
        snapshot: TrainingStateSnapshot,
        dailyProgramContext: DailyProgramContext,
        constructionProfile: SessionConstructionProfile,
        selectedExercises: [Exercise],
        appendedCardio: Bool,
        prescribedIntensity: Int
    ) -> AdaptiveExplanationBundle {
        let lowerSelected = Set(selectedExercises.map { $0.name.lowercased() })
        let preferredAnchorCount = snapshot.preferredAnchorExerciseNames.filter {
            lowerSelected.contains($0.lowercased())
        }.count
        let underusedCount = snapshot.underusedExerciseNames.filter {
            lowerSelected.contains($0.lowercased())
        }.count
        let coveredFamilies = Set(selectedExercises.flatMap {
            ProgramExerciseMetadataService.movementPatterns(for: $0.name).map(\.rawValue)
        })
        let coveredBackfillCount = dailyProgramContext.missedMovementFamilies.filter(coveredFamilies.contains).count

        var topReasons: [AdaptiveReasonCode] = []
        if dailyProgramContext.shouldSupportActiveProgram {
            topReasons.append(.activeProgramProtection)
        }
        if coveredBackfillCount > 0 {
            topReasons.append(.missedMovementBackfill)
        }
        if preferredAnchorCount > 0 {
            topReasons.append(.preferredAnchorPreserved)
        }
        if underusedCount > 0 {
            topReasons.append(.underusedRotation)
        }
        topReasons.append(contentsOf: steeringReasonCodes(for: request.steeringProfile))
        if !dailyProgramContext.blockedCanonicalLifts.isEmpty {
            topReasons.append(.interferenceGuardrail)
        }

        let adjustments = [
            AdaptiveAdjustment(
                key: "selected-exercises",
                title: "Session Slots",
                baseValue: "\(constructionProfile.requiredSlots.count) required slots",
                personalizedValue: "\(selectedExercises.count) exercise\(selectedExercises.count == 1 ? "" : "s") selected",
                reasonCodes: orderedReasonCodes([.continuityCarryForward]),
                guardrailsApplied: [
                    "Slot coverage stays deterministic across identical inputs."
                ]
            ),
            AdaptiveAdjustment(
                key: "anchor-selection",
                title: "Anchor Selection",
                baseValue: "Balanced continuity",
                personalizedValue: preferredAnchorCount > 0
                    ? "\(preferredAnchorCount) familiar anchor\(preferredAnchorCount == 1 ? "" : "s") kept"
                    : request.steeringProfile.continuityBias.title,
                reasonCodes: orderedReasonCodes(
                    preferredAnchorCount > 0
                    ? [.preferredAnchorPreserved]
                    : request.steeringProfile.continuityBias == .rotateMore
                        ? [.continuityBiasRotate, .underusedRotation]
                        : [.continuityCarryForward]
                ),
                guardrailsApplied: dailyProgramContext.shouldSupportActiveProgram
                    ? ["Blocked next-session anchors remain protected."]
                    : []
            ),
            AdaptiveAdjustment(
                key: "movement-backfill",
                title: "Program Support",
                baseValue: "No targeted backfill",
                personalizedValue: coveredBackfillCount > 0
                    ? "\(coveredBackfillCount) missed movement family\(coveredBackfillCount == 1 ? "" : "ies") covered"
                    : "No backfill required",
                reasonCodes: orderedReasonCodes(
                    coveredBackfillCount > 0 ? [.missedMovementBackfill] : [.activeProgramProtection]
                ),
                guardrailsApplied: [
                    "Backfill never overrides interference protection."
                ]
            ),
            AdaptiveAdjustment(
                key: "conditioning-append",
                title: "Cardio Finish",
                baseValue: constructionProfile.allowAutomaticCardioAppend ? "Available" : "Off",
                personalizedValue: appendedCardio ? "Appended" : "Skipped",
                reasonCodes: orderedReasonCodes(
                    appendedCardio ? [.cardioDistributionGuardrail] : [.continuityCarryForward]
                ),
                guardrailsApplied: request.goal == .conditioning || request.sessionMode == .conditioning
                    ? ["Conditioning intent stays explicit in the construction profile."]
                    : []
            ),
            AdaptiveAdjustment(
                key: "prescription-style",
                title: "Prescription Style",
                baseValue: "Goal default",
                personalizedValue: "\(displayTitle(for: constructionProfile.prescriptionStyle)) · Intensity \(prescribedIntensity)",
                reasonCodes: orderedReasonCodes(
                    request.steeringProfile.progressionBias == .push
                    ? [.progressionBiasPush]
                    : request.steeringProfile.recoveryBias == .protectRecovery
                        ? [.recoveryBiasProtect]
                        : [.continuityCarryForward]
                ),
                guardrailsApplied: snapshot.shouldBiasRecovery
                    ? ["Recovery guardrails cap prescription aggressiveness."]
                    : []
            ),
        ]

        let protectedConstraints = orderedUniqueStrings([
            !dailyProgramContext.blockedCanonicalLifts.isEmpty
                ? "Blocked next-session lifts were excluded from anchor selection."
                : nil,
            dailyProgramContext.shouldSupportActiveProgram
                ? "Active-program support mode stays on until the next planned handoff is clear."
                : nil,
            "Minimum session-slot coverage stays deterministic.",
        ].compactMap { $0 })

        return AdaptiveExplanationBundle(
            category: .dailySession,
            summary: "The final session keeps the same deterministic slot logic as the recommendation stage, then uses steering only inside the hard recovery and interference guardrails.",
            topReasons: orderedReasonCodes(topReasons),
            adjustments: adjustments,
            protectedConstraints: protectedConstraints,
            carryForwardSources: buildDailyCarryForwardSources(
                snapshot: snapshot,
                dailyProgramContext: dailyProgramContext
            ),
            governance: .automatic,
            steeringPreview: steeringPreview(for: request.steeringProfile, governance: .automatic)
        )
    }

    private func defaultDeloadInterval(for focus: ProgramFocus, level: ProgramLevel) -> Int {
        switch FocusTemplateLibrary.programmingProfile(for: focus).progressionStrategyFamily {
        case .strengthSkill, .mixedStrengthHypertrophy:
            return 4
        case .hypertrophyVolume:
            return 5
        case .balancedTraining:
            return level == .advanced ? 5 : 4
        case .enduranceConditioning:
            return focus == .cardioEndurance ? 3 : 4
        }
    }

    private func buildCarryForwardSources(
        carryForwardContext: ProgramGenerationCarryForwardContext?,
        continuitySnapshot: ProgramBlockContinuitySnapshot?
    ) -> [AdaptiveCarryForwardSource] {
        var sources: [AdaptiveCarryForwardSource] = []

        if let carryForwardContext {
            if !carryForwardContext.preservedExerciseNames.isEmpty {
                sources.append(
                    AdaptiveCarryForwardSource(
                        key: "preserved-exercises",
                        title: "Preserved Exercises",
                        detail: carryForwardContext.preservedExerciseNames.prefix(4).joined(separator: ", ")
                    )
                )
            }
            for (index, source) in carryForwardContext.valueSources.enumerated() {
                sources.append(
                    AdaptiveCarryForwardSource(
                        key: "value-source-\(index)",
                        title: source.field.rawValue.capitalized,
                        detail: source.note
                    )
                )
            }
        }

        if let accepted = continuitySnapshot?.selectedRecommendationSnapshot {
            sources.append(
                AdaptiveCarryForwardSource(
                    key: "accepted-recommendation",
                    title: "Accepted Recommendation",
                    detail: accepted.title
                )
            )
        }

        return sources
    }

    private func buildDailyCarryForwardSources(
        snapshot: TrainingStateSnapshot,
        dailyProgramContext: DailyProgramContext
    ) -> [AdaptiveCarryForwardSource] {
        var sources: [AdaptiveCarryForwardSource] = []

        if dailyProgramContext.shouldSupportActiveProgram {
            sources.append(
                AdaptiveCarryForwardSource(
                    key: "active-program",
                    title: "Active Program",
                    detail: dailyProgramContext.activeProgramName ?? "Current active program"
                )
            )
            if let nextSessionName = dailyProgramContext.nextSessionName {
                sources.append(
                    AdaptiveCarryForwardSource(
                        key: "next-session",
                        title: "Next Planned Session",
                        detail: nextSessionName
                    )
                )
            }
        }

        if !snapshot.preferredAnchorExerciseNames.isEmpty {
            sources.append(
                AdaptiveCarryForwardSource(
                    key: "preferred-anchors",
                    title: "Preferred Anchors",
                    detail: snapshot.preferredAnchorExerciseNames.prefix(4).joined(separator: ", ")
                )
            )
        }

        return sources
    }

    private func steeringPreview(
        for profile: AdaptiveSteeringProfile,
        governance: AdaptiveGovernanceLevel
    ) -> [AdaptiveSteeringPreview] {
        [
            AdaptiveSteeringPreview(
                key: "progression",
                title: "Progression Bias",
                effectText: profile.progressionBias.effectSummary,
                governance: governance
            ),
            AdaptiveSteeringPreview(
                key: "recovery",
                title: "Recovery Bias",
                effectText: profile.recoveryBias.effectSummary,
                governance: governance
            ),
            AdaptiveSteeringPreview(
                key: "continuity",
                title: "Continuity Bias",
                effectText: profile.continuityBias.effectSummary,
                governance: governance
            ),
        ]
    }

    private func steeringReasonCodes(for profile: AdaptiveSteeringProfile) -> [AdaptiveReasonCode] {
        var reasons: [AdaptiveReasonCode] = []
        switch profile.progressionBias {
        case .conservative:
            reasons.append(.progressionBiasConservative)
        case .balanced:
            break
        case .push:
            reasons.append(.progressionBiasPush)
        }
        switch profile.recoveryBias {
        case .protectRecovery:
            reasons.append(.recoveryBiasProtect)
        case .balanced:
            break
        case .trainThrough:
            reasons.append(.recoveryBiasTrainThrough)
        }
        switch profile.continuityBias {
        case .preserveAnchors:
            reasons.append(.continuityBiasPreserve)
        case .balanced:
            break
        case .rotateMore:
            reasons.append(.continuityBiasRotate)
        }
        return orderedReasonCodes(reasons)
    }

    private func anchorContinuityText(
        preserveBias: Double,
        steering: AdaptiveSteeringProfile
    ) -> String {
        if steering.continuityBias == .rotateMore {
            return "Rotate more while respecting active-program protection"
        }
        if preserveBias >= 0.75 || steering.continuityBias == .preserveAnchors {
            return "Preserve anchors when they fit the block"
        }
        return "Balanced continuity"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func signedNumberText(_ value: Double) -> String {
        let formatted = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
        if value > 0 {
            return "+\(formatted)"
        }
        return formatted
    }

    private func orderedReasonCodes(_ values: [AdaptiveReasonCode]) -> [AdaptiveReasonCode] {
        var seen: Set<AdaptiveReasonCode> = []
        var ordered: [AdaptiveReasonCode] = []
        for value in values {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    private func displayTitle(for style: SuggestMeSomePrescriptionStyle) -> String {
        switch style {
        case .strengthTopSetBackoff:
            return "Top Set + Backoff"
        case .strengthStraightSets:
            return "Straight Sets"
        case .hypertrophyDoubleProgression:
            return "Double Progression"
        case .recoveryTechnique:
            return "Recovery Technique"
        case .conditioningIntervals:
            return "Intervals"
        case .cardioSteadyState:
            return "Steady State"
        }
    }
}
