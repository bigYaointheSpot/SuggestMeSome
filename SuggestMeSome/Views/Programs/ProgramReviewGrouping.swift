//
//  ProgramReviewGrouping.swift
//  SuggestMeSome
//
//  Created by Codex on 4/7/26.
//

import Foundation

struct ProgramReviewExerciseGroup: Identifiable {
    let id: UUID
    let workingSet: ProgramSessionExercise
    let warmupSets: [ProgramSessionExercise]
}

enum ProgramReviewGrouping {
    static func groupedExercises(from exercises: [ProgramSessionExercise]) -> [ProgramReviewExerciseGroup] {
        var groups: [ProgramReviewExerciseGroup] = []
        var pendingWarmups: [ProgramSessionExercise] = []

        for ex in exercises {
            if ex.isWarmup {
                pendingWarmups.append(ex)
            } else {
                let matching = pendingWarmups.filter { $0.exerciseName == ex.exerciseName }
                let unmatched = pendingWarmups.filter { $0.exerciseName != ex.exerciseName }
                for warmup in unmatched {
                    groups.append(ProgramReviewExerciseGroup(id: warmup.id, workingSet: warmup, warmupSets: []))
                }
                groups.append(ProgramReviewExerciseGroup(id: ex.id, workingSet: ex, warmupSets: matching))
                pendingWarmups = []
            }
        }

        for warmup in pendingWarmups {
            groups.append(ProgramReviewExerciseGroup(id: warmup.id, workingSet: warmup, warmupSets: []))
        }
        return groups
    }
}
