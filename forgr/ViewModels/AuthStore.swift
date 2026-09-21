import Foundation
import Combine

@MainActor
final class AuthStore: ObservableObject {
    // Starts optimistically true if a token is already stored, so the app can render
    // straight into the main UI instead of blocking on a network round-trip at launch.
    @Published var isAuthenticated: Bool
    @Published var username: String?
    @Published var loginError: String?
    @Published var isLoggingIn: Bool = false
    @Published var registerError: String?
    @Published var isRegistering: Bool = false
    @Published var changePasswordError: String?
    @Published var isChangingPassword: Bool = false

    private let client = APIClient.shared

    init() {
        isAuthenticated = client.isAuthenticated
        username = client.username
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
            self.username = client.username
            isAuthenticated = true
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() {
        client.logout()
        username = nil
        isAuthenticated = false
    }

    @discardableResult
    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        changePasswordError = nil
        isChangingPassword = true
        defer { isChangingPassword = false }
        do {
            try await client.changePassword(currentPassword: currentPassword, newPassword: newPassword)
            username = client.username
            return true
        } catch {
            changePasswordError = error.localizedDescription
            return false
        }
    }

    /// Registration returns no token, so a successful register is chained straight into
    /// a login to establish the session. Returns whether the whole flow succeeded, so
    /// the view can dismiss only on success.
    @discardableResult
    func register(username: String, password: String, inviteCode: String) async -> Bool {
        registerError = nil
        isRegistering = true
        defer { isRegistering = false }
        do {
            try await client.register(username: username, password: password, inviteCode: inviteCode)
            try await client.login(username: username, password: password)
            self.username = client.username
            isAuthenticated = true
            return true
        } catch {
            registerError = error.localizedDescription
            return false
        }
    }
}
