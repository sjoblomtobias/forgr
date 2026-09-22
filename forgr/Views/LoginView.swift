import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    enum Field { case username, password }

    var body: some View {
        NavigationStack {
            loginContent
        }
    }

    private var loginContent: some View {
        VStack(spacing: 28) {
            Spacer()

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
                Text("Sign in to your datavetenskap.com account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
                    .fieldIcon("lock.fill")
            }
            .padding(.horizontal, 24)

            if let error = auth.loginError {
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
                    if auth.isLoggingIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Log In")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .background(canSubmit ? Color.accentColor : Color.accentColor.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .disabled(!canSubmit || auth.isLoggingIn)
            .padding(.horizontal, 24)

            NavigationLink {
                RegisterView()
            } label: {
                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .foregroundStyle(Color(.lightGray))
                    Text("Create one")
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
            }
            .font(.subheadline)

            Spacer()
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        await auth.login(username: username, password: password)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthStore())
}
