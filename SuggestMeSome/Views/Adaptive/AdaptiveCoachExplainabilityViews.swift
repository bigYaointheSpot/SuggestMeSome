//
//  AdaptiveCoachExplainabilityViews.swift
//  SuggestMeSome
//
//  Feature 15 Prompt 3 — shared steering and explanation UI.
//

import SwiftUI

struct AdaptiveSteeringControlsCard: View {
    let profile: AdaptiveSteeringProfile
    var title: String = "Coach Steering"
    var subtitle: String? = nil
    let onChange: (AdaptiveSteeringProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.teal)
                    Text(title)
                        .font(.headline)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            steeringAxis(
                label: "Progression",
                selection: Binding(
                    get: { profile.progressionBias },
                    set: { onChange(profileWith(progressionBias: $0)) }
                )
            )
            steeringAxis(
                label: "Recovery",
                selection: Binding(
                    get: { profile.recoveryBias },
                    set: { onChange(profileWith(recoveryBias: $0)) }
                )
            )
            steeringAxis(
                label: "Continuity",
                selection: Binding(
                    get: { profile.continuityBias },
                    set: { onChange(profileWith(continuityBias: $0)) }
                )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func profileWith(progressionBias: AdaptiveProgressionBias? = nil) -> AdaptiveSteeringProfile {
        AdaptiveSteeringProfile(
            progressionBias: progressionBias ?? profile.progressionBias,
            recoveryBias: profile.recoveryBias,
            continuityBias: profile.continuityBias
        )
    }

    private func profileWith(recoveryBias: AdaptiveRecoveryBias? = nil) -> AdaptiveSteeringProfile {
        AdaptiveSteeringProfile(
            progressionBias: profile.progressionBias,
            recoveryBias: recoveryBias ?? profile.recoveryBias,
            continuityBias: profile.continuityBias
        )
    }

    private func profileWith(continuityBias: AdaptiveContinuityBias? = nil) -> AdaptiveSteeringProfile {
        AdaptiveSteeringProfile(
            progressionBias: profile.progressionBias,
            recoveryBias: profile.recoveryBias,
            continuityBias: continuityBias ?? profile.continuityBias
        )
    }

    private func steeringAxis<Selection: Hashable & Identifiable & CaseIterable>(
        label: String,
        selection: Binding<Selection>
    ) -> some View where Selection.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(label, selection: selection) {
                ForEach(Array(Selection.allCases), id: \.id) { option in
                    Text(displayTitle(for: option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func displayTitle<Selection>(for value: Selection) -> String {
        switch value {
        case let progression as AdaptiveProgressionBias:
            return progression.title
        case let recovery as AdaptiveRecoveryBias:
            return recovery.title
        case let continuity as AdaptiveContinuityBias:
            return continuity.title
        default:
            return ""
        }
    }
}

struct AdaptiveExplanationCard: View {
    let bundle: AdaptiveExplanationBundle
    var title: String = "Coach Notes"
    var compact: Bool = false

    private var displayedAdjustments: [AdaptiveAdjustment] {
        compact ? Array(bundle.adjustments.prefix(2)) : bundle.adjustments
    }

    private var displayedCarryForward: [AdaptiveCarryForwardSource] {
        compact ? Array(bundle.carryForwardSources.prefix(1)) : bundle.carryForwardSources
    }

    private var displayedPreview: [AdaptiveSteeringPreview] {
        compact ? Array(bundle.steeringPreview.prefix(1)) : bundle.steeringPreview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(bundle.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                governanceBadge
            }

            if !bundle.topReasons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bundle.topReasons, id: \.rawValue) { reason in
                            Text(reason.shortLabel)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.tertiarySystemBackground))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if !displayedAdjustments.isEmpty {
                sectionLabel("What Changed")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(displayedAdjustments) { adjustment in
                        adjustmentRow(adjustment)
                    }
                }
            }

            if !bundle.protectedConstraints.isEmpty {
                sectionLabel("What Stayed Fixed")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bundle.protectedConstraints, id: \.self) { item in
                        bulletRow(item, icon: "lock.fill", color: .orange)
                    }
                }
            }

            if !displayedCarryForward.isEmpty {
                sectionLabel("Why")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displayedCarryForward) { source in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                                .font(.caption.weight(.semibold))
                            Text(source.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !displayedPreview.isEmpty {
                sectionLabel("Steering")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displayedPreview) { preview in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.title)
                                .font(.caption.weight(.semibold))
                            Text(preview.effectText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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

    private var governanceBadge: some View {
        Text(bundle.governance.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                bundle.governance == .automatic
                    ? Color.green.opacity(0.14)
                    : Color.indigo.opacity(0.14)
            )
            .foregroundStyle(bundle.governance == .automatic ? Color.green : Color.indigo)
            .clipShape(Capsule())
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func adjustmentRow(_ adjustment: AdaptiveAdjustment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(adjustment.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(adjustment.baseValue)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(adjustment.personalizedValue)
                    .font(.caption.weight(.semibold))
            }

            if !adjustment.reasonCodes.isEmpty {
                Text(adjustment.reasonCodes.map(\.shortLabel).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !adjustment.guardrailsApplied.isEmpty {
                Text(adjustment.guardrailsApplied.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func bulletRow(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CoachPresentationSummaryCard: View {
    let copy: CoachPresentationCopy
    var eyebrow: String? = "Coach Take"
    var accent: Color = .teal
    var supportLimit: Int = 2

    private var supportingItems: [String] {
        copy.detailSections.first?.items.prefix(supportLimit).map { $0 } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow, !eyebrow.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.caption2)
                    Text(eyebrow)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                }
                .foregroundStyle(accent)
            }

            if !copy.headline.isEmpty {
                Text(copy.headline)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !copy.action.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "point.forward.to.point.capsulepath")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                    Text(copy.action)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !copy.whyShort.isEmpty {
                Text(copy.whyShort)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !supportingItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(supportingItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(accent.opacity(0.8))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(item)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.20), lineWidth: 0.5)
        )
    }
}
