//
//  ProgramGenerationMetadata.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation

enum ProgramProgressionModel: String, Codable {
    case linear
    case dup
    case block

    var displayName: String {
        switch self {
        case .linear: return "Linear Progression"
        case .dup: return "Daily Undulating Periodization"
        case .block: return "Block Periodization"
        }
    }
}

enum ProgramProgressionPhase: String, Codable {
    case linearWorking
    case dupHeavy
    case dupModerate
    case dupLight
    case hypertrophy
    case strength
    case peaking
    case deload
}

enum ProgramTargetEffortType: String, Codable {
    case percentage1RM
    case rpe
    case rir
    case none
}
