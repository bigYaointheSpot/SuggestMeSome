import SwiftUI

@MainActor
enum DeferredNavigationService {
    static func launchAfterSheetDismissIfNeeded(
        hasPendingDestination: Bool,
        launch: @escaping @MainActor () -> Void
    ) {
        guard hasPendingDestination else { return }
        Task { @MainActor in
            await Task.yield()
            launch()
        }
    }
}
