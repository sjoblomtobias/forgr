import Foundation

/// Mirrors the `api` namespace of the shared backend's i18n locale files
/// (`library/src/locales/en.ts` / `sv.ts`). The server returns lookup keys
/// like `"api.workoutSessionEmptySets"` in error `message` fields, not
/// display text — the Vue client translates these locally via `t()`, and
/// this is the iOS equivalent. Only covers keys forgr's endpoints can
/// actually return; grows as those endpoints do.
enum ApiMessages {
    private static let en: [String: String] = [
        "invalidRequest": "Invalid request",
        "internalServerError": "Internal server error",
        "unauthorized": "Unauthorized",
        "usernameTaken": "Username already taken",
        "userNotFound": "User not found",
        "invalidCredentials": "Invalid credentials",
        "invalidPassword": "Invalid password",
        "userRegistered": "User registered successfully",
        "userLoggedIn": "User logged in successfully",
        "userDeleted": "User deleted successfully",
        "tooManyRequests": "Too many attempts. Please try again later.",
        "exercisesRetrieved": "Exercises retrieved successfully",
        "exerciseCreated": "Exercise created successfully",
        "exerciseUpdated": "Exercise updated successfully",
        "exerciseDeleted": "Exercise deleted successfully",
        "exerciseNotFound": "Exercise not found",
        "exerciseGroupsRetrieved": "Exercise groups retrieved successfully",
        "exerciseGroupCreated": "Exercise group created successfully",
        "exerciseGroupUpdated": "Exercise group updated successfully",
        "exerciseGroupDeleted": "Exercise group deleted successfully",
        "exerciseGroupNotFound": "Exercise group not found",
        "workoutPlansRetrieved": "Workout plans retrieved successfully",
        "workoutPlanCreated": "Workout plan created successfully",
        "workoutPlanUpdated": "Workout plan updated successfully",
        "workoutPlanDeleted": "Workout plan deleted successfully",
        "workoutPlanNotFound": "Workout plan not found",
        "workoutPlanEmpty": "Add at least one exercise to this plan before starting a workout",
        "workoutSessionsRetrieved": "Workout sessions retrieved successfully",
        "workoutSessionStarted": "Workout started",
        "workoutSessionUpdated": "Workout session updated successfully",
        "workoutSessionCompleted": "Workout logged successfully",
        "workoutSessionAlreadyCompleted": "This workout has already been logged",
        "workoutSessionEmptySets": "Add at least one set before logging this workout",
        "workoutSessionDeleted": "Workout session deleted successfully",
        "workoutSessionNotFound": "Workout session not found",
        "measurementsRetrieved": "Measurements retrieved successfully",
        "measurementCreated": "Measurement logged successfully",
        "measurementUpdated": "Measurement updated successfully",
        "measurementDeleted": "Measurement deleted successfully",
        "measurementNotFound": "Measurement not found",
    ]

    // forgr's UI is English-only throughout (no other localization exists in
    // this app), so these are always translated to English regardless of
    // device locale, unlike the backend's Vue client which supports sv too.
    private static var table: [String: String] { en }

    /// Translates a raw `"api.<key>"` message from the backend into display
    /// text, including the `"api.<key>: <zod issues>"` shape `APIClient`
    /// appends validation details in. Anything that isn't a known key
    /// (already-human text, or a key not yet ported here) passes through
    /// unchanged.
    static func translate(_ raw: String) -> String {
        let prefix = "api."
        guard raw.hasPrefix(prefix) else { return raw }

        let afterPrefix = raw.dropFirst(prefix.count)
        guard let separatorRange = afterPrefix.range(of: ": ") else {
            return table[String(afterPrefix)] ?? raw
        }

        let key = String(afterPrefix[afterPrefix.startIndex..<separatorRange.lowerBound])
        guard let translated = table[key] else { return raw }
        let rest = afterPrefix[separatorRange.upperBound...]
        return rest.isEmpty ? translated : "\(translated) \(rest)"
    }
}
