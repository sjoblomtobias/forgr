import SwiftUI

struct MeasurementsView: View {
    @EnvironmentObject private var store: FitnessStore
    @State private var showingAdd = false

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoadedOnce {
                SkeletonList()
            } else if store.measurements.isEmpty {
                EmptyState(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "No Measurements Yet",
                    subtitle: "Log your weight and body fat to track progress over time."
                )
            } else {
                List {
                    ForEach(store.measurements) { measurement in
                        NavigationLink(value: measurement) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(String(format: "%.1f", measurement.weight_kg)) kg")
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    Text(DateFormatting.displayString(from: measurement.created_at))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let bodyFat = measurement.body_fat_percent {
                                    Badge(text: "\(String(format: "%.1f", bodyFat))%", systemImage: "percent")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Measurements")
        .navigationDestination(for: Measurement.self) { measurement in
            MeasurementDetailView(measurement: measurement)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            MeasurementFormView(measurement: nil)
        }
    }
}

struct MeasurementFormView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss
    let measurement: Measurement?

    @State private var weight: String
    @State private var bodyFat: String
    @State private var note: String
    @FocusState private var isFocused: Bool

    init(measurement: Measurement?) {
        self.measurement = measurement
        _weight = State(initialValue: measurement.map { String($0.weight_kg) } ?? "")
        _bodyFat = State(initialValue: measurement?.body_fat_percent.map { String($0) } ?? "")
        _note = State(initialValue: measurement?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    TextField("kg", text: $weight)
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                }
                Section("Body Fat (optional)") {
                    TextField("%", text: $bodyFat)
                        .keyboardType(.decimalPad)
                }
                Section("Note (optional)") {
                    TextField("Note", text: $note)
                }
            }
            .navigationTitle(measurement == nil ? "New Measurement" : "Edit Measurement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(measurement == nil ? "Add" : "Save") { save() }
                        .disabled(parseDecimal(weight) == nil)
                }
            }
            .onAppear { isFocused = true }
        }
    }

    /// Accepts both "70.5" and "70,5" — the decimal-pad keyboard shows a comma
    /// separator on many locales, but `Double.init?(String)` only accepts a period.
    private func parseDecimal(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        guard let weightKg = parseDecimal(weight) else { return }
        let bodyFatValue = parseDecimal(bodyFat)
        let noteValue = note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
        if let measurement {
            store.updateMeasurement(id: measurement.id, weightKg: weightKg, bodyFatPercent: bodyFatValue, note: noteValue)
        } else {
            store.addMeasurement(weightKg: weightKg, bodyFatPercent: bodyFatValue, note: noteValue)
        }
        dismiss()
    }
}

struct MeasurementDetailView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss
    let measurement: Measurement
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    /// Reflects edits instantly since `measurement` is just the value captured
    /// at navigation time — the store's copy is the one that stays live.
    private var current: Measurement {
        store.measurements.first(where: { $0.id == measurement.id }) ?? measurement
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Weight")
                    Spacer()
                    Text("\(String(format: "%.1f", current.weight_kg)) kg")
                        .foregroundStyle(.secondary)
                }
                if let bodyFat = current.body_fat_percent {
                    HStack {
                        Text("Body Fat")
                        Spacer()
                        Text("\(String(format: "%.1f", bodyFat))%")
                            .foregroundStyle(.secondary)
                    }
                }
                if let note = current.note, !note.isEmpty {
                    HStack(alignment: .top) {
                        Text("Note")
                        Spacer()
                        Text(note)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                HStack {
                    Text("Logged")
                    Spacer()
                    Text(DateFormatting.displayString(from: current.created_at))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Text("Delete Measurement")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("\(String(format: "%.1f", current.weight_kg)) kg")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEdit = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showingEdit) {
            MeasurementFormView(measurement: current)
        }
        .alert("Delete Measurement?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteMeasurement(measurement)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}

#Preview {
    NavigationStack { MeasurementsView() }.environmentObject(FitnessStore())
}
