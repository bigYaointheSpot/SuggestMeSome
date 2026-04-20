//
//  CollaborationAssignmentsStore.swift
//  SuggestMeSome
//
//  Owns ProgramAssignment state plus the trainee-facing inbox derivation.
//  `inboxAssignments` was the heaviest per-render filter call alongside
//  `coachRosterSnapshots`; cache it here so the TrainingPrograms tab
//  badge count doesn't re-filter on every body tick.
//

import Foundation

@MainActor
@Observable
final class CollaborationAssignmentsStore {
    private(set) var assignments: [ProgramAssignment] = []

    @ObservationIgnored private let currentAccountIDProvider: @MainActor () -> UUID?
    @ObservationIgnored private let inboxAssignmentsCache = CachedDerivation<[ProgramAssignment]>()

    init(currentAccountIDProvider: @MainActor @escaping () -> UUID?) {
        self.currentAccountIDProvider = currentAccountIDProvider
    }

    // MARK: - State updates

    func apply(assignments: [ProgramAssignment]) {
        self.assignments = assignments
        inboxAssignmentsCache.invalidate()
    }

    func clear() {
        assignments = []
        inboxAssignmentsCache.invalidate()
    }

    // MARK: - Derived views

    var inboxAssignments: [ProgramAssignment] {
        inboxAssignmentsCache.get {
            assignments.filter { canActOnAssignment($0) }
        }
    }

    // MARK: - Helpers

    func canActOnAssignment(_ assignment: ProgramAssignment) -> Bool {
        assignment.athleteAccountID == currentAccountIDProvider() && assignment.status == .pending
    }
}
