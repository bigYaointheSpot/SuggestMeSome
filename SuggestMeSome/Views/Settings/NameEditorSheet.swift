//
//  NameEditorSheet.swift
//  SuggestMeSome
//
//  Reusable sheet for single-field name entry — replaces the old inline
//  .alert(…, TextField:) prompts with a Form-based sheet at a medium
//  detent, auto-focused field, and submit-on-return. Used by Manage
//  Exercises for add/rename flows and can fold into other name-only
//  editors as they appear.
//

import SwiftUI

struct NameEditorSheet: View {
    let title: String
    let placeholder: String
    let actionLabel: String
    let subtitle: String?
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        title: String,
        placeholder: String,
        initialValue: String = "",
        actionLabel: String = "Save",
        subtitle: String? = nil,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.actionLabel = actionLabel
        self.subtitle = subtitle
        self._text = State(initialValue: initialValue)
        self.onSave = onSave
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let subtitle {
                    Section { Text(subtitle).foregroundStyle(.secondary) }
                }
                Section {
                    TextField(placeholder, text: $text)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionLabel, action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Raising the FocusState the same tick the sheet appears
            // races the detent animation and intermittently drops the
            // keyboard on iPad and when Reduce Motion is off. A 100ms
            // breather lets the sheet settle before focusing so the
            // keyboard lifts reliably.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                isFocused = true
            }
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
