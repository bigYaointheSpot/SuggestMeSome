//
//  DSField.swift
//  SuggestMeSome
//
//  Form-field primitives introduced in Feature 22 Prompt 2. Wraps the
//  SwiftUI primitives with consistent label/helper/error positioning so
//  Generator, Settings, and Coach surfaces don't reinvent the layout.
//

import SwiftUI

// MARK: - DSTextField

/// Text input with label above, helper text below, optional error message.
/// Mass migration to this wrapper happens in P5/P6.
struct DSTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var helper: String? = nil
    var error: String? = nil
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .background(DSColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous)
                        .stroke(error == nil ? Color.clear : DSColor.signalCritical, lineWidth: 1)
                )

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DSColor.signalCritical)
            } else if let helper {
                Text(helper)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - DSStepperField

struct DSStepperField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var helper: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(value)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            HStack(spacing: DSSpacing.m) {
                Button {
                    let next = max(range.lowerBound, value - step)
                    if next != value { value = next }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: DSIcon.l, height: DSIcon.l)
                }
                .buttonStyle(.bordered)
                .disabled(value <= range.lowerBound)

                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()

                Button {
                    let next = min(range.upperBound, value + step)
                    if next != value { value = next }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: DSIcon.l, height: DSIcon.l)
                }
                .buttonStyle(.bordered)
                .disabled(value >= range.upperBound)
            }

            if let helper {
                Text(helper)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - DSToggleRow

struct DSToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
    }
}
