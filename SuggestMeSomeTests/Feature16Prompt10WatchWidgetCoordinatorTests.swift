import Foundation
import Testing
@testable import SuggestMeSome

@MainActor
struct Feature16Prompt10WatchWidgetCoordinatorTests {

    @Test func deferredWidgetUpdatesCoalesceIntoOneReload() async {
        var savedSnapshots: [WatchWidgetSnapshot] = []
        var reloadCount = 0
        let coordinator = WatchWidgetRefreshCoordinator(
            initialSnapshot: .empty(updatedAt: referenceDate),
            coalescingDelayNanoseconds: 1_000_000,
            saveSnapshot: { savedSnapshots.append($0) },
            reloadTimelines: { reloadCount += 1 }
        )

        coordinator.apply(
            { WatchWidgetSnapshot.mergingTodayPlan(self.makeTodayPlan(label: "Plan A"), into: $0) },
            urgency: .deferred
        )
        coordinator.apply(
            { WatchWidgetSnapshot.mergingTodayPlan(self.makeTodayPlan(label: "Plan B"), into: $0) },
            urgency: .deferred
        )

        try? await Task.sleep(for: .milliseconds(20))

        #expect(savedSnapshots.count == 1)
        #expect(reloadCount == 1)
        #expect(savedSnapshots.first?.todayPlan?.sessionLabel == "Plan B")
    }

    @Test func immediateWidgetFlushBypassesDeferredWindow() async {
        var savedSnapshots: [WatchWidgetSnapshot] = []
        var reloadCount = 0
        let coordinator = WatchWidgetRefreshCoordinator(
            initialSnapshot: .empty(updatedAt: referenceDate),
            coalescingDelayNanoseconds: 2_000_000_000,
            saveSnapshot: { savedSnapshots.append($0) },
            reloadTimelines: { reloadCount += 1 }
        )

        coordinator.apply(
            { WatchWidgetSnapshot.mergingTodayPlan(self.makeTodayPlan(label: "Queued"), into: $0) },
            urgency: .deferred
        )
        coordinator.apply(
            { WatchWidgetSnapshot.mergingTodayPlan(self.makeTodayPlan(label: "Immediate"), into: $0) },
            urgency: .immediate
        )

        try? await Task.sleep(for: .milliseconds(20))

        #expect(savedSnapshots.count == 1)
        #expect(reloadCount == 1)
        #expect(savedSnapshots.first?.todayPlan?.sessionLabel == "Immediate")
    }

    @Test func unchangedSnapshotSkipsSaveAndReload() {
        let initialSnapshot = WatchWidgetSnapshot.mergingTodayPlan(
            makeTodayPlan(label: "Stable"),
            into: .empty(updatedAt: referenceDate)
        )
        var saveCount = 0
        var reloadCount = 0
        let coordinator = WatchWidgetRefreshCoordinator(
            initialSnapshot: initialSnapshot,
            coalescingDelayNanoseconds: 1_000_000,
            saveSnapshot: { _ in saveCount += 1 },
            reloadTimelines: { reloadCount += 1 }
        )

        coordinator.apply(
            { WatchWidgetSnapshot.mergingTodayPlan(self.makeTodayPlan(label: "Stable"), into: $0) },
            urgency: .immediate
        )

        #expect(saveCount == 0)
        #expect(reloadCount == 0)
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_800_600_000)
    }

    private func makeTodayPlan(label: String) -> WatchTodayPlanSnapshot {
        WatchTodayPlanSnapshot(
            confidence: "High",
            compactSummary: "Stay on the plan.",
            primarySuggestionText: "Train as prescribed.",
            readinessTier: "Strong",
            hasPainFlag: false,
            sessionLabel: label,
            programName: "Strength Block",
            programRunStableID: "run-1",
            programWeekNumber: 2,
            programSessionNumber: 1,
            activeSourceLabels: ["Program"],
            whatChangedToday: "",
            adherenceHeadline: nil,
            adherenceGuidanceType: nil,
            sessionsBehindCount: 0,
            pendingProposalCount: 0,
            generatedAt: referenceDate
        )
    }
}
