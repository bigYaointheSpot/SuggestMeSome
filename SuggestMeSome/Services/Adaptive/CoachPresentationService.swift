import Foundation

struct CoachPresentationDetailSection: Equatable, Identifiable {
    let title: String
    let items: [String]

    var id: String { title }
}

struct CoachPresentationCopy: Equatable {
    let headline: String
    let action: String
    let whyShort: String
    let detailSections: [CoachPresentationDetailSection]
}

enum CoachPresentationService {
    static func dailyPlan(for plan: TodayPlan) -> CoachPresentationCopy {
        let recommendation = plan.recommendation
        let notableChangeItems = plan.changeSummary.changeType == .noChanges
            ? [String]()
            : orderedUniqueNonEmpty([plan.changeSummary.headline] + plan.changeSummary.details)
        let headline = cleaned(recommendation.compactSummary)
        let action = cleaned(recommendation.primarySuggestion.compactText)
        let whyShort = firstUniqueLine(
            from: [
                notableChangeItems.first,
                firstSentence(in: plan.whyToday),
                firstSentence(in: recommendation.expandedDetails),
            ],
            excluding: [headline, action]
        )

        let executionNotes = orderedUniqueNonEmpty([
            recommendation.primarySuggestion.expandedText,
            firstSentence(in: recommendation.expandedDetails),
        ] + recommendation.secondarySuggestions.map(\.expandedText))

        var sections: [CoachPresentationDetailSection] = []
        appendSection("Why this fits", items: [plan.whyToday], to: &sections)
        appendSection(
            "How to run it",
            items: executionNotes,
            to: &sections
        )
        appendSection(
            "What changed",
            items: notableChangeItems,
            to: &sections
        )
        appendSection(
            "Next step",
            items: orderedUniqueNonEmpty([plan.nextStepGuidance.headline] + plan.nextStepGuidance.actions),
            to: &sections
        )

        return CoachPresentationCopy(
            headline: headline,
            action: action,
            whyShort: whyShort,
            detailSections: sections
        )
    }

    static func sessionRecommendation(
        for recommendation: SuggestMeSomeSessionRecommendation
    ) -> CoachPresentationCopy {
        let headline = firstUniqueLine(
            from: [recommendation.summary, recommendation.continuitySummary],
            excluding: []
        )
        let action = firstUniqueLine(
            from: [recommendation.nextActionGuidance, recommendation.rationale],
            excluding: [headline]
        )
        let whyShort = firstUniqueLine(
            from: [
                firstSentence(in: recommendation.continuitySummary),
                firstSentence(in: recommendation.rationale),
                recommendation.reasonChips.first,
            ],
            excluding: [headline, action]
        )

        var sections: [CoachPresentationDetailSection] = []
        appendSection(
            "Why this fits",
            items: limitedSentences(from: recommendation.rationale, limit: 2),
            to: &sections
        )
        appendSection("Continuity", items: [recommendation.continuitySummary], to: &sections)
        appendSection("Next step", items: [recommendation.nextActionGuidance], to: &sections)

        return CoachPresentationCopy(
            headline: headline,
            action: action,
            whyShort: whyShort,
            detailSections: sections
        )
    }

    static func builtSession(
        recommendation: SuggestMeSomeSessionRecommendation,
        workout: GeneratedWorkout
    ) -> CoachPresentationCopy {
        let headline = firstUniqueLine(
            from: [
                workout.adaptationNote,
                workout.explanationBundle?.summary,
                recommendation.summary,
            ],
            excluding: []
        )
        let action: String
        if workout.exercises.isEmpty {
            action = "Adjust the setup and build again."
        } else {
            action = "Start this session when the exercise mix looks right."
        }
        let whyShort = firstUniqueLine(
            from: [
                firstSentence(in: recommendation.nextActionGuidance),
                firstSentence(in: recommendation.continuitySummary),
                workout.explanationBundle?.topReasonLabels.first,
            ],
            excluding: [headline, action]
        )

        var sections: [CoachPresentationDetailSection] = []
        appendSection(
            "Why this build fits",
            items: orderedUniqueNonEmpty([
                workout.explanationBundle?.summary,
                recommendation.continuitySummary,
            ]),
            to: &sections
        )
        appendSection("Next step", items: [recommendation.nextActionGuidance], to: &sections)

        return CoachPresentationCopy(
            headline: headline,
            action: action,
            whyShort: whyShort,
            detailSections: sections
        )
    }

    static func nextBlockRecommendation(
        for recommendation: MesocycleNextBlockRecommendation
    ) -> CoachPresentationCopy {
        let headline = cleaned(recommendation.summary)
        let action = "Run \(recommendation.targetFocusDisplayName) for \(recommendation.suggestedDurationWeeks) weeks at \(recommendation.suggestedSessionsPerWeek)x/week."
        let whyShort = firstUniqueLine(
            from: [
                recommendation.rationale.first,
                recommendation.fitNote,
                recommendation.explanationBundle?.summary,
            ],
            excluding: [headline, action]
        )

        var sections: [CoachPresentationDetailSection] = []
        appendSection(
            "Why this fits",
            items: Array(recommendation.rationale.prefix(2)),
            to: &sections
        )
        appendSection(
            "Block shape",
            items: [
                "\(recommendation.suggestedLevel.rawValue.capitalized) · \(recommendation.suggestedDurationWeeks) weeks · \(recommendation.suggestedSessionsPerWeek)x/week"
            ],
            to: &sections
        )

        return CoachPresentationCopy(
            headline: headline,
            action: action,
            whyShort: whyShort,
            detailSections: sections
        )
    }

    static func longHorizonSummary(
        for summary: LongHorizonAdaptationSummary
    ) -> CoachPresentationCopy {
        let insights = summary.insights.filter { $0.kind != .insufficientData }
        let leadingInsights = Array(insights.prefix(2))
        let headline = cleaned(summary.headline)
        let action = longHorizonAction(for: summary, insights: leadingInsights)
        let whyShort = firstUniqueLine(
            from: leadingInsights.map(\.detail),
            excluding: [headline, action]
        )

        var sections: [CoachPresentationDetailSection] = []
        appendSection(
            "Recent pattern",
            items: leadingInsights.map(\.detail),
            to: &sections
        )

        return CoachPresentationCopy(
            headline: headline,
            action: action,
            whyShort: whyShort,
            detailSections: sections
        )
    }

    private static func longHorizonAction(
        for summary: LongHorizonAdaptationSummary,
        insights: [LongHorizonAdaptationInsight]
    ) -> String {
        guard let lead = insights.first else {
            return "Use the finished block as your baseline for the next one."
        }

        switch lead.kind {
        case .missedSessionPattern:
            return "Lower friction before you try to push the next block harder."
        case .toleratedFrequency:
            return "Keep the next block close to the schedule you have sustained best."
        case .movementContinuity:
            return "Keep the anchors that have stayed productive across blocks."
        case .adherenceTrend:
            return summary.blockCount > 1
                ? "Carry the current rhythm into the next block."
                : "Finish another block before you make big changes."
        case .standaloneInfluence:
            return "Let your next block reflect the extra work you actually keep doing."
        case .insufficientData:
            return "Finish another block before you make big changes."
        }
    }

    private static func appendSection(
        _ title: String,
        items: [String],
        to sections: inout [CoachPresentationDetailSection]
    ) {
        let cleanedItems = orderedUniqueNonEmpty(items)
        guard !cleanedItems.isEmpty else { return }
        sections.append(CoachPresentationDetailSection(title: title, items: cleanedItems))
    }

    private static func firstUniqueLine(
        from candidates: [String?],
        excluding excluded: [String]
    ) -> String {
        let excludedKeys = Set(excluded.map(normalizedKey))
        for candidate in candidates {
            let line = cleaned(candidate)
            guard !line.isEmpty else { continue }
            if !excludedKeys.contains(normalizedKey(line)) {
                return line
            }
        }
        return ""
    }

    private static func limitedSentences(from text: String, limit: Int) -> [String] {
        let sentences = splitIntoSentences(text)
        guard !sentences.isEmpty else { return orderedUniqueNonEmpty([text]) }
        return Array(sentences.prefix(limit))
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        let cleanedText = cleaned(text)
        guard !cleanedText.isEmpty else { return [] }

        var sentences: [String] = []
        var current = ""
        for character in cleanedText {
            current.append(character)
            if ".!?".contains(character) {
                let trimmed = cleaned(current)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        let trailing = cleaned(current)
        if !trailing.isEmpty {
            sentences.append(trailing)
        }

        return orderedUniqueNonEmpty(sentences)
    }

    private static func firstSentence(in text: String?) -> String {
        splitIntoSentences(text ?? "").first ?? cleaned(text)
    }

    private static func orderedUniqueNonEmpty(_ values: [String?]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []

        for value in values {
            let cleanedValue = cleaned(value)
            guard !cleanedValue.isEmpty else { continue }
            let key = normalizedKey(cleanedValue)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(cleanedValue)
        }

        return output
    }

    private static func cleaned(_ text: String?) -> String {
        (text ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
