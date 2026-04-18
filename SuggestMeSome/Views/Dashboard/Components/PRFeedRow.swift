//
//  PRFeedRow.swift
//  SuggestMeSome
//
//  Single personal-record feed row.
//

import SwiftUI

struct PRFeedRow: View {
    let pr: PersonalRecord
    let delta: Double?

    private var formattedWeight: String {
        let w = pr.weight
        let num = w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))"
            : String(format: "%.1f", w)
        return "\(num) \(pr.unit.rawValue)"
    }

    private var formattedDelta: String? {
        guard let d = delta, d > 0 else { return nil }
        let num = d.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(d))"
            : String(format: "%.1f", d)
        return "+\(num) \(pr.unit.rawValue)"
    }

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
                .frame(width: 24, height: 24)
                .background(Color.yellow.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(pr.exerciseName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("×\(pr.repCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(pr.dateAchieved, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedWeight)
                    .font(.headline)
                if let deltaStr = formattedDelta {
                    Text(deltaStr)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("First PR")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, DSSpacing.s)
        .padding(.horizontal, DSSpacing.m)
        .background(DSColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.s, style: .continuous))
    }
}
