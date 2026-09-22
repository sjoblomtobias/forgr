import SwiftUI

struct SessionTabView: View {
    @EnvironmentObject private var store: FitnessStore
    @EnvironmentObject private var router: TabRouter
    @Environment(\.pageTint) private var pageTint

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
                        Label("Start a Workout", systemImage: "stopwatch.fill")
                            .font(.title3.bold())
                            .padding(.horizontal)

                        VStack(spacing: 10) {
                            ForEach(store.plans) { plan in
                                let isEmpty = plan.exercises.isEmpty
                                Button {
                                    store.startSession(planId: plan.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(plan.name).font(.subheadline.weight(.semibold))
                                            Text(isEmpty ? "No exercises yet" : "\(plan.exercises.count) exercises")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(isEmpty ? Color.secondary : pageTint)
                                    }
                                    .cardStyle(cornerRadius: 16)
                                }
                                .buttonStyle(.plain)
                                .disabled(isEmpty)
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
}

#Preview {
    SessionTabView()
        .environmentObject(FitnessStore())
        .environmentObject(TabRouter())
}
