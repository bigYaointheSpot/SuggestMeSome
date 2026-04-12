import Foundation

struct ProgramGenerationMovementCoverageHelper {

    func shouldRejectMovementCandidate(
        focus: ProgramFocus,
        sessionName: String,
        candidatePatterns: Set<ProgramMovementPattern>,
        currentSessionPatterns: Set<ProgramMovementPattern>,
        movementTargets: [ProgramMovementPattern: Int],
        weeklyPatternExposure: [ProgramMovementPattern: Int],
        sessionAccessoryPatterns: Set<ProgramMovementPattern>
    ) -> Bool {
        if focus == .fullBody {
            let combined = currentSessionPatterns.union(candidatePatterns)
            let hasLower = combined.contains(.squatKneeDominant) || combined.contains(.hinge)
            let hasPush = combined.contains(.horizontalPush) || combined.contains(.verticalPush)
            let hasPull = combined.contains(.horizontalPull) || combined.contains(.verticalPull)
            if !hasLower && !candidatePatterns.contains(.squatKneeDominant) && !candidatePatterns.contains(.hinge) {
                return true
            }
            if !hasPush && !candidatePatterns.contains(.horizontalPush) && !candidatePatterns.contains(.verticalPush) {
                return true
            }
            if !hasPull && !candidatePatterns.contains(.horizontalPull) && !candidatePatterns.contains(.verticalPull) {
                return true
            }
        }

        if focus == .pushPull {
            let lower = sessionName.lowercased()
            if (lower.contains("push") && candidatePatterns.isDisjoint(with: Set([.horizontalPush, .verticalPush]))) ||
                (lower.contains("pull") && candidatePatterns.isDisjoint(with: Set([.horizontalPull, .verticalPull]))) ||
                ((lower.contains("leg") || lower.contains("lower")) && candidatePatterns.isDisjoint(with: Set([.squatKneeDominant, .hinge, .singleLeg]))) {
                return true
            }
        }

        if focus == .generalFitness || focus == .fullBody || focus == .pushPull {
            let combined = currentSessionPatterns.union(candidatePatterns)
            let unresolvedCriticalPatterns = movementTargets
                .filter { $0.value > 0 }
                .filter { (weeklyPatternExposure[$0.key] ?? 0) < $0.value }
                .filter { sessionAccessoryPatterns.contains($0.key) }
                .map(\.key)

            if !unresolvedCriticalPatterns.isEmpty &&
                unresolvedCriticalPatterns.allSatisfy({ !candidatePatterns.contains($0) }) &&
                combined.contains(.horizontalPush) &&
                combined.contains(.horizontalPull) {
                return true
            }
        }

        return false
    }

    func bodybuildingSessionPriorityMuscles(sessionName: String) -> Set<ProgramVolumeMuscle> {
        let lower = sessionName.lowercased()

        if lower.contains("chest") && lower.contains("tricep") {
            return [.chest, .triceps, .shoulders]
        }
        if lower.contains("back") && lower.contains("biceps") {
            return [.upperBackLats, .biceps, .hamstrings]
        }
        if lower.contains("shoulder") {
            return [.shoulders, .triceps, .upperBackLats]
        }
        if lower.contains("quad") {
            return [.quads, .glutes, .calves]
        }
        if lower.contains("hamstring") || lower.contains("glute") {
            return [.hamstrings, .glutes, .calves]
        }
        if lower.contains("leg") {
            return [.quads, .hamstrings, .glutes, .calves]
        }
        if lower.contains("arm") {
            return [.biceps, .triceps, .shoulders]
        }
        if lower.contains("chest") {
            return [.chest, .shoulders, .triceps]
        }
        if lower.contains("back") {
            return [.upperBackLats, .biceps, .hamstrings]
        }
        return [.chest, .upperBackLats, .quads, .hamstrings, .shoulders]
    }
}
