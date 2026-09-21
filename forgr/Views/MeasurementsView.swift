import SwiftUI
import Charts

struct MeasurementsView: View {
    @EnvironmentObject private var store: FitnessStore
    @State private var showingAdd = false

    /// Oldest first, for the trend chart — the row list below stays newest-first.
    private var weightPoints: [WeightPoint] {
        store.measurements
            .compactMap { measurement -> WeightPoint? in
                guard let date = DateFormatting.date(from: measurement.created_at) else { return nil }
                return WeightPoint(day: date, weight: measurement.weight_kg)
            }
            .sorted { $0.day < $1.day }
    }

    private var weightTrend: ExerciseTrend? {
        ExerciseTrend(days: weightPoints.map(\.day), values: weightPoints.map(\.weight), unitLabel: "kg", threshold: 0.1)
    }

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
                    if weightPoints.count >= 2 {
                        Section {
                            MeasurementTrendChart(points: weightPoints, trend: weightTrend)
                        }
                    }
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

/// The detailed counterpart to the Dashboard's `WeightSparkline` — same data,
/// with axis labels and a trend badge. Y-axis is zoomed to the data's own range
/// (not from 0) since body weight only varies a few kg — starting at 0 would
/// flatten the trend into an unreadable line hugging the top of the chart.
struct MeasurementTrendChart: View {
    let points: [WeightPoint]
    let trend: ExerciseTrend?
    @Environment(\.pageTint) private var pageTint

    private var weightRange: ClosedRange<Double> {
        let weights = points.map(\.weight)
        guard let minW = weights.min(), let maxW = weights.max() else { return 0...1 }
        guard minW != maxW else { return (minW - 1)...(maxW + 1) }
        let pad = (maxW - minW) * 0.15
        return (minW - pad)...(maxW + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(pageTint).frame(width: 6, height: 6)
                    Text("Weight")
                }
                HStack(spacing: 4) {
                    if let trend {
                        Image(systemName: trend.direction.systemImage)
                        Text(String(format: "%+.1f kg/wk", trend.perWeek))
                    } else {
                        Text("Not enough data")
                    }
                }
                .foregroundStyle(trend?.direction.color ?? .secondary)
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.day), y: .value("Weight", point.weight), series: .value("Series", "Weight"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(pageTint)
                    PointMark(x: .value("Date", point.day), y: .value("Weight", point.weight))
                        .foregroundStyle(pageTint)
                }
                if let trend {
                    ForEach(trend.line, id: \.day) { point in
                        LineMark(x: .value("Date", point.day), y: .value("Weight", point.value), series: .value("Series", "Weight Trend"))
                    }
                    .foregroundStyle(pageTint.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .chartYScale(domain: weightRange)
            .frame(height: 160)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    if let kg = value.as(Double.self) {
                        AxisValueLabel { Text("\(Int(kg))kg") }
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
                Section {
                    TextField("kg", text: $weight)
                        .keyboardType(.decimalPad)
                        .focused($isFocused)
                } header: {
                    Label("Weight", systemImage: "scalemass.fill")
                }
                Section {
                    TextField("%", text: $bodyFat)
                        .keyboardType(.decimalPad)
                } header: {
                    Label("Body Fat (optional)", systemImage: "percent")
                }
                Section {
                    TextField("Note", text: $note)
                } header: {
                    Label("Note (optional)", systemImage: "note.text")
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
    NavigationStack {
        MeasurementsView()
            .navigationDestination(for: Measurement.self) { measurement in
                MeasurementDetailView(measurement: measurement)
            }
    }
    .environmentObject(FitnessStore())
}
