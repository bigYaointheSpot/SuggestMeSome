//
//  CollaborationSharesStore.swift
//  SuggestMeSome
//
//  Owns ProgramShareGrant + ProgressShareCard state. Two separate but
//  closely related sharing surfaces, kept in one store because the
//  coordinator's refresh, cache load, and clear paths treat them as a
//  single domain. No derived views today — the views render each share
//  list directly.
//

import Foundation

@MainActor
@Observable
final class CollaborationSharesStore {
    private(set) var programShares: [ProgramShareGrant] = []
    private(set) var progressShares: [ProgressShareCard] = []

    init() {}

    func apply(
        programShares: [ProgramShareGrant],
        progressShares: [ProgressShareCard]
    ) {
        self.programShares = programShares
        self.progressShares = progressShares
    }

    func clear() {
        programShares = []
        progressShares = []
    }
}
