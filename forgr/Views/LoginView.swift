import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    enum Field { case username, password }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image.appIcon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("forgr")
                    .font(.largeTitle.bold())
                Text("Sign in to your account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .padding(14)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
                    .padding(14)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
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
    LoginView().environmentObject(AuthStore())
}
