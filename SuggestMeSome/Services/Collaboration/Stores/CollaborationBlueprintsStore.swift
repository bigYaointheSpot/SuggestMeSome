//
//  CollaborationBlueprintsStore.swift
//  SuggestMeSome
//
//  Owns SavedProgramBlueprint state. No derived views today — the
//  Training Programs tab renders `blueprints` as a plain list. Isolating
//  it now lets tests exercise blueprint state in isolation and gives
//  future coach-facing features (blueprint templates, tagging) a natural
//  home without growing the coordinator further.
//

import Foundation

@MainActor
@Observable
final class CollaborationBlueprintsStore {
    private(set) var blueprints: [SavedProgramBlueprint] = []

    init() {}

    func apply(blueprints: [SavedProgramBlueprint]) {
        self.blueprints = blueprints
    }

    func clear() {
        blueprints = []
    }
}
