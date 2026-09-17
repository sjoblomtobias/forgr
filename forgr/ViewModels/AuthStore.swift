import Foundation
import Combine

@MainActor
final class AuthStore: ObservableObject {
    // Starts optimistically true if a token is already stored, so the app can render
    // straight into the main UI instead of blocking on a network round-trip at launch.
    @Published var isAuthenticated: Bool
    @Published var loginError: String?
    @Published var isLoggingIn: Bool = false

    private let client = APIClient.shared

    init() {
        isAuthenticated = client.isAuthenticated
    }

    /// Reconciles the optimistic session with the server in the background.
    /// Only ever revokes access (on a genuinely invalid token) — never blocks the UI,
    /// and a plain connectivity failure leaves the user logged in to retry later.
    func checkExistingSession() async {
        guard client.isAuthenticated else { return }
        do {
            try await client.verifyToken()
        } catch APIError.unauthorized {
            isAuthenticated = false
        } catch {
            // Network hiccup — stay logged in; FitnessStore's retry banner covers this.
        }
    }

    func login(username: String, password: String) async {
        loginError = nil
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            try await client.login(username: username, password: password)
            isAuthenticated = true
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() {
        client.logout()
        isAuthenticated = false
    }
}
