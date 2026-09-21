import Foundation

// MARK: - Exercise

nonisolated struct Exercise: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    let created_at: String
    let updated_at: String
    let user_id: String
    var group_id: String?
    var position: Int
    /// False for bodyweight/reps-only exercises (push-ups, etc.) — session logging
    /// and history hide the weight field entirely when this is false.
    var tracks_weight: Bool = true
}

// MARK: - Exercise Group

nonisolated struct ExerciseGroup: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var position: Int
    let user_id: String
    let created_at: String
    let updated_at: String
}

// MARK: - Workout Plan

nonisolated struct PlanExercise: Identifiable, Codable, Hashable {
    let id: String
    let plan_id: String
    let exercise_id: String
    var exercise_name: String
    var target_sets: Int
    var target_reps: Int
    var position: Int
}

nonisolated struct WorkoutPlan: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    let created_at: String
    let updated_at: String
    let user_id: String
    var exercises: [PlanExercise]
    var position: Int
}

nonisolated struct PlanExerciseInput: Codable {
    var exercise_id: String
    var target_sets: Int
    var target_reps: Int
}

// MARK: - Workout Session

nonisolated struct SessionSet: Identifiable, Codable, Hashable {
    let id: String
    let session_id: String
    var exercise_id: String?
    var plan_exercise_id: String?
    var exercise_name: String
    var set_number: Int
    var weight_kg: Double
    var reps: Int
    let created_at: String
}

nonisolated enum SessionStatus: String, Codable {
    case inProgress = "in_progress"
    case completed = "completed"
}

nonisolated struct WorkoutSession: Identifiable, Codable, Hashable {
    let id: String
    var plan_id: String?
    var plan_name: String
    var captured_at: String
    var completed_at: String?
    var status: SessionStatus
    let user_id: String
    var sets: [SessionSet]
}

nonisolated struct SessionSetInput: Codable {
    var exercise_id: String?
    var plan_exercise_id: String?
    var set_number: Int
    var weight_kg: Double
    var reps: Int
}

// MARK: - Measurement

nonisolated struct Measurement: Identifiable, Codable, Hashable {
    let id: String
    var weight_kg: Double
    var body_fat_percent: Double?
    var note: String?
    let created_at: String
    let updated_at: String
    let user_id: String
}

// MARK: - Exercise history

nonisolated struct ExerciseHistorySet: Identifiable, Codable, Hashable {
    let id: String
    let session_id: String
    var exercise_id: String?
    var plan_exercise_id: String?
    var exercise_name: String
    var set_number: Int
    var weight_kg: Double
    var reps: Int
    let created_at: String
    let captured_at: String
}

// MARK: - On-device cache snapshot

nonisolated struct FitnessSnapshot: Codable {
    var exercises: [Exercise]
    var exerciseGroups: [ExerciseGroup]
    var plans: [WorkoutPlan]
    var sessions: [WorkoutSession]
    var activeSession: WorkoutSession?
    var measurements: [Measurement]
}
