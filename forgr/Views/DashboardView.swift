import SwiftUI

/// Non-data-driven pushes off the Dashboard — needs a stable `Hashable` value (rather
/// than a closure-style `NavigationLink`) so it plays nicely with the `WorkoutSession`
/// destination also registered on this stack. A closure-style link here previously
/// got its "active" push state corrupted whenever `historyCard` recomputed while a
/// session was pushed on top of it (e.g. `SessionDetailView`'s own background
/// `refreshSessions()` call, which this same stack's `store` is subscribed to) —
/// producing a duplicate History push and a broken back-stack.
enum DashboardRoute: Hashable {
    case history
    case measurements
    case about
}

struct DashboardView: View {
    @EnvironmentObject private var store: FitnessStore
    @EnvironmentObject private var router: TabRouter
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var showingProfile = false
    @State private var showingAddMeasurement = false
    @State private var sessionToDelete: WorkoutSession?

    /// The Dashboard mixes domains on one screen (plans/sessions/measurements
    /// side by side), so unlike a single-domain tab it can't lean on one ambient
    /// `.pageTint` — each element below asks for its own domain's color directly.
    private func color(for domain: DataDomain) -> Color {
        themeStore.theme.color(for: domain)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.isLoading && !store.hasLoadedOnce {
                        SkeletonCard(lines: 1)
                        SkeletonCard()
                        SkeletonCard()
                    } else {
                        statsCard

                        if let session = store.activeSession {
                            ActiveSessionCard(session: session) { router.selection = .session }
                        }

                        activityCard
                        progressCard
                        historyCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            // A custom header instead of `.navigationTitle`/`.toolbar` — the
            // system large title shrinks into a small centered one as soon as
            // the content scrolls (a jarring fade), and a `ToolbarItem` doesn't
            // have room for `.largeTitle`-sized text (clipped) and picks up
            // iOS 26's automatic glass/button chrome on arbitrary content. A
            // `safeAreaInset` header sits above the scrollable content, at a
            // fixed size and position, immune to both problems.
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    NavigationLink(value: DashboardRoute.about) {
                        Text("forgr")
                            .font(.largeTitle.bold())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        showingProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WorkoutSession.self) { session in
                SessionDetailView(sessionId: session.id)
                    .tint(color(for: .session))
                    .environment(\.pageTint, color(for: .session))
            }
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .history: HistoryListView().tint(color(for: .session)).environment(\.pageTint, color(for: .session))
                case .measurements: MeasurementsView().tint(color(for: .measurements)).environment(\.pageTint, color(for: .measurements))
                case .about: AboutView()
                }
            }
            .navigationDestination(for: Measurement.self) { measurement in
                MeasurementDetailView(measurement: measurement)
                    .tint(color(for: .measurements))
                    .environment(\.pageTint, color(for: .measurements))
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingAddMeasurement) {
                MeasurementFormView(measurement: nil)
                    .tint(color(for: .measurements))
                    .environment(\.pageTint, color(for: .measurements))
            }
            .deleteConfirmation($sessionToDelete, title: "Delete Session?") { session in
                store.deleteSession(session)
            }
            .refreshable { await store.loadAll() }
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            StatFigure(value: "\(store.plans.count)", label: "Plans", systemImage: "list.clipboard.fill", color: color(for: .plans))
            StatFigure(value: "\(completedSessionsCount)", label: "Sessions", systemImage: "checkmark.circle.fill", color: color(for: .session))
            StatFigure(value: latestWeightText, label: "Weight", systemImage: "scalemass.fill", color: color(for: .measurements))
        }
        .cardStyle()
    }

    private var completedSessionsCount: Int {
        store.sessions.filter { $0.status == .completed }.count
    }

    private var latestWeightText: String {
        guard let latest = store.measurements.first else { return "–" }
        return String(format: "%.1f", latest.weight_kg)
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity", systemImage: "calendar").font(.headline)
                Spacer()
                NavigationLink {
                    WorkoutActivityYearView(sessions: store.sessions)
                } label: {
                    HStack(spacing: 4) {
                        Text("Full Year")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color(for: .session))
                }
            }
            MonthActivityGrid(sessions: store.sessions)
            Text("\(monthSessionsCount) sessions this month")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var monthSessionsCount: Int {
        let calendar = Calendar.current
        let now = Date()
        return store.sessions.filter { session in
            guard session.status == .completed, let date = DateFormatting.date(from: session.captured_at) else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }.count
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Measurements", systemImage: "scalemass.fill").font(.headline)
                Spacer()
                Button {
                    showingAddMeasurement = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .foregroundStyle(color(for: .measurements))
            }

            if store.measurements.isEmpty {
                Text("No measurements yet. Log your weight to start tracking progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.measurements.prefix(3)) { measurement in
                    NavigationLink(value: measurement) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(String(format: "%.1f", measurement.weight_kg)) kg")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                Text(DateFormatting.displayString(from: measurement.created_at))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let bodyFat = measurement.body_fat_percent {
                                Badge(text: "\(String(format: "%.1f", bodyFat))%", systemImage: "percent")
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink(value: DashboardRoute.measurements) {
                    HStack {
                        Text("See All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color(for: .measurements))
                }
            }
        }
        .cardStyle()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("History", systemImage: "clock.arrow.circlepath").font(.headline)
            if completedSessions.isEmpty {
                Text("No sessions logged yet. Start one from the Session tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(completedSessions.prefix(3)) { session in
                    NavigationLink(value: session) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.plan_name).font(.subheadline.weight(.medium))
                                HStack(spacing: 4) {
                                    Text(DateFormatting.displayString(from: session.captured_at))
                                    if let completedAt = session.completed_at,
                                       let duration = DateFormatting.durationString(from: session.captured_at, to: completedAt) {
                                        Text("·")
                                        Text(duration)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            sessionToDelete = session
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                NavigationLink(value: DashboardRoute.history) {
                    HStack {
                        Text("See All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(color(for: .session))
                }
            }
        }
        .cardStyle()
    }

    private var completedSessions: [WorkoutSession] {
        store.sessions.filter { $0.status == .completed }
    }
}

struct WeightPoint: Identifiable {
    var id: Date { day }
    let day: Date
    let weight: Double
}

struct HistoryListView: View {
    @EnvironmentObject private var store: FitnessStore
    @State private var sessionToDelete: WorkoutSession?

    private var sessions: [WorkoutSession] {
        store.sessions.filter { $0.status == .completed }
    }

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoadedOnce {
                SkeletonList()
            } else if sessions.isEmpty {
                EmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "No History Yet",
                    subtitle: "Completed workouts will show up here."
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink(value: session) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.plan_name).font(.subheadline.weight(.medium))
                                HStack(spacing: 4) {
                                    Text(DateFormatting.displayString(from: session.captured_at))
                                    if let completedAt = session.completed_at,
                                       let duration = DateFormatting.durationString(from: session.captured_at, to: completedAt) {
                                        Text("·")
                                        Text(duration)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                sessionToDelete = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .refreshable { await store.refreshSessions() }
            }
        }
        .navigationTitle("History")
        .deleteConfirmation($sessionToDelete, title: "Delete Session?") { session in
            store.deleteSession(session)
        }
        .task { await store.refreshSessions() }
    }
}

struct ActiveSessionCard: View {
    let session: WorkoutSession
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "stopwatch.fill")
                        .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                    Text("Workout in Progress")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                Text(session.plan_name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(session.sets.count) sets logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DashboardView()
        .environmentObject(FitnessStore())
        .environmentObject(AuthStore())
        .environmentObject(TabRouter())
        .environmentObject(ThemeStore())
}
