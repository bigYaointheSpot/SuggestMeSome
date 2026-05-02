import SwiftUI

private let durationPresets = [30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180]

struct DurationPickerView: View {
    let duration: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Duration", systemImage: "clock")
                .dsHeadline()

            let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(durationPresets, id: \.self) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        Text("\(preset)m")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(duration == preset ? Color.blue : Color(.secondarySystemBackground))
                            .foregroundStyle(duration == preset ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private let intensityDescriptions: [Int: String] = [
    1: "Light / High Volume",
    2: "Moderate-Light",
    3: "Moderate",
    4: "Moderate-Heavy",
    5: "Heavy / Low Volume",
]

private func intensityAccentColor(_ level: Int) -> Color {
    switch level {
    case 1: return .green
    case 2: return Color(red: 0.1, green: 0.7, blue: 0.45)
    case 3: return .blue
    case 4: return .orange
    default: return .red
    }
}

struct IntensitySelectorView: View {
    let intensity: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Intensity", systemImage: "bolt.fill")
                .dsHeadline()

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            onSelect(level)
                        }
                    } label: {
                        Text("\(level)")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                intensity == level
                                    ? intensityAccentColor(level)
                                    : Color(.secondarySystemBackground)
                            )
                            .foregroundStyle(intensity == level ? .white : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if let description = intensityDescriptions[intensity] {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .id(intensity)
                    .transition(.opacity)
            }
        }
    }
}
