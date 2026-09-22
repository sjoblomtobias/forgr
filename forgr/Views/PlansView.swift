import SwiftUI
import Charts

struct PlansView: View {
    @EnvironmentObject private var store: FitnessStore
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var showingEditor = false
    @State private var planToDelete: WorkoutPlan?
    @State private var searchText = ""

    private var filteredPlans: [WorkoutPlan] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return store.plans }
        return store.plans.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && !store.hasLoadedOnce {
                    SkeletonList()
                } else if store.plans.isEmpty {
                    EmptyState(
                        systemImage: "list.clipboard",
                        title: "No Plans Yet",
                        subtitle: "Create a workout plan to start scheduling and logging sessions."
                    )
                } else if filteredPlans.isEmpty {
                    EmptyState(
                        systemImage: "magnifyingglass",
                        title: "No Matches",
                        subtitle: "No plans match \u{201C}\(searchText)\u{201D}."
                    )
                } else {
                    List {
                        ForEach(filteredPlans) { plan in
                            NavigationLink(value: plan) {
                                PlanRow(plan: plan)
                            }
                            .swipeActions {
                                // Plain button, not `role: .destructive` — that role makes
                                // List auto-animate the row away on tap, before the
                                // confirmation alert (and the actual delete) happens.
                                Button {
                                    planToDelete = plan
                                } label: { Label("Delete", systemImage: "trash") }
                                    .tint(.red)
                            }
                        }
                        .onMove(perform: move)
                    }
                }
            }
            .navigationTitle("Plans")
            .searchable(text: $searchText, prompt: "Search Plans")
            .navigationDestination(for: WorkoutPlan.self) { plan in
                PlanStatsView(plan: plan)
            }
            .navigationDestination(for: WorkoutSession.self) { session in
                let sessionColor = themeStore.theme.color(for: .session)
                SessionDetailView(sessionId: session.id)
                    .tint(sessionColor)
                    .environment(\.pageTint, sessionColor)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Edit mode gates dragging — leaving it always-on broke tapping
                    // into a plan's stats (NavigationLink taps get swallowed by List's
                    // reorder-handle interaction while edit mode is active). Same fix
                    // as ExercisesView.
                    if !store.plans.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingEditor) {
                PlanEditorView(plan: nil)
            }
            .deleteConfirmation($planToDelete, title: "Delete Plan?") { plan in
                store.deletePlan(plan)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = filteredPlans.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        store.reorderPlans(ids)
    }
}

struct PlanRow: View {
    let plan: WorkoutPlan
    @Environment(\.pageTint) private var pageTint

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.clipboard.fill")
                .foregroundStyle(pageTint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name).font(.subheadline.weight(.medium))
                Text("\(plan.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlanStatsView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss
    let plan: WorkoutPlan
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    /// Reflects renames/edits instantly since `plan` is just the value captured
    /// at navigation time — the store's copy is the one that stays live.
    private var currentPlan: WorkoutPlan {
        store.plans.first(where: { $0.id == plan.id }) ?? plan
    }

    private var completedSessions: [WorkoutSession] {
        store.sessions
            .filter { $0.plan_id == plan.id && $0.status == .completed }
            .sorted { $0.captured_at > $1.captured_at }
    }

    /// Total logged volume (reps × weight, summed across every set) per session,
    /// oldest first, so the trend line reads left-to-right like the exercise chart.
    private var volumePoints: [PlanVolumePoint] {
        completedSessions
            .compactMap { session -> PlanVolumePoint? in
                guard let date = DateFormatting.date(from: session.captured_at) else { return nil }
                let volume = session.sets.reduce(0) { $0 + Double($1.reps) * $1.weight_kg }
                return PlanVolumePoint(day: date, volume: volume)
            }
            .sorted { $0.day < $1.day }
    }

    private var volumeTrend: ExerciseTrend? {
        ExerciseTrend(days: volumePoints.map(\.day), values: volumePoints.map(\.volume), unitLabel: "vol", threshold: 1)
    }

    var body: some View {
        List {
            if completedSessions.isEmpty {
                Section {
                    EmptyState(
                        systemImage: "chart.bar",
                        title: "No Sessions Yet",
                        subtitle: "Completed workouts using this plan will show up here."
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if volumePoints.count >= 2 {
                    Section {
                        PlanVolumeChart(points: volumePoints, trend: volumeTrend)
                    }
                }
                Section {
                    ForEach(completedSessions) { session in
                        NavigationLink(value: session) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(DateFormatting.displayString(from: session.captured_at))
                                        .font(.subheadline.weight(.medium))
                                    if let completedAt = session.completed_at,
                                       let duration = DateFormatting.durationString(from: session.captured_at, to: completedAt) {
                                        Text(duration)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(session.sets.count) sets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Text("Delete Plan")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(currentPlan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEdit = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showingEdit) {
            PlanEditorView(plan: currentPlan)
        }
        .alert("Delete Plan?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deletePlan(plan)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}

struct PlanVolumePoint: Identifiable {
    var id: Date { day }
    let day: Date
    let volume: Double
}

struct PlanVolumeChart: View {
    let points: [PlanVolumePoint]
    let trend: ExerciseTrend?
    @Environment(\.pageTint) private var pageTint

    private static let headroom = 0.75
    private var axisMax: Double { max((points.map(\.volume).max() ?? 0) / Self.headroom, 0.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(pageTint).frame(width: 6, height: 6)
                    Text("Volume")
                }
                HStack(spacing: 4) {
                    if let trend {
                        Image(systemName: trend.direction.systemImage)
                        Text(String(format: "%+.0f/wk", trend.perWeek))
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
                    LineMark(x: .value("Date", point.day), y: .value("Volume", point.volume), series: .value("Series", "Volume"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(pageTint)
                    PointMark(x: .value("Date", point.day), y: .value("Volume", point.volume))
                        .foregroundStyle(pageTint)
                }
                if let trend {
                    ForEach(trend.line, id: \.day) { point in
                        LineMark(x: .value("Date", point.day), y: .value("Volume", point.value), series: .value("Series", "Volume Trend"))
                    }
                    .foregroundStyle(pageTint.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .chartYScale(domain: 0...axisMax)
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
                    if let volume = value.as(Double.self) {
                        AxisValueLabel { Text("\(Int(volume))") }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PlanEditorView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss

    let plan: WorkoutPlan?

    @State private var name: String = ""
    @State private var rows: [PlanExerciseRow] = []
    @State private var showingExercisePicker = false

    init(plan: WorkoutPlan?) {
        self.plan = plan
        _name = State(initialValue: plan?.name ?? "")
        _rows = State(initialValue: plan?.exercises
            .sorted { $0.position < $1.position }
            .map { PlanExerciseRow(exerciseId: $0.exercise_id, exerciseName: $0.exercise_name, sets: $0.target_sets, reps: $0.target_reps) } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Push Day", text: $name)
                } header: {
                    Label("Plan Name", systemImage: "pencil")
                }

                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.exercises.first(where: { $0.id == row.exerciseId })?.name ?? row.exerciseName)
                                .font(.subheadline.weight(.medium))
                            HStack {
                                Text("Sets")
                                Spacer()
                                TextField("Sets", value: clampedBinding($row.sets, in: 1...20), format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(.body, design: .rounded).monospacedDigit())
                                    .frame(width: 20)
                                Stepper("", value: $row.sets, in: 1...20)
                                    .labelsHidden()
                            }
                            HStack {
                                Text("Reps")
                                Spacer()
                                TextField("Reps", value: clampedBinding($row.reps, in: 1...100), format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(.body, design: .rounded).monospacedDigit())
                                    .frame(width: 28)
                                Stepper("", value: $row.reps, in: 1...100)
                                    .labelsHidden()
                            }
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Label("Exercises", systemImage: "list.bullet")
                }
            }
            .navigationTitle(plan == nil ? "New Plan" : "Edit Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView { exercise in
                    rows.append(PlanExerciseRow(exerciseId: exercise.id, exerciseName: exercise.name, sets: 3, reps: 10))
                }
            }
        }
    }

    private func save() {
        let inputs = rows.map { PlanExerciseInput(exercise_id: $0.exerciseId, target_sets: $0.sets, target_reps: $0.reps) }
        if let plan {
            store.updatePlan(id: plan.id, name: name, exercises: inputs)
        } else {
            store.addPlan(name: name, exercises: inputs)
        }
        dismiss()
    }

    private func clampedBinding(_ value: Binding<Int>, in range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}

struct PlanExerciseRow: Identifiable {
    let id = UUID()
    let exerciseId: String
    let exerciseName: String
    var sets: Int
    var reps: Int
}

struct ExercisePickerView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void
    @State private var searchText = ""

    private var filteredExercises: [Exercise] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return store.exercises }
        return store.exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredExercises.isEmpty {
                    EmptyState(systemImage: "magnifyingglass", title: "No Matches", subtitle: "No exercises match \u{201C}\(searchText)\u{201D}.")
                } else {
                    List(filteredExercises) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            Text(exercise.name)
                        }
                    }
                }
            }
            .navigationTitle("Choose Exercise")
            .searchable(text: $searchText, prompt: "Search Exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PlansView()
        .environmentObject(FitnessStore())
        .environmentObject(ThemeStore())
}
