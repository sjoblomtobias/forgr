import SwiftUI

struct PlansView: View {
    @EnvironmentObject private var store: FitnessStore
    @State private var showingEditor = false
    @State private var editingPlan: WorkoutPlan?
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
                            Button {
                                editingPlan = plan
                            } label: {
                                PlanRow(plan: plan)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    planToDelete = plan
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plans")
            .searchable(text: $searchText, prompt: "Search Plans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingEditor) {
                PlanEditorView(plan: nil)
            }
            .sheet(item: $editingPlan) { plan in
                PlanEditorView(plan: plan)
            }
            .deleteConfirmation($planToDelete, title: "Delete Plan?") { plan in
                store.deletePlan(plan)
            }
        }
    }
}

struct PlanRow: View {
    let plan: WorkoutPlan
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.clipboard.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name).font(.subheadline.weight(.medium))
                Text("\(plan.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "pencil.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
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
                Section("Plan Name") {
                    TextField("e.g. Push Day", text: $name)
                }

                Section("Exercises") {
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
                                    .foregroundStyle(Color.accentColor)
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
                                    .foregroundStyle(Color.accentColor)
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
                }
            }
            .navigationTitle(plan == nil ? "New Plan" : "Edit Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || rows.isEmpty)
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
    PlansView().environmentObject(FitnessStore())
}
