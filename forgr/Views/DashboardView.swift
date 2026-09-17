import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: FitnessStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: TabRouter
    @State private var showingLogoutConfirm = false
    @State private var showingAddMeasurement = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
                        recentSessionsCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("forgr")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log Out", role: .destructive) { showingLogoutConfirm = true }
                }
            }
            .alert("Log Out?", isPresented: $showingLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Log Out", role: .destructive) { auth.logout() }
            } message: {
                Text("You'll need to sign in again to access your data.")
            }
            .sheet(isPresented: $showingAddMeasurement) {
                MeasurementFormView(measurement: nil)
            }
            .refreshable { await store.loadAll() }
        }
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            StatFigure(value: "\(store.plans.count)", label: "Plans")
            StatFigure(value: "\(completedSessionsCount)", label: "Sessions")
            StatFigure(value: latestWeightText, label: "Weight")
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
                Text("Activity").font(.headline)
                Spacer()
                NavigationLink {
                    WorkoutActivityYearView(sessions: store.sessions)
                } label: {
                    HStack(spacing: 4) {
                        Text("Full Year")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
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
                Text("Progress").font(.headline)
                Spacer()
                Button {
                    showingAddMeasurement = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }

            if store.measurements.isEmpty {
                Text("No measurements yet. Log your weight to start tracking progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.measurements.prefix(3)) { measurement in
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
                    }
                }

                NavigationLink {
                    MeasurementsView()
                } label: {
                    HStack {
                        Text("See All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .cardStyle()
    }

    private var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions").font(.headline)
            if store.sessions.isEmpty {
                Text("No sessions logged yet. Start one from the Session tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.sessions.prefix(5)) { session in
                    Button {
                        router.selection = .session
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.plan_name).font(.subheadline.weight(.medium))
                                Text(DateFormatting.displayString(from: session.captured_at))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Badge(text: session.status == .completed ? "Done" : "Active",
                                  systemImage: session.status == .completed ? "checkmark.circle.fill" : "stopwatch.fill")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
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
}
