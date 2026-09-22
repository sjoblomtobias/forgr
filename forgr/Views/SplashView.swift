import SwiftUI

/// Cold-launch gate: blocks entry into the app until connectivity is confirmed.
/// Never auto-advances once it's shown the offline state — even if connectivity
/// silently returns in the background, the user must tap Retry to proceed.
///
/// Also owns the session check + initial data load, running them alongside a
/// short minimum-duration timer so the spinner doesn't just flash, and the app
/// already has a head start on fetching data by the time it's shown.
struct SplashGateView: View {
    @StateObject private var network = NetworkMonitor()
    @StateObject private var auth = AuthStore()
    @StateObject private var store = FitnessStore()
    @StateObject private var router = TabRouter()
    @StateObject private var themeStore = ThemeStore()
    @State private var isOffline = false
    @State private var isReady = false
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
                    .environmentObject(themeStore)
            } else {
                SplashView(isOffline: isOffline, onRetry: attemptProceed)
            }
        }
        .onAppear { attemptProceed() }
        .onOpenURL { url in
            switch url.host {
            case "session":
                // Tapping the workout session's Live Activity opens this. If the app is
                // already up, jump tabs immediately; if we're still cold-launching,
                // queue it so beginLoading() lands on it instead of the Home default.
                if isReady {
                    router.selection = .session
                } else {
                    pendingDeepLinkTab = .session
                }
            default:
                break
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
        Task {
            async let sessionCheck: Void = auth.checkExistingSession()
            // Only prefetch if we actually have a session — otherwise every request
            // fails immediately on missing auth, which would wrongly mark the store
            // as "loaded" before the user has ever logged in.
            async let dataLoad: Void = loadDataIfAuthenticated()
            // Keeps the spinner on screen long enough to read as intentional even
            // when auth/data resolve almost instantly (e.g. a warm cache).
            async let minDuration = try? Task.sleep(for: .milliseconds(600))
            _ = await (sessionCheck, dataLoad, minDuration)
            // Once loading finishes, land on the Home tab — unless a deep link
            // (e.g. tapping the session Live Activity) arrived while loading.
            router.selection = pendingDeepLinkTab ?? .home
            isReady = true
        }
    }

    private func loadDataIfAuthenticated() async {
        if auth.isAuthenticated { await store.loadAll() }
    }
}

struct SplashView: View {
    let isOffline: Bool
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
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // An overlay (rather than a slot in the VStack above) puts this at the
        // screen's true vertical center regardless of how much space the
        // branding block above ends up taking.
        .overlay {
            if !isOffline {
                SpinningShapesView()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// Four filled shapes evenly spaced on a ring, the whole ring orbiting around
/// its center — the splash screen's substitute for a conventional spinner.
/// Each shape carries its own counter-rotation (`-orbitAngle`) to cancel out
/// the tilt it would otherwise inherit from the outer ring's rotation, so the
/// shapes themselves stay upright and only their position travels in a circle.
struct SpinningShapesView: View {
    private static let symbols = ["circle.fill", "triangle.fill", "square.fill", "pentagon.fill"]
    private let radius: CGFloat = 14
    private let shapeSize: CGFloat = 11

    @State private var orbitAngle = Angle.zero

    var body: some View {
        ZStack {
            ForEach(Array(Self.symbols.enumerated()), id: \.offset) { index, symbol in
                let placement = Angle.degrees(Double(index) / Double(Self.symbols.count) * 360)
                Image(systemName: symbol)
                    .font(.system(size: shapeSize))
                    .foregroundStyle(.white)
                    .rotationEffect(-orbitAngle)
                    .offset(
                        x: radius * CGFloat(cos(placement.radians)),
                        y: radius * CGFloat(sin(placement.radians))
                    )
            }
        }
        .rotationEffect(orbitAngle)
        .frame(width: (radius + shapeSize) * 2, height: (radius + shapeSize) * 2)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                orbitAngle = .degrees(360)
            }
        }
    }
}

#Preview("Loading") {
    SplashView(isOffline: false, onRetry: {})
}

#Preview("Offline") {
    SplashView(isOffline: true, onRetry: {})
}
