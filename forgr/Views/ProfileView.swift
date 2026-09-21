import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingChangePassword = false
    @State private var showingLogoutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.username ?? "Unknown")
                                .font(.headline)
                            Text("datavetenskap.com")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Theme", selection: $themeStore.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Appearance", systemImage: "paintpalette.fill")
                } footer: {
                    Text("Colorful gives each kind of data its own color throughout the app. This is saved on this device only.")
                }

                Section {
                    Button {
                        showingChangePassword = true
                    } label: {
                        Label("Change Password", systemImage: "lock.rotation")
                    }
                }

                Section {
                    DestructiveButton(title: "Log Out") { showingLogoutConfirm = true }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingChangePassword) {
                ChangePasswordView()
            }
            .alert("Log Out?", isPresented: $showingLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Log Out", role: .destructive) {
                    auth.logout()
                    dismiss()
                }
            } message: {
                Text("You'll need to sign in again to access your data.")
            }
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var didSave = false
    @FocusState private var focusedField: Field?

    enum Field { case current, new, confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Password") {
                    SecureField("Current Password", text: $currentPassword)
                        .textContentType(.password)
                        .focused($focusedField, equals: .current)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .new }
                }

                Section("New Password") {
                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .new)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirm }

                    if !newPassword.isEmpty && !isNewPasswordValid {
                        Text("Password must be 8–72 characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SecureField("Confirm New Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }

                    if !confirmPassword.isEmpty && !isConfirmValid {
                        Text("Passwords don't match.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = auth.changePasswordError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if didSave {
                    Section {
                        Label("Password updated.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if auth.isChangingPassword {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await submit() } }
                            .disabled(!canSubmit)
                    }
                }
            }
            .onAppear { focusedField = .current }
        }
    }

    private var isNewPasswordValid: Bool {
        (8...72).contains(newPassword.count)
    }

    private var isConfirmValid: Bool {
        !confirmPassword.isEmpty && confirmPassword == newPassword
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty && isNewPasswordValid && isConfirmValid
    }

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        let success = await auth.changePassword(currentPassword: currentPassword, newPassword: newPassword)
        if success {
            didSave = true
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthStore())
        .environmentObject(ThemeStore())
}
