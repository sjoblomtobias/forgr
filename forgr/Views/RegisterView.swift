import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var inviteCode: String
    @State private var agreedToTerms = false
    @FocusState private var focusedField: Field?

    enum Field { case username, password, confirmPassword, inviteCode }

    /// `inviteCode` pre-fills the field, e.g. from a `forgr://invite?code=...` deep link.
    init(inviteCode: String = "") {
        _inviteCode = State(initialValue: Self.sanitizeInviteCode(inviteCode))
    }

    /// Invite codes are 6 chars, A-Z0-9 — normalize rather than rejecting input outright.
    private static func sanitizeInviteCode(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image.appIcon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Image.datavetenskapLogo
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    Text("Create your datavetenskap.com account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Registration is invite-only — enter the code you were given.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(spacing: 14) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .fieldIcon("person.fill")

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmPassword }
                        .fieldIcon("lock.fill")

                    if !password.isEmpty && !isPasswordValid {
                        Text("Password must be 8–72 characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .inviteCode }
                        .fieldIcon("lock.fill")

                    if !confirmPassword.isEmpty && !isConfirmPasswordValid {
                        Text("Passwords don't match.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    TextField("Invite Code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .inviteCode)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .onChange(of: inviteCode) { _, newValue in
                            inviteCode = Self.sanitizeInviteCode(newValue)
                        }
                        .fieldIcon("ticket.fill")
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("I agree to the Terms of Service and Privacy Policy", isOn: $agreedToTerms)
                        .font(.subheadline)

                    HStack(spacing: 4) {
                        Text("Read our")
                            .foregroundStyle(.secondary)
                        Link("Terms of Service", destination: URL(string: "https://datavetenskap.com/legal/terms")!)
                        Text("and")
                            .foregroundStyle(.secondary)
                        Link("Privacy Policy", destination: URL(string: "https://datavetenskap.com/legal/privacy")!)
                    }
                    .font(.footnote)
                }
                .padding(.horizontal, 24)

                if let error = auth.registerError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if auth.isRegistering {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create Account")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .background(canSubmit ? Color.accentColor : Color.accentColor.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
                .disabled(!canSubmit || auth.isRegistering)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }

    private var isUsernameValid: Bool {
        (3...20).contains(username.trimmingCharacters(in: .whitespaces).count)
    }

    private var isPasswordValid: Bool {
        (8...72).contains(password.count)
    }

    private var isConfirmPasswordValid: Bool {
        !confirmPassword.isEmpty && confirmPassword == password
    }

    private var isInviteCodeValid: Bool {
        inviteCode.count == 6
    }

    private var canSubmit: Bool {
        isUsernameValid && isPasswordValid && isConfirmPasswordValid && isInviteCodeValid && agreedToTerms
    }

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        await auth.register(username: username, password: password, inviteCode: inviteCode)
    }
}

#Preview {
    NavigationStack {
        RegisterView()
    }
    .environmentObject(AuthStore())
}
