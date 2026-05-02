//
//  DSListRow.swift
//  SuggestMeSome
//
//  Unified list-row primitive introduced in Feature 22 Prompt 2. Replaces
//  the ad-hoc rows in WorkoutRow, ProgramReviewView, the Collaboration
//  roster, and Settings. Three slots (leading icon, primary/secondary text,
//  trailing accessory) keep visual rhythm consistent across surfaces.
//

import SwiftUI

// MARK: - Trailing accessory

enum DSListRowAccessory {
    case none
    case chevron
    case value(String)
    case badge(text: String, tone: DSBadge.Tone)
    case checkmark(isOn: Bool)
}

// MARK: - DSListRow

struct DSListRow: View {
    let leadingSystemImage: String?
    let leadingTint: Color
    let title: String
    let subtitle: String?
    let accessory: DSListRowAccessory
    let onTap: (() -> Void)?

    init(
        leadingSystemImage: String? = nil,
        leadingTint: Color = DSColor.primaryAction,
        title: String,
        subtitle: String? = nil,
        accessory: DSListRowAccessory = .none,
        onTap: (() -> Void)? = nil
    ) {
        self.leadingSystemImage = leadingSystemImage
        self.leadingTint = leadingTint
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.onTap = onTap
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) { rowContent }
                .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: DSSpacing.m) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(.system(size: DSIcon.s, weight: .semibold))
                    .foregroundStyle(leadingTint)
                    .frame(width: DSIcon.l, height: DSIcon.l)
                    .background(leadingTint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: DSSpacing.s)

            accessoryView
        }
        .padding(.vertical, DSSpacing.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCombinedLabel)
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        case .value(let text):
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        case .badge(let text, let tone):
            DSBadge(text, tone: tone)
        case .checkmark(let isOn):
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DSIcon.m, weight: .semibold))
                .foregroundStyle(isOn ? DSColor.signalPositive : .secondary)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityCombinedLabel: String {
        var parts: [String] = [title]
        if let subtitle { parts.append(subtitle) }
        switch accessory {
        case .none, .chevron:                       break
        case .value(let v):                         parts.append(v)
        case .badge(let text, _):                   parts.append(text)
        case .checkmark(let isOn):                  parts.append(isOn ? "completed" : "incomplete")
        }
        return parts.joined(separator: ", ")
    }
}
