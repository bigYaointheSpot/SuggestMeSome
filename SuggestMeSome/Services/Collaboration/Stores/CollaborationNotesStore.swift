//
//  CollaborationNotesStore.swift
//  SuggestMeSome
//
//  Owns CoachNote state and the unread-filter derivation that drives the
//  Daily Coach badge. Memoized the same way as the other sub-stores so
//  the filter doesn't re-run on every body invocation.
//

import Foundation

@MainActor
@Observable
final class CollaborationNotesStore {
    private(set) var notes: [CoachNote] = []

    @ObservationIgnored private let unreadCoachNotesCache = CachedDerivation<[CoachNote]>()

    init() {}

    // MARK: - State updates

    func apply(notes: [CoachNote]) {
        self.notes = notes
        unreadCoachNotesCache.invalidate()
    }

    func clear() {
        notes = []
        unreadCoachNotesCache.invalidate()
    }

    // MARK: - Derived views

    var unreadCoachNotes: [CoachNote] {
        unreadCoachNotesCache.get {
            notes.filter(\.isUnread)
        }
    }
}
