import ActivityKit
import Foundation

/// Starts/ends the Lock Screen + Dynamic Island Live Activity that mirrors the
/// in-progress workout session. The activity is local-only (`pushType: nil`)
/// — no push entitlement needed — and its UI lives in the forgrWidget
/// extension target; this just drives the ActivityKit lifecycle.
@MainActor
enum LiveActivityManager {
    static func start(planName: String, startDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Don't stack a duplicate on top of one that's already running for a
        // resumed session (e.g. the app relaunched mid-workout).
        guard Activity<SessionActivityAttributes>.activities.isEmpty else { return }

        let attributes = SessionActivityAttributes(planName: planName, startDate: startDate)
        let content = ActivityContent(state: SessionActivityAttributes.ContentState(), staleDate: nil)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    static func end() {
        Task {
            for activity in Activity<SessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
