import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject private var store: FitnessStore
    let sessionId: String

    private var session: WorkoutSession? {
        store.sessions.first { $0.id == sessionId } ?? (store.activeSession?.id == sessionId ? store.activeSession : nil)
    }

    var body: some View {
        Group {
            if let session {
                SessionEditor(session: session)
            } else {
                EmptyState(systemImage: "questionmark.circle", title: "Session Not Found", subtitle: "This session couldn't be loaded.")
            }
        }
        // Re-verifies against the backend every time a session is opened, rather
        // than trusting whatever was cached at launch indefinitely.
        .task { await store.refreshSessions() }
    }
}

struct SessionEditor: View {
    @EnvironmentObject private var store: FitnessStore
    @EnvironmentObject private var router: TabRouter
    let session: WorkoutSession

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pageTint) private var pageTint
    @State private var groups: [ExerciseSetGroup] = []
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var hasUnsavedChanges = false
    @State private var showingCancelConfirm = false
    @State private var isCompleting = false
    /// Completed sessions open read-only — every field/button stays locked until
    /// "Edit" is tapped, and edits only persist via the explicit "Save" button
    /// (no silent autosave of history). In-progress sessions are never locked;
    /// they keep their existing freely-editable, autosaving flow.
    @State private var isLocked: Bool

    init(session: WorkoutSession) {
        self.session = session
        _isLocked = State(initialValue: session.status == .completed)
    }

    private var startDate: Date {
        DateFormatting.date(from: session.captured_at) ?? Date()
    }

    var body: some View {
        List {
            if session.status == .completed {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateFormatting.displayString(from: session.captured_at))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let completedAt = session.completed_at,
                               let duration = DateFormatting.durationString(from: session.captured_at, to: completedAt) {
                                Text(duration)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Badge(text: "Completed", systemImage: "checkmark.circle.fill")
                    }
                }
            } else {
                Section {
                    SessionTimerView(startDate: startDate)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }

            ForEach($groups) { $group in
                Section {
                    ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, _ in
                        SetRow(set: $group.sets[index], index: index, previous: group.previousSets[safe: index], isLocked: isLocked, tracksWeight: group.tracksWeight)
                    }
                    .onDelete(perform: isLocked ? nil : { group.sets.remove(atOffsets: $0) })

                    if !isLocked {
                        Button {
                            let last = group.sets.last
                            let previous = group.previousSets[safe: group.sets.count]
                            group.sets.append(LoggedSet(
                                exerciseId: group.exerciseId,
                                weightKg: group.tracksWeight ? (last?.weightKg ?? previous?.weightKg ?? 0) : 0,
                                reps: last?.reps ?? previous?.reps ?? group.targetReps ?? 0
                            ))
                        } label: {
                            Label("Add Set", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    HStack {
                        Text(group.exerciseName)
                        if let target = group.targetLabel {
                            Spacer()
                            Text(target).font(.caption)
                        }
                    }
                }
            }

            if session.status != .completed {
                Section {
                    Button {
                        save()
                        isCompleting = true
                        Task {
                            let succeeded = await store.completeSession(sessionId: session.id)
                            isCompleting = false
                            if succeeded {
                                router.selection = .session
                            }
                        }
                    } label: {
                        Group {
                            if isCompleting {
                                ProgressView()
                            } else {
                                Text("Complete Workout")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isCompleting)
                    .listRowBackground(pageTint)
                    .foregroundStyle(.white)
                }

                Section {
                    Button(role: .destructive) {
                        showingCancelConfirm = true
                    } label: {
                        Text("Cancel Workout")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isCompleting)
            }
        }
        .dismissesKeyboardOnBackgroundTap()
        .navigationTitle(session.plan_name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.status == .completed {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLocked {
                        Button("Edit") { isLocked = false }
                    } else {
                        Button("Save") {
                            save()
                            isLocked = true
                        }
                        .disabled(!hasUnsavedChanges)
                    }
                }
            }
        }
        .onAppear { rebuildGroups() }
        .onDisappear { flushPendingSave() }
        .onChange(of: groups) { oldValue, _ in
            guard !oldValue.isEmpty, !isLocked else { return }
            hasUnsavedChanges = true
            // Completed-session edits only persist via the explicit Save button
            // above — no debounced autosave of history the way an in-progress
            // session has.
            if session.status != .completed {
                scheduleAutoSave()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Leaving .active (backgrounding, app switcher, quitting) — flush right
            // away rather than waiting out the debounce, so a save in flight has the
            // best chance of finishing before the process is suspended.
            if newPhase != .active { flushPendingSave() }
        }
        .alert(
            "Cancel Workout?",
            isPresented: $showingCancelConfirm
        ) {
            Button("Keep Going", role: .cancel) {}
            Button("Cancel Workout", role: .destructive) {
                store.deleteSession(session)
            }
        } message: {
            Text("All logged sets will be deleted. This can't be undone.")
        }
    }

    private func rebuildGroups() {
        var result: [ExerciseSetGroup] = []

        if let planId = session.plan_id, let plan = store.plans.first(where: { $0.id == planId }) {
            let sortedExercises = plan.exercises.sorted(by: { $0.position < $1.position })
            let currentPlanExerciseIds = Set(sortedExercises.map(\.id))

            // Sets whose plan_exercise_id doesn't resolve against the plan's *current*
            // configuration — typically because the plan was edited (exercise added,
            // removed, or reordered) after this session was logged, and the backend
            // minted fresh plan_exercise ids. The exercise itself may still be in the
            // plan, so these would otherwise be silently dropped instead of falling
            // into the "no longer in plan" leftover bucket below. Claim them by
            // exercise_id instead so editing a plan doesn't retroactively blank out
            // already-logged history.
            let orphanedSets = session.sets.filter { set in
                guard let planExerciseId = set.plan_exercise_id else { return true }
                return !currentPlanExerciseIds.contains(planExerciseId)
            }
            var claimedOrphanIds = Set<String>()

            for planExercise in sortedExercises {
                var matchingSets = session.sets.filter { $0.plan_exercise_id == planExercise.id }
                if matchingSets.isEmpty {
                    let fallback = orphanedSets.filter {
                        $0.exercise_id == planExercise.exercise_id && !claimedOrphanIds.contains($0.id)
                    }
                    matchingSets = fallback
                    claimedOrphanIds.formUnion(fallback.map(\.id))
                }
                let logged = matchingSets
                    .sorted { $0.set_number < $1.set_number }
                    .map { LoggedSet(exerciseId: $0.exercise_id, weightKg: $0.weight_kg, reps: $0.reps) }
                result.append(ExerciseSetGroup(
                    exerciseId: planExercise.exercise_id,
                    planExerciseId: planExercise.id,
                    exerciseName: store.exercises.first(where: { $0.id == planExercise.exercise_id })?.name ?? planExercise.exercise_name,
                    targetSets: planExercise.target_sets,
                    targetReps: planExercise.target_reps,
                    sets: logged,
                    previousSets: previousSets(planExerciseId: planExercise.id, exerciseId: planExercise.exercise_id),
                    tracksWeight: store.exercises.first(where: { $0.id == planExercise.exercise_id })?.tracks_weight ?? true
                ))
            }

            let coveredExerciseIds = Set(sortedExercises.map(\.exercise_id))
            let leftover = session.sets.filter { set in
                guard !claimedOrphanIds.contains(set.id) else { return false }
                if let planExerciseId = set.plan_exercise_id, currentPlanExerciseIds.contains(planExerciseId) { return false }
                return !coveredExerciseIds.contains(set.exercise_id ?? "")
            }
            appendLeftover(leftover, into: &result)
        } else {
            appendLeftover(session.sets, into: &result)
        }

        groups = result
    }

    /// Looks back through completed sessions (most recent first) for the last
    /// time this exercise was logged, so its sets can be shown as a "last time"
    /// reference even before this session has any sets of its own. Prefers
    /// `plan_exercise_id` (ties the lookup to this specific slot in the plan) but
    /// falls back to `exercise_id` — both for exercises logged outside a plan and
    /// for sessions logged before the plan was last edited, whose sets still carry
    /// a now-stale `plan_exercise_id` (the backend mints new ids on plan edits).
    private func previousSets(planExerciseId: String?, exerciseId: String?) -> [PreviousSet] {
        let priorSessions = store.sessions
            .filter { $0.status == .completed && $0.id != session.id }
            .sorted { $0.captured_at > $1.captured_at }

        for candidate in priorSessions {
            var matching: [SessionSet] = []
            if let planExerciseId {
                matching = candidate.sets.filter { $0.plan_exercise_id == planExerciseId }
            }
            if matching.isEmpty, let exerciseId {
                matching = candidate.sets.filter { $0.exercise_id == exerciseId }
            }
            if !matching.isEmpty {
                return matching
                    .sorted { $0.set_number < $1.set_number }
                    .map { PreviousSet(weightKg: $0.weight_kg, reps: $0.reps) }
            }
        }
        return []
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Called on disappear and on leaving the active scene phase — skips the
    /// debounce and saves immediately if there's an edit it hasn't caught yet.
    private func flushPendingSave() {
        autoSaveTask?.cancel()
        guard hasUnsavedChanges else { return }
        save()
    }

    private func appendLeftover(_ sets: [SessionSet], into result: inout [ExerciseSetGroup]) {
        let byExercise = Dictionary(grouping: sets) { $0.exercise_id ?? $0.exercise_name }
        for (_, exerciseSets) in byExercise.sorted(by: { $0.key < $1.key }) {
            guard let first = exerciseSets.first else { continue }
            let logged = exerciseSets.sorted { $0.set_number < $1.set_number }.map { LoggedSet(exerciseId: $0.exercise_id, weightKg: $0.weight_kg, reps: $0.reps) }
            result.append(ExerciseSetGroup(
                exerciseId: first.exercise_id,
                planExerciseId: nil,
                exerciseName: first.exercise_name,
                targetSets: nil,
                targetReps: nil,
                sets: logged,
                previousSets: previousSets(planExerciseId: nil, exerciseId: first.exercise_id),
                tracksWeight: first.exercise_id.flatMap { id in store.exercises.first(where: { $0.id == id })?.tracks_weight } ?? true
            ))
        }
    }

    private func save() {
        hasUnsavedChanges = false
        var inputs: [SessionSetInput] = []
        for group in groups {
            for (index, set) in group.sets.enumerated() {
                inputs.append(SessionSetInput(
                    exercise_id: set.exerciseId,
                    plan_exercise_id: group.planExerciseId,
                    set_number: index + 1,
                    weight_kg: set.weightKg,
                    reps: set.reps
                ))
            }
        }
        store.saveSets(sessionId: session.id, sets: inputs)
    }
}

struct SessionTimerView: View {
    let startDate: Date
    @Environment(\.pageTint) private var pageTint

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1)) { context in
            Text(Self.formatted(context.date.timeIntervalSince(startDate)))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(pageTint)
        }
    }

    private static func formatted(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct SetRow: View {
    @Binding var set: LoggedSet
    let index: Int
    var previous: PreviousSet?
    var isLocked: Bool = false
    var tracksWeight: Bool = true

    private var repsBinding: Binding<Int> {
        Binding(
            get: { set.reps },
            set: { set.reps = min(max($0, 0), 200) }
        )
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { set.weightKg },
            set: { set.weightKg = min(max($0, 0), 500) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Set \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let previous {
                    Spacer()
                    Text(tracksWeight
                        ? "Last: \(previous.reps) × \(String(format: "%.1f", previous.weightKg))kg"
                        : "Last: \(previous.reps) reps")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack {
                Text("Reps")
                Spacer()
                TextField("Reps", value: repsBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .frame(width: 36)
                Stepper("", value: repsBinding)
                    .labelsHidden()
            }
            if tracksWeight {
                HStack {
                    Text("Weight (kg)")
                    Spacer()
                    TextField("kg", value: weightBinding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .frame(width: 50)
                    Stepper("", value: weightBinding, step: 2.5)
                        .labelsHidden()
                }
            }
        }
        .padding(.vertical, 4)
        .disabled(isLocked)
    }
}

struct ExerciseSetGroup: Identifiable, Equatable {
    var id: String { planExerciseId ?? exerciseId ?? exerciseName }
    let exerciseId: String?
    let planExerciseId: String?
    let exerciseName: String
    let targetSets: Int?
    let targetReps: Int?
    var sets: [LoggedSet]
    var previousSets: [PreviousSet] = []
    var tracksWeight: Bool = true

    var targetLabel: String? {
        guard let targetSets, let targetReps else { return nil }
        return "\(targetSets) × \(targetReps) target"
    }
}

struct LoggedSet: Identifiable, Equatable {
    let id = UUID()
    var exerciseId: String?
    var weightKg: Double
    var reps: Int
}

/// A set from the last time this exercise was logged, kept around purely for
/// display/defaulting — not tied to any particular session id.
struct PreviousSet: Equatable {
    var weightKg: Double
    var reps: Int
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    SessionDetailView(sessionId: "preview")
        .environmentObject(FitnessStore())
        .environmentObject(TabRouter())
}
