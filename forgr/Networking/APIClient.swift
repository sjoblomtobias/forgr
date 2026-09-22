import Foundation

struct APIErrorBody: Decodable {
    let message: String
    let errors: [ZodIssueLike]?
}

/// Zod's `issue.path` mixes object keys (strings) and array indices (numbers),
/// e.g. `["exercises", 0, "exercise_id"]` — decode either so a numeric segment
/// doesn't fail the whole `[String]` decode and silently swallow the error.
enum ZodPathSegment: Decodable {
    case string(String)
    case number(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .number(try container.decode(Int.self))
        }
    }

    var description: String {
        switch self {
        case .string(let value): value
        case .number(let value): String(value)
        }
    }
}

struct ZodIssueLike: Decodable {
    let message: String?
    let path: [ZodPathSegment]?

    /// e.g. "exercises.0.exercise_id: Invalid uuid" — falls back to just the
    /// message (or is dropped entirely) when either piece is missing.
    var displayText: String? {
        guard let message, !message.isEmpty else { return nil }
        guard let path, !path.isEmpty else { return message }
        return "\(path.map(\.description).joined(separator: ".")): \(message)"
    }
}

enum APIError: LocalizedError {
    case unauthorized
    case server(status: Int, message: String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session has expired. Please log in again."
        case .server(_, let message): return ApiMessages.translate(message)
        case .decoding(let message): return "Something went wrong reading the server's response: \(message)"
        case .network(let message): return message
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://datavetenskap.com/api")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    var token: String? {
        get { KeychainStore.loadToken() }
        set {
            if let newValue {
                KeychainStore.save(token: newValue)
            } else {
                KeychainStore.clear()
            }
        }
    }

    var isAuthenticated: Bool { token != nil }

    /// Decoded from the stored JWT's payload — there's no separate user-info endpoint.
    var username: String? { token.flatMap(JWTDecoder.username(fromToken:)) }

    // MARK: - Core request

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        authenticated: Bool = true
    ) async throws -> Response {
        var url = baseURL
        url.append(path: path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated {
            guard let token else { throw APIError.unauthorized }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("No response from server.")
        }

        if http.statusCode == 401 {
            self.token = nil
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            if let errorBody = try? decoder.decode(APIErrorBody.self, from: data) {
                let issues = errorBody.errors?.compactMap(\.displayText) ?? []
                let fullMessage = issues.isEmpty ? errorBody.message : "\(errorBody.message): \(issues.joined(separator: "; "))"
                throw APIError.server(status: http.statusCode, message: fullMessage)
            }
            throw APIError.server(status: http.statusCode, message: "Request failed with status \(http.statusCode).")
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private func requestNoContent(path: String, method: String, body: Encodable? = nil) async throws {
        let _: EmptyResponse = try await request(path: path, method: method, body: body)
    }

    // MARK: - Auth

    func login(username: String, password: String) async throws {
        struct LoginRequest: Encodable { let username: String; let password: String }
        struct LoginResponse: Decodable { let message: String; let token: String? }
        let response: LoginResponse = try await request(
            path: "auth/login", method: "POST",
            body: LoginRequest(username: username, password: password),
            authenticated: false
        )
        guard let token = response.token else {
            throw APIError.server(status: 401, message: response.message)
        }
        self.token = token
    }

    func logout() {
        token = nil
    }

    /// Registration doesn't return a token — call `login` afterward to establish a
    /// session. The server responds with an i18n key (e.g. "api.usernameTaken"),
    /// not display text, so known register-specific failures are remapped to plain English here.
    func register(username: String, password: String) async throws {
        struct RegisterRequest: Encodable {
            let username: String
            let password: String
            let agreed_to_terms: Bool
        }
        struct Response: Decodable { let message: String }
        do {
            let _: Response = try await request(
                path: "auth/register", method: "POST",
                body: RegisterRequest(username: username, password: password, agreed_to_terms: true),
                authenticated: false
            )
        } catch APIError.server(let status, let message) {
            throw APIError.server(status: status, message: Self.humanizeRegisterError(message))
        }
    }

    private static func humanizeRegisterError(_ raw: String) -> String {
        let knownKeys: [String: String] = [
            "api.usernameTaken": "That username is already taken.",
            "api.internalServerError": "Something went wrong on our end. Please try again.",
            "api.invalidRequest": "Please check your details.",
        ]
        for (key, friendly) in knownKeys {
            if raw == key { return friendly }
            if raw.hasPrefix(key + ":") {
                let rest = raw.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? friendly : "\(friendly) \(rest)"
            }
        }
        return raw
    }

    /// Bumps `token_version` server-side, invalidating tokens on every other device —
    /// the response carries a fresh token for *this* session, which must replace the
    /// stored one (it re-encodes the same username, but callers shouldn't assume that).
    func changePassword(currentPassword: String, newPassword: String) async throws {
        struct Body: Encodable { let current_password: String; let new_password: String }
        struct Response: Decodable { let message: String; let token: String }
        do {
            let response: Response = try await request(
                path: "account/password", method: "PATCH",
                body: Body(current_password: currentPassword, new_password: newPassword)
            )
            token = response.token
        } catch APIError.server(let status, let message) {
            throw APIError.server(status: status, message: Self.humanizeAccountError(message))
        }
    }

    private static func humanizeAccountError(_ raw: String) -> String {
        let knownKeys: [String: String] = [
            "api.invalidPassword": "That's not your current password.",
            "api.userNotFound": "Something went wrong on our end. Please try again.",
            "api.internalServerError": "Something went wrong on our end. Please try again.",
            "api.invalidRequest": "Please check your details.",
        ]
        for (key, friendly) in knownKeys {
            if raw == key { return friendly }
            if raw.hasPrefix(key + ":") {
                let rest = raw.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? friendly : "\(friendly) \(rest)"
            }
        }
        return raw
    }

    /// Throws `.unauthorized` if the token itself is invalid/expired, or any other
    /// `APIError` (e.g. `.network`) if we simply couldn't reach the server.
    /// Callers should only treat `.unauthorized` as a reason to log out.
    func verifyToken() async throws {
        struct VerifyResponse: Decodable { let message: String }
        let _: VerifyResponse = try await request(path: "auth/verify", method: "GET")
    }

    // MARK: - Exercises

    func fetchExercises() async throws -> [Exercise] {
        struct Response: Decodable { let exercises: [Exercise] }
        let response: Response = try await request(path: "exercises")
        return response.exercises
    }

    func createExercise(name: String, groupId: String? = nil, tracksWeight: Bool = true) async throws -> Exercise {
        struct Body: Encodable { let name: String; let group_id: String?; let tracks_weight: Bool }
        struct Response: Decodable { let exercise: Exercise }
        let response: Response = try await request(
            path: "exercises", method: "POST",
            body: Body(name: name, group_id: groupId, tracks_weight: tracksWeight)
        )
        return response.exercise
    }

    /// `groupId`/`position` are double-optional: `nil` (the outer optional) omits the field
    /// entirely so the server leaves that value untouched; `.some(nil)` sends an explicit
    /// JSON `null` (ungroups); `.some(id)` sends a value. See `Body.encode` below.
    /// `tracksWeight` is a plain optional: `nil` omits the field (server leaves it
    /// unchanged), a value sends it explicitly — there's no "explicit null" case for a bool.
    func updateExercise(id: String, name: String, groupId: String?? = nil, position: Int? = nil, tracksWeight: Bool? = nil) async throws -> Exercise {
        struct Body: Encodable {
            let id: String
            let name: String
            let group_id: String??
            let position: Int?
            let tracks_weight: Bool?

            enum CodingKeys: String, CodingKey { case id, name, group_id, position, tracks_weight }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(id, forKey: .id)
                try container.encode(name, forKey: .name)
                if let group_id {
                    try container.encode(group_id, forKey: .group_id)
                }
                try container.encodeIfPresent(position, forKey: .position)
                try container.encodeIfPresent(tracks_weight, forKey: .tracks_weight)
            }
        }
        struct Response: Decodable { let exercise: Exercise }
        let response: Response = try await request(
            path: "exercises", method: "PUT",
            body: Body(id: id, name: name, group_id: groupId, position: position, tracks_weight: tracksWeight)
        )
        return response.exercise
    }

    func deleteExercise(id: String) async throws {
        try await requestNoContent(path: "exercises/\(id)", method: "DELETE")
    }

    func fetchExerciseHistory(id: String) async throws -> [ExerciseHistorySet] {
        struct Response: Decodable { let sets: [ExerciseHistorySet] }
        let response: Response = try await request(path: "exercises/\(id)/history")
        return response.sets
    }

    // MARK: - Exercise Groups

    func fetchExerciseGroups() async throws -> [ExerciseGroup] {
        struct Response: Decodable { let exercise_groups: [ExerciseGroup] }
        let response: Response = try await request(path: "exercise-groups")
        return response.exercise_groups
    }

    func createExerciseGroup(name: String) async throws -> ExerciseGroup {
        struct Body: Encodable { let name: String }
        struct Response: Decodable { let exercise_group: ExerciseGroup }
        let response: Response = try await request(path: "exercise-groups", method: "POST", body: Body(name: name))
        return response.exercise_group
    }

    func updateExerciseGroup(id: String, name: String? = nil, position: Int? = nil) async throws -> ExerciseGroup {
        struct Body: Encodable { let id: String; let name: String?; let position: Int? }
        struct Response: Decodable { let exercise_group: ExerciseGroup }
        let response: Response = try await request(
            path: "exercise-groups", method: "PUT",
            body: Body(id: id, name: name, position: position)
        )
        return response.exercise_group
    }

    func deleteExerciseGroup(id: String) async throws {
        try await requestNoContent(path: "exercise-groups/\(id)", method: "DELETE")
    }

    // MARK: - Workout Plans

    func fetchWorkoutPlans() async throws -> [WorkoutPlan] {
        struct Response: Decodable { let plans: [WorkoutPlan] }
        let response: Response = try await request(path: "workout-plans")
        return response.plans
    }

    func createWorkoutPlan(name: String, exercises: [PlanExerciseInput]) async throws -> WorkoutPlan {
        struct Body: Encodable { let name: String; let exercises: [PlanExerciseInput] }
        struct Response: Decodable { let plan: WorkoutPlan }
        let response: Response = try await request(path: "workout-plans", method: "POST", body: Body(name: name, exercises: exercises))
        return response.plan
    }

    /// `name`/`exercises` stay optional so a reorder (`position` only) doesn't need to
    /// resend the plan's contents — mirrors `updateExerciseGroup`'s partial-update shape.
    func updateWorkoutPlan(id: String, name: String? = nil, exercises: [PlanExerciseInput]? = nil, position: Int? = nil) async throws -> WorkoutPlan {
        struct Body: Encodable { let id: String; let name: String?; let exercises: [PlanExerciseInput]?; let position: Int? }
        struct Response: Decodable { let plan: WorkoutPlan }
        let response: Response = try await request(
            path: "workout-plans", method: "PUT",
            body: Body(id: id, name: name, exercises: exercises, position: position)
        )
        return response.plan
    }

    func deleteWorkoutPlan(id: String) async throws {
        try await requestNoContent(path: "workout-plans/\(id)", method: "DELETE")
    }

    // MARK: - Workout Sessions

    func fetchWorkoutSessions() async throws -> [WorkoutSession] {
        struct Response: Decodable { let sessions: [WorkoutSession] }
        let response: Response = try await request(path: "workout-sessions")
        return response.sessions
    }

    func fetchActiveSession() async throws -> WorkoutSession? {
        struct Response: Decodable { let session: WorkoutSession? }
        do {
            let response: Response = try await request(path: "workout-sessions/active")
            return response.session
        } catch APIError.server(let status, _) where status == 404 {
            return nil
        }
    }

    func startSession(planId: String) async throws -> WorkoutSession {
        struct Body: Encodable { let plan_id: String }
        struct Response: Decodable { let session: WorkoutSession }
        let response: Response = try await request(path: "workout-sessions", method: "POST", body: Body(plan_id: planId))
        return response.session
    }

    func updateSessionSets(id: String, sets: [SessionSetInput], capturedAt: String? = nil, completedAt: String? = nil) async throws -> WorkoutSession {
        struct Body: Encodable { let sets: [SessionSetInput]; let captured_at: String?; let completed_at: String? }
        struct Response: Decodable { let session: WorkoutSession }
        let response: Response = try await request(
            path: "workout-sessions/\(id)", method: "PUT",
            body: Body(sets: sets, captured_at: capturedAt, completed_at: completedAt)
        )
        return response.session
    }

    func completeSession(id: String) async throws -> WorkoutSession {
        struct Response: Decodable { let session: WorkoutSession }
        let response: Response = try await request(path: "workout-sessions/\(id)", method: "PATCH")
        return response.session
    }

    func deleteSession(id: String) async throws {
        try await requestNoContent(path: "workout-sessions/\(id)", method: "DELETE")
    }

    // MARK: - Measurements

    func fetchMeasurements() async throws -> [Measurement] {
        struct Response: Decodable { let measurements: [Measurement] }
        let response: Response = try await request(path: "measurements")
        return response.measurements
    }

    func createMeasurement(weightKg: Double, bodyFatPercent: Double?, note: String?) async throws -> Measurement {
        struct Body: Encodable { let weight_kg: Double; let body_fat_percent: Double?; let note: String? }
        struct Response: Decodable { let measurement: Measurement }
        let response: Response = try await request(path: "measurements", method: "POST", body: Body(weight_kg: weightKg, body_fat_percent: bodyFatPercent, note: note))
        return response.measurement
    }

    func updateMeasurement(id: String, weightKg: Double, bodyFatPercent: Double?, note: String?) async throws -> Measurement {
        struct Body: Encodable { let id: String; let weight_kg: Double; let body_fat_percent: Double?; let note: String? }
        struct Response: Decodable { let measurement: Measurement }
        let response: Response = try await request(path: "measurements", method: "PUT", body: Body(id: id, weight_kg: weightKg, body_fat_percent: bodyFatPercent, note: note))
        return response.measurement
    }

    func deleteMeasurement(id: String) async throws {
        try await requestNoContent(path: "measurements/\(id)", method: "DELETE")
    }
}

struct EmptyResponse: Decodable {}
