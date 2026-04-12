import Foundation

struct SyncConflictResolutionPolicy {
    func mergeWorkouts(local: WorkoutSyncDTO, remote: WorkoutSyncDTO) -> WorkoutSyncDTO {
        let winner = chooseScalarWinner(local: local.metadata, remote: remote.metadata) == .local ? local : remote
        let entryMap = mergeByStableID(
            local: local.exerciseEntries,
            remote: remote.exerciseEntries,
            key: { $0.metadata.stableID },
            merge: mergeExerciseEntries
        )

        var merged = winner
        merged.metadata = mergeMetadata(local: local.metadata, remote: remote.metadata)
        merged.exerciseEntries = entryMap.sorted { $0.orderIndex < $1.orderIndex }
        return merged
    }

    func mergeDailyCheckInSameDay(local: DailyCoachCheckInSyncDTO, remote: DailyCoachCheckInSyncDTO) -> DailyCoachCheckInSyncDTO {
        let winner = chooseScalarWinner(local: local.metadata, remote: remote.metadata) == .local ? local : remote
        var merged = winner
        merged.metadata = mergeMetadata(local: local.metadata, remote: remote.metadata)
        return merged
    }

    func mergeAdaptationProposal(local: AdaptationProposalSyncDTO, remote: AdaptationProposalSyncDTO) -> AdaptationProposalSyncDTO {
        let mergedMetadata = mergeMetadata(local: local.metadata, remote: remote.metadata)

        let localStatus = ProposalStatus(rawValue: local.proposalStatusRawValue) ?? .draft
        let remoteStatus = ProposalStatus(rawValue: remote.proposalStatusRawValue) ?? .draft

        let winner: AdaptationProposalSyncDTO
        if local.decidedAt != nil || remote.decidedAt != nil {
            if (local.decidedAt ?? .distantPast) != (remote.decidedAt ?? .distantPast) {
                winner = (local.decidedAt ?? .distantPast) > (remote.decidedAt ?? .distantPast) ? local : remote
            } else {
                winner = statusRank(localStatus) >= statusRank(remoteStatus) ? local : remote
            }
        } else {
            winner = chooseScalarWinner(local: local.metadata, remote: remote.metadata) == .local ? local : remote
        }

        var merged = winner
        merged.metadata = mergedMetadata
        return merged
    }

    func resolveOverlayActivationConflicts(local: [AppliedProgramOverlaySyncDTO], remote: [AppliedProgramOverlaySyncDTO]) -> [AppliedProgramOverlaySyncDTO] {
        let mergedByID = mergeByStableID(
            local: local,
            remote: remote,
            key: { $0.metadata.stableID },
            merge: mergeOverlay
        )

        var overlays = mergedByID
        let sortedIndices = overlays.indices.sorted {
            overlays[$0].appliedAt > overlays[$1].appliedAt
        }

        var seenActivationScope: Set<String> = []
        for index in sortedIndices {
            let status = OverlayStatus(rawValue: overlays[index].overlayStatusRawValue) ?? .active
            guard status == .active else { continue }

            let scope = "\(overlays[index].programRunStableID ?? "none")|\(overlays[index].effectiveWeekStart)|\(overlays[index].effectiveWeekEnd ?? -1)"
            if seenActivationScope.contains(scope) {
                overlays[index].overlayStatusRawValue = OverlayStatus.superseded.rawValue
                overlays[index].metadata.lastModifiedAt = max(overlays[index].metadata.lastModifiedAt, Date())
                overlays[index].metadata.version += 1
            } else {
                seenActivationScope.insert(scope)
            }
        }

        return overlays
    }

    func mergeProgramRunProgress(local: ProgramRunSyncDTO, remote: ProgramRunSyncDTO) -> ProgramRunSyncDTO {
        let winner = chooseScalarWinner(local: local.metadata, remote: remote.metadata) == .local ? local : remote
        var merged = winner
        merged.metadata = mergeMetadata(local: local.metadata, remote: remote.metadata)
        merged.startDate = min(local.startDate, remote.startDate)
        merged.endDate = maxDate(local.endDate, remote.endDate)
        merged.isCompleted = local.isCompleted || remote.isCompleted
        merged.trainingProgramStableID = winner.trainingProgramStableID ?? (winner.metadata.stableID == local.metadata.stableID ? remote.trainingProgramStableID : local.trainingProgramStableID)
        return merged
    }

    private func mergeExerciseEntries(local: ExerciseEntrySyncDTO, remote: ExerciseEntrySyncDTO) -> ExerciseEntrySyncDTO {
        let winner = chooseScalarWinner(local: local.metadata, remote: remote.metadata) == .local ? local : remote
        let mergedSets = mergeByStableID(
            local: local.sets,
            remote: remote.sets,
            key: { $0.metadata.stableID },
            merge: mergeSets
        )

        var merged = winner
        merged.metadata = mergeMetadata(local: local.metadata, remote: remote.metadata)
        merged.sets = mergedSets.sorted { $0.setNumber < $1.setNumber }
        return merged
    }

    private func mergeSets(local: SetEntrySyncDTO, remote: SetEntrySyncDTO) -> SetEntrySyncDTO {
        let winner = chooseScalarWinner(local: local.metadata, remote: remote.metadata) == .local ? local : remote
        var merged = winner
        merged.metadata = mergeMetadata(local: local.metadata, remote: remote.metadata)
        return merged
    }

    private func mergeOverlay(local: AppliedProgramOverlaySyncDTO, remote: AppliedProgramOverlaySyncDTO) -> AppliedProgramOverlaySyncDTO {
        let winner = chooseScalarWinner(local: local.metadata, remote: remote.metadata) == .local ? local : remote
        let mergedAdjustments = mergeByStableID(
            local: local.adjustments,
            remote: remote.adjustments,
            key: { $0.metadata.stableID },
            merge: { lhs, rhs in
                var result = chooseScalarWinner(local: lhs.metadata, remote: rhs.metadata) == .local ? lhs : rhs
                result.metadata = mergeMetadata(local: lhs.metadata, remote: rhs.metadata)
                return result
            }
        )

        var merged = winner
        merged.metadata = mergeMetadata(local: local.metadata, remote: remote.metadata)
        merged.adjustments = mergedAdjustments.sorted { $0.sequence < $1.sequence }
        return merged
    }

    private enum MergeWinner {
        case local
        case remote
    }

    private func chooseScalarWinner(local: SyncRecordMetadataDTO, remote: SyncRecordMetadataDTO) -> MergeWinner {
        if local.lastModifiedAt != remote.lastModifiedAt {
            return local.lastModifiedAt > remote.lastModifiedAt ? .local : .remote
        }
        if local.version != remote.version {
            return local.version > remote.version ? .local : .remote
        }
        return local.stableID >= remote.stableID ? .local : .remote
    }

    private func mergeMetadata(local: SyncRecordMetadataDTO, remote: SyncRecordMetadataDTO) -> SyncRecordMetadataDTO {
        SyncRecordMetadataDTO(
            stableID: local.stableID,
            version: max(local.version, remote.version),
            lastModifiedAt: max(local.lastModifiedAt, remote.lastModifiedAt),
            deletedAt: maxDate(local.deletedAt, remote.deletedAt)
        )
    }

    private func statusRank(_ status: ProposalStatus) -> Int {
        switch status {
        case .superseded: return 8
        case .rejected: return 7
        case .confirmed: return 6
        case .autoApplied: return 5
        case .expired: return 4
        case .pendingUserConfirmation: return 3
        case .pendingAutoApply: return 2
        case .draft: return 1
        }
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?): return max(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }

    private func mergeByStableID<T>(
        local: [T],
        remote: [T],
        key: (T) -> String,
        merge: (T, T) -> T
    ) -> [T] {
        var merged: [String: T] = [:]
        for item in local {
            merged[key(item)] = item
        }
        for item in remote {
            let stableID = key(item)
            if let existing = merged[stableID] {
                merged[stableID] = merge(existing, item)
            } else {
                merged[stableID] = item
            }
        }
        return Array(merged.values)
    }
}
