//
//  AsyncActionButton.swift
//  SuggestMeSome
//
//  Button that awaits an async action, disables itself while running, swaps
//  the label for a ProgressView, and fires a success haptic on completion.
//  Accepts either a ViewBuilder label (rich content) or a plain title
//  string — callers pick whichever fits. External `.buttonStyle(...)`
//  modifiers still apply, so the same component renders as prominent,
//  bordered, borderless, or a custom DSButtonStyle.
//

import SwiftUI

struct AsyncActionButton<Label: View>: View {
    let role: ButtonRole?
    let action: () async -> Void
    @ViewBuilder let label: () -> Label

    @State private var isRunning = false
    @State private var completionCount = 0
    /// Tracked so the in-flight work is cancelled if the containing view
    /// disappears mid-action (user pops the stack before a slow network
    /// call returns). Without this the Task leaks past the view's
    /// lifetime and the haptic fires into the void.
    @State private var runningTask: Task<Void, Never>?

    init(
        role: ButtonRole? = nil,
        action: @escaping () async -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(role: role) {
            guard !isRunning else { return }
            isRunning = true
            // Task inherits MainActor from the enclosing view body, so
            // the post-await state mutations below run on main without
            // a manual MainActor.run hop.
            runningTask = Task { @MainActor in
                await action()
                guard !Task.isCancelled else { return }
                isRunning = false
                completionCount &+= 1
            }
        } label: {
            HStack(spacing: DSSpacing.s) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                label()
            }
        }
        .disabled(isRunning)
        .sensoryFeedback(.success, trigger: completionCount)
        .onDisappear {
            // Cancel the in-flight work AND reset the spinner. If @State
            // survives the disappear/reappear cycle (scroll-recycled cells,
            // dismiss-to-reopen sheets) we'd otherwise come back with the
            // button frozen as disabled-with-spinner, because the Task's
            // cancelled branch bails before flipping isRunning back off.
            runningTask?.cancel()
            runningTask = nil
            isRunning = false
        }
    }
}

extension AsyncActionButton where Label == Text {
    /// Convenience for the common "Accept" / "Retry" / "Save" case where
    /// the label is a single string. Equivalent to passing a `Text(title)`
    /// ViewBuilder. Applies an accessibility label matching the title so
    /// VoiceOver reads the same string the user sees.
    init(
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () async -> Void
    ) {
        self.init(role: role, action: action) {
            Text(title)
        }
    }
}
