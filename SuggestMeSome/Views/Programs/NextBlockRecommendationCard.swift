//
//  NextBlockRecommendationCard.swift
//  SuggestMeSome
//
//  Feature 13 — Reusable cards for the ranked next-block recommendation list.
//

import SwiftUI

extension MesocycleNextBlockRecommendation: Identifiable {
    var id: String { stableID }
}

// MARK: - NextBlockRecommendationCard

struct NextBlockRecommendationCard: View {
    enum Style {
        case primary
        case secondary
    }

    let recommendation: MesocycleNextBlockRecommendation
    let style: Style
    var isSelected: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            switch style {
            case .primary:   primaryBody
            case .secondary: secondaryBody
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Primary

    private var primaryBody: some View {
        let coachCopy = CoachPresentationService.nextBlockRecommendation(for: recommendation)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        capsule("Recommended", color: .teal, filled: true)
                        if let governance = recommendation.explanationBundle?.governance {
                            capsule(governance.title, color: DSColor.primaryAction, filled: false)
                        }
                        if let note = fitLabel {
                            capsule(note, color: fitColor, filled: false)
                        }
                    }
                    Text(recommendation.title)
                        .dsHeadline()
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 6) {
                capsule(recommendation.targetFocusDisplayName, color: .teal, filled: false)
                capsule("\(recommendation.suggestedDurationWeeks) wks", color: .secondary, filled: false)
                capsule("\(recommendation.suggestedSessionsPerWeek)×/wk", color: .secondary, filled: false)
                capsule(recommendation.suggestedLevel.rawValue.capitalized, color: .secondary, filled: false)
            }

            CoachPresentationSummaryCard(
                copy: coachCopy,
                eyebrow: "Coach Call",
                accent: .teal,
                supportLimit: 2
            )

            if let explanation = recommendation.explanationBundle, !explanation.topReasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(explanation.topReasons.prefix(3)), id: \.rawValue) { reason in
                            capsule(reason.shortLabel, color: DSColor.primaryAction, filled: false)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            Text("Review and adjust defaults")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.teal)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.teal.opacity(0.10) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.teal.opacity(0.6) : Color(.separator), lineWidth: isSelected ? 1.5 : 0.5)
        )
    }

    // MARK: Secondary

    private var secondaryBody: some View {
        let coachCopy = CoachPresentationService.nextBlockRecommendation(for: recommendation)
        return HStack(alignment: .top, spacing: 10) {
            Text("#\(recommendation.rank)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if !coachCopy.action.isEmpty {
                    Text(coachCopy.action)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                }
                if !coachCopy.whyShort.isEmpty {
                    Text(coachCopy.whyShort)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(coachCopy.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    capsule(recommendation.targetFocusDisplayName, color: .teal, filled: false)
                    capsule("\(recommendation.suggestedDurationWeeks)w · \(recommendation.suggestedSessionsPerWeek)×", color: .secondary, filled: false)
                    if let governance = recommendation.explanationBundle?.governance {
                        capsule(governance.title, color: DSColor.primaryAction, filled: false)
                    }
                    if let fit = fitLabel {
                        capsule(fit, color: fitColor, filled: false)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.teal.opacity(0.08) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.teal.opacity(0.6) : Color(.separator), lineWidth: 0.5)
        )
    }

    // MARK: Helpers

    private var fitLabel: String? {
        switch recommendation.fitScore {
        case 80...:  return "Strong fit"
        case 60..<80: return "Good fit"
        case 40..<60: return "Alt path"
        default:      return nil
        }
    }

    private var fitColor: Color {
        switch recommendation.fitScore {
        case 80...:   return .green
        case 60..<80: return .teal
        case 40..<60: return .orange
        default:      return .secondary
        }
    }

    private func capsule(_ text: String, color: Color, filled: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(filled ? 0.18 : 0.10))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
