import SwiftUI

struct RootView: View {
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: FitnessStore
    @State private var showingOfflineAlert = false

    let onRestart: () -> Void

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView()
                    .environmentObject(store)
                    .task {
                        // SplashGateView already ran the initial load; only fetch here
                        // for a session that starts mid-run (e.g. a fresh login).
                        if !store.hasLoadedOnce { await store.loadAll() }
                    }
            } else {
                LoginView()
            }
        }
        .environmentObject(auth)
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated { store.clearCache() }
        }
        .onChange(of: network.isConnected) { _, isConnected in
            // Only ever opens the alert on a real drop — regaining connectivity in the
            // background never auto-dismisses it; the user must tap Retry themselves.
            if isConnected == false { showingOfflineAlert = true }
        }
        .alert("No Internet Connection", isPresented: $showingOfflineAlert) {
            Button("Retry") { onRestart() }
        } message: {
            Text("This app requires an internet connection. Please check your connection and try again.")
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var store: FitnessStore
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var isShowingError = false

    private func color(for tab: AppTab) -> Color {
        themeStore.theme.color(for: tab.domain)
    }

    var body: some View {
        TabView(selection: $router.selection) {
            DashboardView()
                .tint(color(for: .home))
                .environment(\.pageTint, color(for: .home))
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            ExercisesView()
                .tint(color(for: .exercises))
                .environment(\.pageTint, color(for: .exercises))
                .tabItem { Label("Exercises", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.exercises)
            PlansView()
                .tint(color(for: .plans))
                .environment(\.pageTint, color(for: .plans))
                .tabItem { Label("Plans", systemImage: "list.clipboard.fill") }
                .tag(AppTab.plans)
            SessionTabView()
                .tint(color(for: .session))
                .environment(\.pageTint, color(for: .session))
                .tabItem { Label("Session", systemImage: "stopwatch.fill") }
                .tag(AppTab.session)
        }
        // Mutations apply locally and sync in the background (see FitnessStore); if a
        // sync call ends up failing, this is where that surfaces — after the fact.
        //
        // `isPresented` is a plain local @State rather than a computed Binding that
        // writes into `store.errorMessage` — SwiftUI invokes that binding's setter
        // as part of the alert's own dismiss transaction, and mutating an
        // @EnvironmentObject from inside it triggered "Publishing changes from
        // within view updates". The store is only cleared from the Button action.
        .onChange(of: store.errorMessage) { _, newValue in
            isShowingError = newValue != nil
        }
        .alert(
            "Something Went Wrong",
            isPresented: $isShowingError,
            presenting: store.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }
}

#Preview {
    RootView(onRestart: {})
        .environmentObject(NetworkMonitor())
        .environmentObject(AuthStore())
        .environmentObject(FitnessStore())
        .environmentObject(TabRouter())
        .environmentObject(ThemeStore())
}
