//
//  ProgramSessionRowGroupingService.swift
//  SuggestMeSome
//
//  Shared grouping logic for converting ordered program rows into
//  display/workout draft exercise blocks.
//

import Foundation

struct ProgramSessionRowGroupingService {
    /// Groups ordered rows into contiguous exercise blocks.
    ///
    /// Rows are grouped together when they share the same non-nil
    /// `topBackoffGroupID`, or when they are contiguous rows with the same
    /// exercise name and neither row belongs to a top/backoff group.
    static func group(_ ordered: [ProgramSessionExercise]) -> [[ProgramSessionExercise]] {
        var groups: [[ProgramSessionExercise]] = []

        for exercise in ordered {
            guard let lastGroup = groups.last, let last = lastGroup.last else {
                groups.append([exercise])
                continue
            }

            let shareTopBackoffGroup = {
                guard let a = last.topBackoffGroupID, let b = exercise.topBackoffGroupID else { return false }
                return a == b
            }()
            let contiguousSameExercise =
                last.topBackoffGroupID == nil &&
                exercise.topBackoffGroupID == nil &&
                last.exerciseName == exercise.exerciseName

            if shareTopBackoffGroup || contiguousSameExercise {
                groups[groups.count - 1].append(exercise)
            } else {
                groups.append([exercise])
            }
        }

        return groups
    }
}
