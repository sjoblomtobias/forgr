import Foundation
import Combine
import UIKit

@MainActor
final class FitnessStore: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var exerciseGroups: [ExerciseGroup] = []
    @Published var plans: [WorkoutPlan] = []
    @Published var sessions: [WorkoutSession] = []
    @Published var activeSession: WorkoutSession?
    @Published var measurements: [Measurement] = []

    @Published var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let client = APIClient.shared
    private var isLoadInFlight = false
    private var isSessionsRefreshInFlight = false

    init() {
        if let snapshot = FitnessCache.load() {
            exercises = snapshot.exercises
            exerciseGroups = snapshot.exerciseGroups
            plans = snapshot.plans
            sessions = snapshot.sessions
            activeSession = snapshot.activeSession
            measurements = snapshot.measurements
            hasLoadedOnce = true
        }
    }

    func loadAll() async {
        guard !isLoadInFlight else { return }
        isLoadInFlight = true
        defer { isLoadInFlight = false }

        isLoading = true
        errorMessage = nil
        var failures: [String] = []

        async let exercisesResult = attempt("exercises") { try await self.client.fetchExercises() }
        async let exerciseGroupsResult = attempt("exercise groups") { try await self.client.fetchExerciseGroups() }
        async let plansResult = attempt("plans") { try await self.client.fetchWorkoutPlans() }
        async let sessionsResult = attempt("sessions") { try await self.client.fetchWorkoutSessions() }
        async let activeResult = attempt("active session") { try await self.client.fetchActiveSession() }
        async let measurementsResult = attempt("measurements") { try await self.client.fetchMeasurements() }

        var hasChanges = false

        if let exercises = await exercisesResult.value {
            let sorted = exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            hasChanges = setIfChanged(&self.exercises, sorted) || hasChanges
        } else if let failure = await exercisesResult.failure { failures.append(failure) }

        if let exerciseGroups = await exerciseGroupsResult.value {
            let sorted = exerciseGroups.sorted { $0.position < $1.position }
            hasChanges = setIfChanged(&self.exerciseGroups, sorted) || hasChanges
        } else if let failure = await exerciseGroupsResult.failure { failures.append(failure) }

        if let plans = await plansResult.value {
            hasChanges = setIfChanged(&self.plans, plans) || hasChanges
        } else if let failure = await plansResult.failure { failures.append(failure) }

        if let sessions = await sessionsResult.value {
            let sorted = sessions.sorted { $0.captured_at > $1.captured_at }
            hasChanges = setIfChanged(&self.sessions, sorted) || hasChanges
        } else if let failure = await sessionsResult.failure { failures.append(failure) }

        if let active = await activeResult.value {
            hasChanges = setIfChanged(&self.activeSession, active) || hasChanges
            // Covers relaunching into a session whose Live Activity already ended
            // (e.g. it hit ActivityKit's display budget) — start() no-ops if one's
            // already running.
            if let active, active.status != .completed {
                LiveActivityManager.start(planName: active.plan_name, startDate: DateFormatting.date(from: active.captured_at) ?? Date())
            }
        } else if let failure = await activeResult.failure { failures.append(failure) }

        if let measurements = await measurementsResult.value {
            let sorted = measurements.sorted { $0.created_at > $1.created_at }
            hasChanges = setIfChanged(&self.measurements, sorted) || hasChanges
        } else if let failure = await measurementsResult.failure { failures.append(failure) }

        if !failures.isEmpty {
            errorMessage = "Couldn't load your data. Try again."
        }
        isLoading = false
        hasLoadedOnce = true
        if hasChanges {
            persistSnapshot()
        }
    }

    /// Only assigns (and thus only triggers `@Published`/SwiftUI updates) when
    /// the freshly fetched value actually differs from what's already showing
    /// — a `loadAll()` that finds nothing new should re-render nothing.
    @discardableResult
    private func setIfChanged<T: Equatable>(_ current: inout T, _ new: T) -> Bool {
        guard current != new else { return false }
        current = new
        return true
    }

    private func persistSnapshot() {
        let snapshot = FitnessSnapshot(
            exercises: exercises, exerciseGroups: exerciseGroups, plans: plans, sessions: sessions,
            activeSession: activeSession, measurements: measurements
        )
        Task.detached(priority: .background) {
            FitnessCache.save(snapshot)
        }
    }

    /// Wipes all in-memory and on-disk data. Called on logout/unauthorized so a
    /// different user on the same device never briefly sees stale cached data.
    func clearCache() {
        exercises = []
        exerciseGroups = []
        plans = []
        sessions = []
        activeSession = nil
        measurements = []
        hasLoadedOnce = false
        errorMessage = nil
        FitnessCache.clear()
    }

    private func attempt<T>(_ label: String, _ work: @escaping () async throws -> T) async -> (value: T?, failure: String?) {
        do {
            let value = try await work()
            return (value, nil)
        } catch is CancellationError {
            return (nil, nil)
        } catch {
            return (nil, "\(label) (\(error.localizedDescription))")
        }
    }

    /// Runs a background write with an iOS background-task assertion held for its
    /// duration, so a fire-and-forget sync started right before the user quits or
    /// backgrounds the app gets a grace period to actually reach the server instead
    /// of being killed mid-flight.
    private func runInBackground(_ work: @escaping () async -> Void) {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "FitnessStore.sync") {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
        Task {
            await work()
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
    }

    /// A locally-minted id for optimistic inserts, so we have something to key
    /// off of until the server assigns the real one.
    private static func tempId() -> String { "temp-\(UUID().uuidString)" }

    private static func now() -> String { ISO8601Formatter.shared.string(from: Date()) }

    // MARK: - Exercises

    /// Every mutation below applies its change to local state immediately and
    /// fires the network request in the background, reconciling (or rolling
    /// back) when the response comes in — the UI never waits on a round trip.
    func addExercise(name: String, groupId: String? = nil, tracksWeight: Bool = true) {
        let id = Self.tempId()
        let position = exercises.filter { $0.group_id == groupId }.count
        let placeholder = Exercise(
            id: id, name: name, created_at: Self.now(), updated_at: Self.now(), user_id: "",
            group_id: groupId, position: position, tracks_weight: tracksWeight
        )
        exercises.append(placeholder)
        exercises.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        runInBackground { [self] in
            do {
                let exercise = try await client.createExercise(name: name, groupId: groupId, tracksWeight: tracksWeight)
                if let index = exercises.firstIndex(where: { $0.id == id }) {
                    exercises[index] = exercise
                    exercises.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            } catch {
                exercises.removeAll { $0.id == id }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Renames and/or moves an exercise into (or out of, via `groupId: nil`) a group.
    /// Position within its group/bucket is left to the server (reordering goes through
    /// `reorderExercises`).
    func updateExercise(id: String, name: String, groupId: String?, tracksWeight: Bool? = nil) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let previous = exercises[index]
        exercises[index].name = name
        exercises[index].group_id = groupId
        if let tracksWeight { exercises[index].tracks_weight = tracksWeight }
        exercises.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        runInBackground { [self] in
            do {
                let exercise = try await client.updateExercise(id: id, name: name, groupId: .some(groupId), tracksWeight: tracksWeight)
                if let index = exercises.firstIndex(where: { $0.id == id }) {
                    exercises[index] = exercise
                    exercises.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            } catch {
                if let index = exercises.firstIndex(where: { $0.id == id }) {
                    exercises[index] = previous
                    exercises.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Applies a new manual order (via `position`) to a set of exercises that share a
    /// group — e.g. after a drag-to-reorder within one section of the grouped list.
    func reorderExercises(_ orderedIds: [String]) {
        let previous = exercises
        for (position, id) in orderedIds.enumerated() {
            if let index = exercises.firstIndex(where: { $0.id == id }) {
                exercises[index].position = position
            }
        }

        runInBackground { [self] in
            do {
                for (position, id) in orderedIds.enumerated() {
                    guard let exercise = exercises.first(where: { $0.id == id }) else { continue }
                    let updated = try await client.updateExercise(id: id, name: exercise.name, position: position)
                    if let index = exercises.firstIndex(where: { $0.id == id }) {
                        exercises[index] = updated
                    }
                }
            } catch {
                exercises = previous
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteExercise(_ exercise: Exercise) {
        let previousIndex = exercises.firstIndex(where: { $0.id == exercise.id })
        exercises.removeAll { $0.id == exercise.id }

        runInBackground { [self] in
            do {
                try await client.deleteExercise(id: exercise.id)
            } catch {
                if let previousIndex, !exercises.contains(where: { $0.id == exercise.id }) {
                    exercises.insert(exercise, at: min(previousIndex, exercises.count))
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Exercise Groups

    func addExerciseGroup(name: String) {
        let id = Self.tempId()
        let placeholder = ExerciseGroup(
            id: id, name: name, position: exerciseGroups.count, user_id: "",
            created_at: Self.now(), updated_at: Self.now()
        )
        exerciseGroups.append(placeholder)

        runInBackground { [self] in
            do {
                let group = try await client.createExerciseGroup(name: name)
                if let index = exerciseGroups.firstIndex(where: { $0.id == id }) {
                    exerciseGroups[index] = group
                }
            } catch {
                exerciseGroups.removeAll { $0.id == id }
                errorMessage = error.localizedDescription
            }
        }
    }

    func renameExerciseGroup(id: String, name: String) {
        guard let index = exerciseGroups.firstIndex(where: { $0.id == id }) else { return }
        let previous = exerciseGroups[index]
        exerciseGroups[index].name = name

        runInBackground { [self] in
            do {
                let group = try await client.updateExerciseGroup(id: id, name: name)
                if let index = exerciseGroups.firstIndex(where: { $0.id == id }) {
                    exerciseGroups[index] = group
                }
            } catch {
                if let index = exerciseGroups.firstIndex(where: { $0.id == id }) {
                    exerciseGroups[index] = previous
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func reorderExerciseGroups(_ orderedIds: [String]) {
        let previous = exerciseGroups
        exerciseGroups = orderedIds.enumerated().compactMap { position, id in
            guard var group = exerciseGroups.first(where: { $0.id == id }) else { return nil }
            group.position = position
            return group
        }

        runInBackground { [self] in
            do {
                for (position, id) in orderedIds.enumerated() {
                    let group = try await client.updateExerciseGroup(id: id, position: position)
                    if let index = exerciseGroups.firstIndex(where: { $0.id == id }) {
                        exerciseGroups[index] = group
                    }
                }
            } catch {
                exerciseGroups = previous
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Deleting a group ungroups its exercises rather than deleting them, both locally
    /// and on the server (confirmed server-side behavior — not a cascade delete).
    func deleteExerciseGroup(_ group: ExerciseGroup) {
        let previousIndex = exerciseGroups.firstIndex(where: { $0.id == group.id })
        exerciseGroups.removeAll { $0.id == group.id }
        let affectedIds = exercises.filter { $0.group_id == group.id }.map(\.id)
        for id in affectedIds {
            if let index = exercises.firstIndex(where: { $0.id == id }) {
                exercises[index].group_id = nil
            }
        }

        runInBackground { [self] in
            do {
                try await client.deleteExerciseGroup(id: group.id)
            } catch {
                if let previousIndex, !exerciseGroups.contains(where: { $0.id == group.id }) {
                    exerciseGroups.insert(group, at: min(previousIndex, exerciseGroups.count))
                }
                for id in affectedIds {
                    if let index = exercises.firstIndex(where: { $0.id == id }) {
                        exercises[index].group_id = group.id
                    }
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Plans

    func addPlan(name: String, exercises exerciseInputs: [PlanExerciseInput]) {
        let id = Self.tempId()
        let placeholder = WorkoutPlan(
            id: id, name: name, created_at: Self.now(), updated_at: Self.now(), user_id: "",
            exercises: optimisticPlanExercises(planId: id, inputs: exerciseInputs)
        )
        plans.append(placeholder)

        runInBackground { [self] in
            do {
                let plan = try await client.createWorkoutPlan(name: name, exercises: exerciseInputs)
                if let index = plans.firstIndex(where: { $0.id == id }) {
                    plans[index] = plan
                }
            } catch {
                plans.removeAll { $0.id == id }
                errorMessage = error.localizedDescription
            }
        }
    }

    func updatePlan(id: String, name: String, exercises exerciseInputs: [PlanExerciseInput]) {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return }
        let previous = plans[index]
        plans[index].name = name
        plans[index].exercises = optimisticPlanExercises(planId: id, inputs: exerciseInputs, reusingFrom: previous)

        runInBackground { [self] in
            do {
                let plan = try await client.updateWorkoutPlan(id: id, name: name, exercises: exerciseInputs)
                if let index = plans.firstIndex(where: { $0.id == id }) {
                    plans[index] = plan
                }
            } catch {
                if let index = plans.firstIndex(where: { $0.id == id }) {
                    plans[index] = previous
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func optimisticPlanExercises(
        planId: String, inputs: [PlanExerciseInput], reusingFrom previous: WorkoutPlan? = nil
    ) -> [PlanExercise] {
        inputs.enumerated().map { position, input in
            let existingId = previous?.exercises.first(where: { $0.exercise_id == input.exercise_id })?.id
            return PlanExercise(
                id: existingId ?? Self.tempId(),
                plan_id: planId,
                exercise_id: input.exercise_id,
                exercise_name: exercises.first(where: { $0.id == input.exercise_id })?.name ?? "",
                target_sets: input.target_sets,
                target_reps: input.target_reps,
                position: position
            )
        }
    }

    func deletePlan(_ plan: WorkoutPlan) {
        let previousIndex = plans.firstIndex(where: { $0.id == plan.id })
        plans.removeAll { $0.id == plan.id }

        runInBackground { [self] in
            do {
                try await client.deleteWorkoutPlan(id: plan.id)
            } catch {
                if let previousIndex, !plans.contains(where: { $0.id == plan.id }) {
                    plans.insert(plan, at: min(previousIndex, plans.count))
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Sessions

    /// Re-fetches completed/history sessions straight from the backend, so views
    /// that only ran once at launch (or are reading a stale on-disk cache) get
    /// corrected instead of silently trusting whatever's already in memory.
    /// Deliberately leaves `activeSession` untouched: a session currently being
    /// edited is driven by its own optimistic local state via `saveSets`, and
    /// overwriting it here could stomp on edits not yet flushed to the server.
    func refreshSessions() async {
        guard !isSessionsRefreshInFlight else { return }
        isSessionsRefreshInFlight = true
        defer { isSessionsRefreshInFlight = false }

        do {
            let sessions = try await client.fetchWorkoutSessions()
            let sorted = sessions.sorted { $0.captured_at > $1.captured_at }
            if setIfChanged(&self.sessions, sorted) {
                persistSnapshot()
            }
        } catch is CancellationError {
            // Navigating away mid-fetch — nothing to reconcile.
        } catch {
            errorMessage = "Couldn't refresh session history. \(error.localizedDescription)"
        }
    }

    /// Starting a session optimistically opens the session editor right away with
    /// a placeholder id; `saveSets`/`completeSession`/`deleteSession` below treat
    /// any id starting with "temp-" as not-yet-real and hold off calling the
    /// backend until the real session comes back and this id is reconciled.
    func startSession(planId: String) {
        guard let plan = plans.first(where: { $0.id == planId }) else { return }
        let id = Self.tempId()
        let placeholder = WorkoutSession(
            id: id, plan_id: planId, plan_name: plan.name, captured_at: Self.now(),
            completed_at: nil, status: .inProgress, user_id: "", sets: []
        )
        activeSession = placeholder
        sessions.insert(placeholder, at: 0)
        LiveActivityManager.start(planName: plan.name, startDate: Date())

        runInBackground { [self] in
            do {
                let session = try await client.startSession(planId: planId)
                if activeSession?.id == id { activeSession = session }
                if let index = sessions.firstIndex(where: { $0.id == id }) {
                    sessions[index] = session
                }
            } catch {
                if activeSession?.id == id { activeSession = nil }
                sessions.removeAll { $0.id == id }
                LiveActivityManager.end()
                errorMessage = error.localizedDescription
            }
        }
    }

    func saveSets(sessionId: String, sets: [SessionSetInput]) {
        guard !sessionId.hasPrefix("temp-") else { return }
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].sets = optimisticSessionSets(sessionId: sessionId, inputs: sets, reusingFrom: sessions[index].sets)
        }
        if activeSession?.id == sessionId {
            activeSession?.sets = optimisticSessionSets(sessionId: sessionId, inputs: sets, reusingFrom: activeSession?.sets ?? [])
        }

        runInBackground { [self] in
            do {
                let session = try await client.updateSessionSets(id: sessionId, sets: sets)
                if activeSession?.id == sessionId { activeSession = session }
                if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                    sessions[index] = session
                } else {
                    sessions.insert(session, at: 0)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func optimisticSessionSets(
        sessionId: String, inputs: [SessionSetInput], reusingFrom previous: [SessionSet]
    ) -> [SessionSet] {
        inputs.map { input in
            let existingId = previous.first(where: { $0.plan_exercise_id == input.plan_exercise_id && $0.set_number == input.set_number })?.id
            return SessionSet(
                id: existingId ?? Self.tempId(),
                session_id: sessionId,
                exercise_id: input.exercise_id,
                plan_exercise_id: input.plan_exercise_id,
                exercise_name: previous.first(where: { $0.exercise_id == input.exercise_id })?.exercise_name ?? "",
                set_number: input.set_number,
                weight_kg: input.weight_kg,
                reps: input.reps,
                created_at: Self.now()
            )
        }
    }

    func completeSession(sessionId: String) {
        guard !sessionId.hasPrefix("temp-") else { return }
        let previousActiveSession = activeSession
        let previousIndex = sessions.firstIndex(where: { $0.id == sessionId })
        let previousSession = previousIndex.map { sessions[$0] }

        if activeSession?.id == sessionId { activeSession = nil }
        if let previousIndex {
            sessions[previousIndex].status = .completed
        }
        LiveActivityManager.end()

        runInBackground { [self] in
            do {
                let session = try await client.completeSession(id: sessionId)
                if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                    sessions[index] = session
                } else {
                    sessions.insert(session, at: 0)
                }
            } catch {
                if previousActiveSession?.id == sessionId { activeSession = previousActiveSession }
                if let previousIndex, let previousSession, previousIndex < sessions.count, sessions[previousIndex].id == sessionId {
                    sessions[previousIndex] = previousSession
                }
                if previousActiveSession?.id == sessionId {
                    LiveActivityManager.start(planName: previousActiveSession?.plan_name ?? "", startDate: DateFormatting.date(from: previousActiveSession?.captured_at ?? "") ?? Date())
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteSession(_ session: WorkoutSession) {
        let previousIndex = sessions.firstIndex(where: { $0.id == session.id })
        let wasActive = activeSession?.id == session.id
        sessions.removeAll { $0.id == session.id }
        if wasActive {
            activeSession = nil
            LiveActivityManager.end()
        }

        guard !session.id.hasPrefix("temp-") else { return }
        runInBackground { [self] in
            do {
                try await client.deleteSession(id: session.id)
            } catch {
                if let previousIndex, !sessions.contains(where: { $0.id == session.id }) {
                    sessions.insert(session, at: min(previousIndex, sessions.count))
                }
                if wasActive {
                    activeSession = session
                    LiveActivityManager.start(planName: session.plan_name, startDate: DateFormatting.date(from: session.captured_at) ?? Date())
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Measurements

    func addMeasurement(weightKg: Double, bodyFatPercent: Double?, note: String?) {
        let id = Self.tempId()
        let placeholder = Measurement(
            id: id, weight_kg: weightKg, body_fat_percent: bodyFatPercent, note: note,
            created_at: Self.now(), updated_at: Self.now(), user_id: ""
        )
        measurements.insert(placeholder, at: 0)

        runInBackground { [self] in
            do {
                let measurement = try await client.createMeasurement(weightKg: weightKg, bodyFatPercent: bodyFatPercent, note: note)
                if let index = measurements.firstIndex(where: { $0.id == id }) {
                    measurements[index] = measurement
                }
            } catch {
                measurements.removeAll { $0.id == id }
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateMeasurement(id: String, weightKg: Double, bodyFatPercent: Double?, note: String?) {
        guard let index = measurements.firstIndex(where: { $0.id == id }) else { return }
        let previous = measurements[index]
        measurements[index].weight_kg = weightKg
        measurements[index].body_fat_percent = bodyFatPercent
        measurements[index].note = note

        runInBackground { [self] in
            do {
                let measurement = try await client.updateMeasurement(id: id, weightKg: weightKg, bodyFatPercent: bodyFatPercent, note: note)
                if let index = measurements.firstIndex(where: { $0.id == id }) {
                    measurements[index] = measurement
                }
            } catch {
                if let index = measurements.firstIndex(where: { $0.id == id }) {
                    measurements[index] = previous
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteMeasurement(_ measurement: Measurement) {
        let previousIndex = measurements.firstIndex(where: { $0.id == measurement.id })
        measurements.removeAll { $0.id == measurement.id }

        runInBackground { [self] in
            do {
                try await client.deleteMeasurement(id: measurement.id)
            } catch {
                if let previousIndex, !measurements.contains(where: { $0.id == measurement.id }) {
                    measurements.insert(measurement, at: min(previousIndex, measurements.count))
                }
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum ISO8601Formatter {
    static let shared: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
