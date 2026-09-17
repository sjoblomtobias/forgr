import SwiftUI

/// Cold-launch gate: blocks entry into the app until connectivity is confirmed.
/// Never auto-advances once it's shown the offline state — even if connectivity
/// silently returns in the background, the user must tap Retry to proceed.
///
/// Also owns the session check + initial data load, running them alongside a
/// short minimum-duration progress animation so the bar visibly completes and
/// the app already has a head start on fetching data by the time it's shown.
struct SplashGateView: View {
    @StateObject private var network = NetworkMonitor()
    @StateObject private var auth = AuthStore()
    @StateObject private var store = FitnessStore()
    @StateObject private var router = TabRouter()
    @State private var isOffline = false
    @State private var isReady = false
    @State private var progress: CGFloat = 0
    @State private var pendingDeepLinkTab: AppTab?

    let onRestart: () -> Void

    var body: some View {
        Group {
            if isReady {
                RootView(onRestart: onRestart)
                    .environmentObject(network)
                    .environmentObject(auth)
                    .environmentObject(store)
                    .environmentObject(router)
            } else {
                SplashView(isOffline: isOffline, progress: progress, onRetry: attemptProceed)
            }
        }
        .onAppear { attemptProceed() }
        .onOpenURL { url in
            // Tapping the workout session's Live Activity opens this. If the app is
            // already up, jump tabs immediately; if we're still cold-launching,
            // queue it so beginLoading() lands on it instead of the Home default.
            guard url.host == "session" else { return }
            if isReady {
                router.selection = .session
            } else {
                pendingDeepLinkTab = .session
            }
        }
    }

    private func attemptProceed() {
        switch network.isConnected {
        case true:
            isOffline = false
            beginLoading()
        case false:
            isOffline = true
        case nil:
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                if !isReady { attemptProceed() }
            }
        }
    }

    private func beginLoading() {
        guard !isReady else { return }
        progress = 0
        Task {
            async let sessionCheck: Void = auth.checkExistingSession()
            // Only prefetch if we actually have a session — otherwise every request
            // fails immediately on missing auth, which would wrongly mark the store
            // as "loaded" before the user has ever logged in.
            async let dataLoad: Void = loadDataIfAuthenticated()
            async let minDuration: Void = animateProgress()
            _ = await (sessionCheck, dataLoad, minDuration)
            // Once the bar hits 100%, land on the Home tab — unless a deep link
            // (e.g. tapping the session Live Activity) arrived while loading.
            router.selection = pendingDeepLinkTab ?? .home
            isReady = true
        }
    }

    private func loadDataIfAuthenticated() async {
        if auth.isAuthenticated { await store.loadAll() }
    }

    private func animateProgress() async {
        withAnimation(.easeInOut(duration: 0.6)) {
            progress = 1
        }
        try? await Task.sleep(for: .milliseconds(600))
    }
}

struct SplashView: View {
    let isOffline: Bool
    var progress: CGFloat = 0
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image.appIcon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("forgr")
                    .font(.largeTitle.bold())
            }

            Spacer()

            if isOffline {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.title)
                        .foregroundStyle(.red)
                    Text("No Internet Connection")
                        .font(.headline)
                    Text("This app requires an internet connection. Please connect and try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 32)
            } else {
                ProgressView(value: progress, total: 1)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(width: 180)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Loading") {
    SplashView(isOffline: false, progress: 0.6, onRetry: {})
}

#Preview("Offline") {
    SplashView(isOffline: true, onRetry: {})
}
