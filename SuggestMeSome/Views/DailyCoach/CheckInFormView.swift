//
//  CheckInFormView.swift
//  SuggestMeSome
//
//  Feature 7 — Daily Coach readiness check-in form.
//  Creates a new DailyCoachCheckIn or updates the existing same-day record.
//

import SwiftUI
import SwiftData

// MARK: - CheckInFormView

struct CheckInFormView: View {

    // MARK: Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: Input

    /// Pass the existing same-day check-in to edit it; nil to create a new one.
    var existingCheckIn: DailyCoachCheckIn?

    // MARK: State

    @State private var sleepQuality: Int = 3
    @State private var soreness: Int = 1
    @State private var energy: Int = 3
    @State private var stress: Int = 2
    @State private var availableTimeMinutes: Int = 60
    @State private var hasPainOrDiscomfort: Bool = false
    @State private var painNotes: String = ""
    @State private var showSavedConfirmation = false

    private let timeOptions = [30, 45, 60, 75, 90, 120]

    // MARK: Init

    init(existingCheckIn: DailyCoachCheckIn? = nil) {
        self.existingCheckIn = existingCheckIn
        if let c = existingCheckIn {
            _sleepQuality = State(initialValue: c.sleepQuality)
            _soreness = State(initialValue: c.soreness)
            _energy = State(initialValue: c.energy)
            _stress = State(initialValue: c.stress)
            _availableTimeMinutes = State(initialValue: c.availableTimeMinutes)
            _hasPainOrDiscomfort = State(initialValue: c.hasPainOrDiscomfort)
            _painNotes = State(initialValue: c.painNotes ?? "")
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                scaleSection(title: "Sleep Quality", systemImage: "moon.fill", value: $sleepQuality)
                scaleSection(title: "Energy", systemImage: "bolt.fill", value: $energy)
                scaleSection(title: "Soreness", systemImage: "figure.walk", value: $soreness)
                scaleSection(title: "Stress", systemImage: "brain", value: $stress)
                availableTimeSection
                painSection
            }
            .navigationTitle(existingCheckIn == nil ? "Check In" : "Edit Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .overlay {
                if showSavedConfirmation {
                    savedConfirmationOverlay
                }
            }
        }
    }

    private var savedConfirmationOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.indigo)
            Text("Checked In")
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(32)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 16)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: - Scale Section

    private func scaleSection(title: String, systemImage: String, value: Binding<Int>) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                RatingChips(value: value)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Available Time Section

    private var availableTimeSection: some View {
        Section("Available Time") {
            Picker("Duration", selection: $availableTimeMinutes) {
                ForEach(timeOptions, id: \.self) { mins in
                    Text("\(mins) min").tag(mins)
                }
            }
        }
    }

    // MARK: - Pain Section

    private var painSection: some View {
        Section("Pain / Discomfort") {
            Toggle("Pain or Discomfort", isOn: $hasPainOrDiscomfort)
            if hasPainOrDiscomfort {
                TextField("Describe (optional)", text: $painNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let clamp = { (v: Int) in max(1, min(5, v)) }
        let today = Calendar.current.startOfDay(for: Date())

        if let existing = existingCheckIn {
            existing.sleepQuality = clamp(sleepQuality)
            existing.soreness = clamp(soreness)
            existing.energy = clamp(energy)
            existing.stress = clamp(stress)
            existing.availableTimeMinutes = availableTimeMinutes
            existing.hasPainOrDiscomfort = hasPainOrDiscomfort
            existing.painNotes = hasPainOrDiscomfort && !painNotes.isEmpty ? painNotes : nil
            existing.updatedAt = Date()
            existing.markSyncUpdated(at: existing.updatedAt)
        } else {
            let checkIn = DailyCoachCheckIn(
                date: today,
                dayStart: today,
                sleepQuality: clamp(sleepQuality),
                soreness: clamp(soreness),
                energy: clamp(energy),
                stress: clamp(stress),
                availableTimeMinutes: availableTimeMinutes,
                hasPainOrDiscomfort: hasPainOrDiscomfort,
                painNotes: hasPainOrDiscomfort && !painNotes.isEmpty ? painNotes : nil
            )
            modelContext.insert(checkIn)
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.25)) {
                showSavedConfirmation = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismiss()
            }
        }
    }
}

// MARK: - RatingChips

/// Five tappable chips for a 1–5 integer rating.
private struct RatingChips: View {
    @Binding var value: Int

    private let labels = ["1", "2", "3", "4", "5"]
    private let colors: [Color] = [.green, .mint, .yellow, .orange, .red]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { rating in
                Button {
                    value = rating
                } label: {
                    Text(labels[rating - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(value == rating ? colors[rating - 1].opacity(0.85) : Color(.tertiarySystemFill))
                        .foregroundStyle(value == rating ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
