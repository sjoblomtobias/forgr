import SwiftUI

struct SessionTabView: View {
    @EnvironmentObject private var store: FitnessStore
    @EnvironmentObject private var router: TabRouter
    @State private var showingHistory = false
    @State private var sessionToDelete: WorkoutSession?

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && !store.hasLoadedOnce {
                    ScrollView {
                        VStack(spacing: 12) {
                            SkeletonCard(lines: 2)
                            SkeletonCard(lines: 2)
                            SkeletonCard(lines: 2)
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                } else if let session = store.activeSession {
                    SessionEditor(session: session)
                } else {
                    startWorkoutView
                }
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingHistory) {
                NavigationStack {
                    HistoryListView(sessions: completedSessions)
                }
            }
            .deleteConfirmation($sessionToDelete, title: "Delete Session?") { session in
                store.deleteSession(session)
            }
            .onChange(of: router.selection) { _, newSelection in
                // TabView keeps every tab's view alive, so this fires even while
                // Session isn't the visible tab — exactly when we want to catch a
                // switch onto it and re-verify history against the backend.
                if newSelection == .session {
                    Task { await store.refreshSessions() }
                }
            }
        }
    }

    private var startWorkoutView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if store.plans.isEmpty {
                    EmptyState(
                        systemImage: "stopwatch",
                        title: "No Plans Yet",
                        subtitle: "Create a workout plan in the Plans tab, then start a session from here."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Start a Workout")
                            .font(.title3.bold())
                            .padding(.horizontal)

                        VStack(spacing: 10) {
                            ForEach(store.plans) { plan in
                                Button {
                                    store.startSession(planId: plan.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(plan.name).font(.subheadline.weight(.semibold))
                                            Text("\(plan.exercises.count) exercises")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .cardStyle(cornerRadius: 16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if !completedSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("History")
                                .font(.title3.bold())
                            Spacer()
                            Button("See All") { showingHistory = true }
                                .font(.subheadline)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 10) {
                            ForEach(completedSessions.prefix(3)) { session in
                                NavigationLink {
                                    SessionDetailView(sessionId: session.id)
                                } label: {
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
                                    .cardStyle(cornerRadius: 16)
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
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var completedSessions: [WorkoutSession] {
        store.sessions.filter { $0.status == .completed }
    }
}

struct HistoryListView: View {
    @EnvironmentObject private var store: FitnessStore
    let sessions: [WorkoutSession]
    @State private var sessionToDelete: WorkoutSession?

    var body: some View {
        Group {
            if sessions.isEmpty {
                EmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "No History Yet",
                    subtitle: "Completed workouts will show up here."
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink {
                            SessionDetailView(sessionId: session.id)
                        } label: {
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
        .navigationBarTitleDisplayMode(.inline)
        .deleteConfirmation($sessionToDelete, title: "Delete Session?") { session in
            store.deleteSession(session)
        }
        .task { await store.refreshSessions() }
    }
}

#Preview {
    SessionTabView()
        .environmentObject(FitnessStore())
        .environmentObject(TabRouter())
}
