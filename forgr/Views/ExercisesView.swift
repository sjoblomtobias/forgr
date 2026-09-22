import SwiftUI
import Charts

struct ExercisesView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.pageTint) private var pageTint
    @State private var showingAdd = false
    @State private var showingManageGroups = false
    @State private var searchText = ""
    @State private var collapsedSectionIds: Set<String> = []

    /// Same key `ManageExerciseGroupsView` writes when its "Default" row gets
    /// dragged to a new spot — reading it here keeps this screen's section order
    /// in sync with whatever order was chosen there.
    @AppStorage("defaultGroupRowIndex") private var defaultGroupIndex: Int = .max

    private struct ExerciseSection: Identifiable {
        var id: String { group?.id ?? "ungrouped" }
        let group: ExerciseGroup?
        let exercises: [Exercise]
    }

    /// Groups (sorted by `position`) each get a section of their exercises (also sorted
    /// by `position`); a "Default" section is spliced in wherever it was last dragged to
    /// in Manage Groups, shown only when it has members (or there are no groups at all,
    /// so the list still renders something). While searching, a section whose group name
    /// matches keeps all its exercises; otherwise only its individually-matching exercises
    /// survive, and a section left with none is dropped.
    private var sections: [ExerciseSection] {
        let byGroup = Dictionary(grouping: store.exercises, by: \.group_id)
        var result = store.exerciseGroups
            .sorted { $0.position < $1.position }
            .map { group in
                ExerciseSection(group: group, exercises: (byGroup[group.id] ?? []).sorted { $0.position < $1.position })
            }
        let ungrouped = (byGroup[nil] ?? []).sorted { $0.position < $1.position }
        if !ungrouped.isEmpty || result.isEmpty {
            let insertIndex = min(max(defaultGroupIndex, 0), result.count)
            result.insert(ExerciseSection(group: nil, exercises: ungrouped), at: insertIndex)
        }
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return result }
        return result.compactMap { section in
            if let groupName = section.group?.name, groupName.localizedCaseInsensitiveContains(searchText) {
                return section.exercises.isEmpty ? nil : section
            }
            let matches = section.exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            return matches.isEmpty ? nil : ExerciseSection(group: section.group, exercises: matches)
        }
    }

    /// Sections always render expanded while actively searching, so a match never
    /// hides behind a collapsed group.
    private func isCollapsed(_ section: ExerciseSection) -> Bool {
        guard searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return collapsedSectionIds.contains(section.id)
    }

    private func toggleCollapsed(_ section: ExerciseSection) {
        if collapsedSectionIds.contains(section.id) {
            collapsedSectionIds.remove(section.id)
        } else {
            collapsedSectionIds.insert(section.id)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && !store.hasLoadedOnce {
                    SkeletonList()
                } else if store.exercises.isEmpty {
                    EmptyState(
                        systemImage: "figure.strengthtraining.traditional",
                        title: "No Exercises Yet",
                        subtitle: "Add exercises to your catalog to build workout plans."
                    )
                } else if sections.isEmpty {
                    EmptyState(
                        systemImage: "magnifyingglass",
                        title: "No Matches",
                        subtitle: "No exercises match \u{201C}\(searchText)\u{201D}."
                    )
                } else {
                    List {
                        ForEach(sections) { section in
                            Section {
                                if !isCollapsed(section) {
                                    ForEach(section.exercises) { exercise in
                                        NavigationLink(value: exercise) {
                                            HStack(spacing: 12) {
                                                Image(systemName: "figure.strengthtraining.traditional")
                                                    .foregroundStyle(pageTint)
                                                    .frame(width: 22)
                                                Text(exercise.name)
                                            }
                                        }
                                        // Drag-and-drop between Sections of the same List turned
                                        // out to be unreliable in practice (drop kept bouncing
                                        // back even hit dead-on) even in isolation from .onMove —
                                        // a long-press menu is a fully reliable substitute.
                                        .contextMenu {
                                            if !store.exerciseGroups.isEmpty {
                                                Menu("Move to Group") {
                                                    if exercise.group_id != nil {
                                                        Button("Default") { moveExercise(exercise, toGroupId: nil) }
                                                    }
                                                    ForEach(store.exerciseGroups.sorted { $0.position < $1.position }) { group in
                                                        if group.id != exercise.group_id {
                                                            Button(group.name) { moveExercise(exercise, toGroupId: group.id) }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .onMove { offsets, destination in move(in: section, from: offsets, to: destination) }
                                }
                            } header: {
                                if !store.exerciseGroups.isEmpty {
                                    Button {
                                        withAnimation { toggleCollapsed(section) }
                                    } label: {
                                        HStack {
                                            Text(section.group?.name ?? "Default")
                                            Spacer()
                                            Image(systemName: isCollapsed(section) ? "chevron.right" : "chevron.down")
                                                .font(.caption.weight(.semibold))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exercises")
            .searchable(text: $searchText, prompt: "Search Exercises")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseHistoryView(exercise: exercise)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Edit mode gates dragging — leaving it always-on broke tapping
                    // into an exercise's detail (NavigationLink taps get swallowed by
                    // List's reorder-handle interaction while edit mode is active).
                    if !store.exercises.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingManageGroups = true } label: { Image(systemName: "square.stack.3d.up") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                ExerciseFormView(exercise: nil)
            }
            .sheet(isPresented: $showingManageGroups) {
                ManageExerciseGroupsView()
            }
        }
    }

    private func move(in section: ExerciseSection, from source: IndexSet, to destination: Int) {
        var ids = section.exercises.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        store.reorderExercises(ids)
    }

    /// Re-parents an exercise into a different group (position within the new group
    /// is left to the server, same as `addExercise`/`reorderExercises`).
    private func moveExercise(_ exercise: Exercise, toGroupId groupId: String?) {
        guard exercise.group_id != groupId else { return }
        store.updateExercise(id: exercise.id, name: exercise.name, groupId: groupId)
    }
}

struct ManageExerciseGroupsView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    @State private var editingGroup: ExerciseGroup?
    @State private var pendingDelete: ExerciseGroup?

    /// Where the synthetic "Default" row sits among the real groups, as an index
    /// into the combined displayed order. Not a server concept — `ExerciseGroup.position`
    /// only orders real groups against each other — so this is a purely local display
    /// preference, persisted on-device. Defaults to "last".
    @AppStorage("defaultGroupRowIndex") private var defaultGroupIndex: Int = .max

    private var sortedGroups: [ExerciseGroup] { store.exerciseGroups.sorted { $0.position < $1.position } }

    private enum GroupRow: Identifiable {
        case real(ExerciseGroup)
        case defaultGroup

        var id: String {
            switch self {
            case .real(let group): group.id
            case .defaultGroup: "default"
            }
        }
    }

    /// Real groups in `position` order with the "Default" row spliced in wherever
    /// it was last dragged to (clamped in case groups were added/removed since).
    private var rows: [GroupRow] {
        var result = sortedGroups.map { GroupRow.real($0) }
        result.insert(.defaultGroup, at: min(max(defaultGroupIndex, 0), result.count))
        return result
    }

    private var defaultGroupCount: Int {
        store.exercises.filter { $0.group_id == nil }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        switch row {
                        case .real(let group):
                            // Not a Button — with edit mode always on for dragging, a row
                            // tap can't reliably double as "open rename" (this is exactly
                            // what broke NavigationLink taps on the Exercises screen), so
                            // rename/delete both live in the long-press menu instead.
                            HStack {
                                Text(group.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(store.exercises.filter { $0.group_id == group.id }.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button { editingGroup = group } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { pendingDelete = group } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions {
                                // Plain button, not `role: .destructive` — that role makes
                                // List auto-animate the row away on tap, before the
                                // confirmation alert (and the actual delete) happens.
                                Button { pendingDelete = group } label: { Label("Delete", systemImage: "trash") }
                                    .tint(.red)
                            }
                        case .defaultGroup:
                            // No name to edit and nothing to delete — it's not a real
                            // group, just wherever exercises with no group_id land.
                            HStack {
                                Text("Default")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(defaultGroupCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove(perform: moveRows)
                } footer: {
                    if sortedGroups.isEmpty {
                        Text("Create groups like \"Push\" or \"Legs\" to organize your exercise list. Drag to reorder, long-press to rename.")
                    } else {
                        Text("Drag to reorder, long-press to rename.")
                    }
                }
            }
            // Reorder handles are always on — dragging is the only way to reorder,
            // no separate Edit mode to toggle into first. Rename/delete moved off the
            // row tap and into the long-press menu (see .contextMenu above) so this
            // doesn't repeat the NavigationLink-tap-swallowing bug from Exercises.
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Exercise Groups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                ExerciseGroupFormView(group: nil)
            }
            .sheet(item: $editingGroup) { group in
                ExerciseGroupFormView(group: group)
            }
            .deleteConfirmation(
                $pendingDelete, title: "Delete Group?",
                message: "Exercises in this group will become ungrouped."
            ) { group in
                store.deleteExerciseGroup(group)
            }
        }
    }

    private func moveRows(from source: IndexSet, to destination: Int) {
        var reordered = rows
        reordered.move(fromOffsets: source, toOffset: destination)

        if let index = reordered.firstIndex(where: { if case .defaultGroup = $0 { true } else { false } }) {
            defaultGroupIndex = index
        }

        let realIds = reordered.compactMap { row -> String? in
            if case .real(let group) = row { return group.id }
            return nil
        }
        store.reorderExerciseGroups(realIds)
    }
}

struct ExerciseGroupFormView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss
    let group: ExerciseGroup?
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(group: ExerciseGroup?) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Push Day", text: $name)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit { save() }
                } header: {
                    Label("Group Name", systemImage: "square.stack.3d.up")
                }
            }
            .navigationTitle(group == nil ? "New Group" : "Rename Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(group == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let group {
            store.renameExerciseGroup(id: group.id, name: trimmed)
        } else {
            store.addExerciseGroup(name: trimmed)
        }
        dismiss()
    }
}

struct ExerciseFormView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise?
    @State private var name: String
    @State private var groupId: String?
    @State private var tracksWeight: Bool
    @FocusState private var isFocused: Bool

    init(exercise: Exercise?) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _groupId = State(initialValue: exercise?.group_id)
        _tracksWeight = State(initialValue: exercise?.tracks_weight ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Bench Press", text: $name)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit { save() }
                } header: {
                    Label("Exercise Name", systemImage: "figure.strengthtraining.traditional")
                }
                if !store.exerciseGroups.isEmpty {
                    Section {
                        Picker("Group", selection: $groupId) {
                            Text("Default").tag(Optional<String>.none)
                            ForEach(store.exerciseGroups.sorted { $0.position < $1.position }) { group in
                                Text(group.name).tag(Optional(group.id))
                            }
                        }
                    } header: {
                        Label("Group", systemImage: "square.stack.3d.up")
                    }
                }
                Section {
                    Toggle("Track Weight", isOn: $tracksWeight)
                } footer: {
                    Text("Turn off for bodyweight exercises like push-ups, where you only log reps.")
                }
            }
            .navigationTitle(exercise == nil ? "New Exercise" : "Rename Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(exercise == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let exercise {
            store.updateExercise(id: exercise.id, name: trimmed, groupId: groupId, tracksWeight: tracksWeight)
        } else {
            store.addExercise(name: trimmed, groupId: groupId, tracksWeight: tracksWeight)
        }
        dismiss()
    }
}

struct ExerciseHistoryView: View {
    @EnvironmentObject private var store: FitnessStore
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    @State private var history: [ExerciseHistorySet] = []
    @State private var isLoading = true
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false

    // Grouping/sorting/regression over `history` used to be computed properties
    // re-derived every time `body` referenced them — `dailyBests` alone was
    // recomputed up to 4x per render (once directly, once each from `weightTrend`/
    // `repsTrend`, once from `.count`), all synchronously on the same frame the
    // chart materializes. That redundant work was the actual source of the
    // freeze on opening this screen. Computed once in `.task` instead, before the
    // skeleton is dismissed, so revealing the real content is just a cheap read.
    @State private var groupedHistory: [(day: Date, sessionId: String, title: String, sets: [ExerciseHistorySet])] = []
    @State private var dailyBests: [DailyBest] = []
    @State private var weightTrend: ExerciseTrend?
    @State private var repsTrend: ExerciseTrend?

    /// Reflects renames instantly since `exercise` is just the value captured
    /// at navigation time — the store's copy is the one that stays live.
    private var currentName: String {
        store.exercises.first(where: { $0.id == exercise.id })?.name ?? exercise.name
    }

    /// Same freshness rationale as `currentName` — reflects a `tracks_weight` flip
    /// made from this same detail screen without needing to re-navigate.
    private var tracksWeight: Bool {
        store.exercises.first(where: { $0.id == exercise.id })?.tracks_weight ?? exercise.tracks_weight
    }

    /// Plans that reference this exercise — deleting it also removes it from
    /// each of these, so the confirmation alert names them up front.
    private var plansContainingExercise: [WorkoutPlan] {
        store.plans.filter { plan in plan.exercises.contains { $0.exercise_id == exercise.id } }
    }

    private var deleteConfirmationMessage: String {
        let names = plansContainingExercise.map(\.name)
        guard !names.isEmpty else { return "This can't be undone." }
        return "This can't be undone. It'll also be removed from \(names.joined(separator: ", "))."
    }

    private func estimatedOneRepMax(_ set: ExerciseHistorySet) -> Double {
        set.weight_kg * (1 + Double(set.reps) / 30)
    }

    /// Sets grouped by *session* (most recent first), both for the list and for
    /// the trend chart's data points — all derived from `history` in one pass.
    /// Everything here keys off session, not calendar day: two sessions logged
    /// on the same day are still separate workouts, so merging them by day alone
    /// both interleaved their set numbers in the list as if they were one
    /// session, and collapsed their two "bests" into a single chart point (which
    /// could hide the chart entirely — it needs 2+ points and a day with the
    /// exercise's only two sessions would otherwise count as just one). Days
    /// with more than one session get the session's start time appended to the
    /// section title so they stay distinguishable. "Best" (per session) is
    /// picked by estimated 1-rep-max (Epley) rather than raw weight, so a set
    /// that traded some weight for more reps — a legitimate form of progress —
    /// can still win. For reps-only exercises (no weight logged at all) that
    /// formula degenerates to zero for every set, so "best" falls back to simply
    /// the most reps. Weight and reps are trended independently — a rep-only
    /// improvement (same weight, more reps) should register as progress even
    /// when weight is flat.
    private func deriveHistory(_ history: [ExerciseHistorySet], tracksWeight: Bool) -> (
        grouped: [(day: Date, sessionId: String, title: String, sets: [ExerciseHistorySet])], bests: [DailyBest],
        weightTrend: ExerciseTrend?, repsTrend: ExerciseTrend?
    ) {
        let calendar = Calendar.current

        struct SessionGroup { let day: Date; let start: Date; let sessionId: String; let sets: [ExerciseHistorySet] }
        let sessionGroups: [SessionGroup] = Dictionary(grouping: history, by: \.session_id)
            .map { sessionId, sets in
                let sorted = sets.sorted { $0.set_number < $1.set_number }
                let start = sorted.map { DateFormatting.date(from: $0.captured_at) ?? .distantPast }.min() ?? .distantPast
                return SessionGroup(day: calendar.startOfDay(for: start), start: start, sessionId: sessionId, sets: sorted)
            }
            .sorted { $0.start > $1.start }

        let sessionsPerDay = Dictionary(grouping: sessionGroups, by: \.day).mapValues(\.count)
        let grouped = sessionGroups.map { group -> (day: Date, sessionId: String, title: String, sets: [ExerciseHistorySet]) in
            let dayText = DateFormatting.dayOnly.string(from: group.day)
            let title = (sessionsPerDay[group.day] ?? 1) > 1
                ? "\(dayText) · \(DateFormatting.timeOnly.string(from: group.start))"
                : dayText
            return (day: group.day, sessionId: group.sessionId, title: title, sets: group.sets)
        }

        let bests: [DailyBest] = sessionGroups
            .compactMap { group -> DailyBest? in
                let best = tracksWeight
                    ? group.sets.max(by: { estimatedOneRepMax($0) < estimatedOneRepMax($1) })
                    : group.sets.max(by: { $0.reps < $1.reps })
                guard let best else { return nil }
                return DailyBest(day: group.start, bestWeight: best.weight_kg, repsAtBest: best.reps)
            }
            .sorted { $0.day < $1.day }

        // The trend regression needs day-granularity x-values, not the bests' precise
        // session timestamps: two sessions minutes apart give the regression a
        // near-zero time delta, which blows up its per-week extrapolation (e.g. a
        // 10-rep gain in 5 minutes projects to +2000/day). Rounding to the day
        // means same-day sessions correctly contribute no slope information on
        // their own, while the plotted points (`bests`) keep full session
        // precision so same-day sessions still render as distinct points.
        let trendDays = bests.map { calendar.startOfDay(for: $0.day) }
        let weightTrend = ExerciseTrend(days: trendDays, values: bests.map(\.bestWeight), unitLabel: "kg", threshold: 0.25)
        let repsTrend = ExerciseTrend(days: trendDays, values: bests.map { Double($0.repsAtBest) }, unitLabel: "reps", threshold: 0.25)

        return (grouped, bests, weightTrend, repsTrend)
    }

    var body: some View {
        List {
            if isLoading {
                // Mirrors the shape of the real content (chart card + rows) so the
                // reveal doesn't introduce a large new section all at once.
                Section {
                    SkeletonBlock(height: 160, cornerRadius: 12)
                        .frame(maxWidth: .infinity)
                }
                .shimmering()
                Section {
                    ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                }
                .shimmering()
            } else if history.isEmpty {
                Section {
                    EmptyState(
                        systemImage: "chart.line.uptrend.xyaxis",
                        title: "No History Yet",
                        subtitle: "Sets logged for this exercise will show up here."
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if dailyBests.count >= 2 {
                    Section {
                        ExerciseTrendChart(
                            dailyBests: dailyBests,
                            weightTrend: tracksWeight ? weightTrend : nil,
                            repsTrend: repsTrend,
                            tracksWeight: tracksWeight
                        )
                    }
                }
                ForEach(groupedHistory, id: \.sessionId) { _, _, title, sets in
                    Section(title) {
                        ForEach(sets) { set in
                            HStack {
                                Text("Set \(set.set_number)").font(.subheadline.weight(.medium))
                                Spacer()
                                Text(tracksWeight ? "\(set.reps) × \(String(format: "%.1f", set.weight_kg))kg" : "\(set.reps) reps")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Text("Delete Exercise")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(currentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEdit = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showingEdit) {
            ExerciseFormView(exercise: exercise)
        }
        .alert("Delete Exercise?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteExercise(exercise)
                dismiss()
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .task {
            do {
                let fetched = try await APIClient.shared.fetchExerciseHistory(id: exercise.id)
                let derived = deriveHistory(fetched, tracksWeight: tracksWeight)
                history = fetched
                groupedHistory = derived.grouped
                dailyBests = derived.bests
                weightTrend = derived.weightTrend
                repsTrend = derived.repsTrend
            } catch {
                // silently ignore — dashboard-level errors surface elsewhere
            }
            isLoading = false
        }
    }
}

struct DailyBest: Identifiable {
    var id: Date { day }
    let day: Date
    let bestWeight: Double
    let repsAtBest: Int
}

enum TrendDirection {
    case up, down, flat

    var label: String {
        switch self {
        case .up: return "Trending Up"
        case .down: return "Trending Down"
        case .flat: return "Holding Steady"
        }
    }

    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .flat: return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }
}

/// Linear regression over a daily value series (weight or reps); slope determines direction.
/// Each metric gets its own trend so a rep-only improvement doesn't get masked by flat weight.
struct ExerciseTrend {
    let direction: TrendDirection
    let perWeek: Double
    let unitLabel: String
    let line: [(day: Date, value: Double)]

    init?(days: [Date], values: [Double], unitLabel: String, threshold: Double) {
        guard days.count == values.count, days.count >= 2 else { return nil }
        let referenceDay = days[0]
        let xs = days.map { $0.timeIntervalSince(referenceDay) / 86400 }
        let ys = values
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        perWeek = slope * 7
        self.unitLabel = unitLabel
        direction = perWeek > threshold ? .up : (perWeek < -threshold ? .down : .flat)
        line = [
            (days.first!, intercept + slope * xs.first!),
            (days.last!, intercept + slope * xs.last!)
        ]
    }
}

struct ExerciseTrendChart: View {
    let dailyBests: [DailyBest]
    let weightTrend: ExerciseTrend?
    let repsTrend: ExerciseTrend?
    var tracksWeight: Bool = true

    /// Headroom so the highest point sits at ~75% of the chart height instead of the very top.
    private static let headroom = 0.75

    private var weightMax: Double { max(dailyBests.map(\.bestWeight).max() ?? 0, 0.1) }
    private var weightAxisMax: Double { weightMax / Self.headroom }

    /// Reps get their own (rounded-up-to-5) scale. When weight is also tracked, that
    /// scale is mapped onto the weight axis so both lines can share one plot — the
    /// trailing axis relabels those positions back into reps so it reads like a genuine
    /// second axis. When weight isn't tracked, reps are plotted directly (no mapping).
    private var niceRepsMax: Int {
        let repsMax = dailyBests.map(\.repsAtBest).max() ?? 0
        return max(5, Int((Double(repsMax) / 5).rounded(.up)) * 5)
    }

    private var repsAxisMax: Double { Double(niceRepsMax) / Self.headroom }

    private func scaledReps(_ reps: Double) -> Double {
        guard tracksWeight else { return reps }
        return (reps / Double(niceRepsMax)) * weightMax
    }

    private var repsAxisTicks: [Int] { [0, niceRepsMax / 2, niceRepsMax] }

    @ViewBuilder
    private func trendBadge(_ trend: ExerciseTrend?) -> some View {
        if let trend {
            HStack(spacing: 4) {
                Image(systemName: trend.direction.systemImage)
                Text(String(format: "%+.1f %@/wk", trend.perWeek, trend.unitLabel))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(trend.direction.color)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if tracksWeight {
                    HStack(spacing: 4) {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        Text("Weight")
                    }
                    trendBadge(weightTrend)
                    Spacer()
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("Reps")
                }
                trendBadge(repsTrend)
                if !tracksWeight { Spacer() }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Chart {
                if tracksWeight {
                    ForEach(dailyBests) { point in
                        LineMark(x: .value("Date", point.day), y: .value("Weight", point.bestWeight), series: .value("Series", "Weight"))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Color.accentColor)
                        PointMark(x: .value("Date", point.day), y: .value("Weight", point.bestWeight))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                ForEach(dailyBests) { point in
                    LineMark(x: .value("Date", point.day), y: .value("Reps", scaledReps(Double(point.repsAtBest))), series: .value("Series", "Reps"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.orange)
                    PointMark(x: .value("Date", point.day), y: .value("Reps", scaledReps(Double(point.repsAtBest))))
                        .foregroundStyle(Color.orange)
                }
                if tracksWeight, let weightTrend {
                    ForEach(weightTrend.line, id: \.day) { point in
                        LineMark(x: .value("Date", point.day), y: .value("Weight", point.value), series: .value("Series", "Weight Trend"))
                    }
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                if let repsTrend {
                    ForEach(repsTrend.line, id: \.day) { point in
                        LineMark(x: .value("Date", point.day), y: .value("Reps", scaledReps(point.value)), series: .value("Series", "Reps Trend"))
                    }
                    .foregroundStyle(Color.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .chartYScale(domain: 0...(tracksWeight ? weightAxisMax : repsAxisMax))
            .frame(height: 160)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                if tracksWeight {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        if let kg = value.as(Double.self) {
                            AxisValueLabel { Text("\(Int(kg))kg") }
                        }
                    }
                    AxisMarks(position: .trailing, values: repsAxisTicks.map { scaledReps(Double($0)) }) { value in
                        if let raw = value.as(Double.self) {
                            let reps = Int((raw / weightMax * Double(niceRepsMax)).rounded())
                            AxisValueLabel { Text("\(reps)") }
                        }
                    }
                } else {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        if let reps = value.as(Double.self) {
                            AxisValueLabel { Text("\(Int(reps))") }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ExercisesView().environmentObject(FitnessStore())
}
