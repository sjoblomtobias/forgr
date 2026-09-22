import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image.appIcon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 6) {
                        Text("forgr")
                            .font(.title2.bold())
                        Badge(text: "Beta", systemImage: "hammer.fill")
                    }

                    Text("Build plans, log every set live from your Lock Screen, and watch a year of training stack up on one screen — the native iPhone tracker for your workouts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)

            Section {
                Text("forgr signs in with your datavetenskap.com account — you can create one right from the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LinkRow(title: "Privacy Policy", url: "https://datavetenskap.com/forgr/privacy")
                LinkRow(title: "Terms of Service", url: "https://datavetenskap.com/legal/terms")
                LinkRow(title: "Data Deletion", url: "https://datavetenskap.com/legal/dataDeletion")
                LinkRow(title: "Cookie Policy", url: "https://datavetenskap.com/legal/cookies")
            } header: {
                Text("Legal")
            } footer: {
                Text("forgr's Privacy Policy covers what's specific to the app; your account, data, and cookies are governed by datavetenskap.com's general policies above.")
            }

            Section("Support") {
                LinkRow(title: "Support & FAQ", url: "https://datavetenskap.com/forgr/support")
                LinkRow(title: "Contact", url: "mailto:root@datavetenskap.com")
                LinkRow(title: "datavetenskap.com", url: "https://datavetenskap.com")
            }

            Section {
                Text("© 2026 datavetenskap")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

/// A `Form` row that opens an external URL (site pages, mail composer) — the trailing
/// `arrow.up.right` (rather than the app's usual `chevron.right`) signals it leaves the
/// app instead of pushing another screen.
private struct LinkRow: View {
    let title: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
