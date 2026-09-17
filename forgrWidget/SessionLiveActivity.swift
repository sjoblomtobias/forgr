import ActivityKit
import WidgetKit
import SwiftUI

struct SessionLiveActivity: Widget {
    /// Tapping the activity anywhere (Lock Screen banner, or the compact/minimal
    /// Dynamic Island) opens the app straight to this URL; `forgrApp` routes it
    /// to the Session tab via `onOpenURL`.
    private let sessionURL = URL(string: "forgr://session")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(sessionURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startDate...Date.distantFuture, countsDown: false)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Color("AccentColor"))
                        .frame(width: 64, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: sessionURL ?? URL(string: "forgr://")!) {
                        Text(context.attributes.planName)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            } compactLeading: {
                // Timer only, no icon, kept to just this one side (nothing in
                // compactTrailing) so the Island can merge with another app's Live
                // Activity (e.g. Spotify) on the other side instead of us claiming both.
                Text(timerInterval: context.attributes.startDate...Date.distantFuture, countsDown: false)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color("AccentColor"))
                    .frame(width: 42, alignment: .center)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                // This is what actually renders whenever another app (e.g. Spotify's
                // Now Playing) occupies the compact regions — not compactLeading.
                Text(timerInterval: context.attributes.startDate...Date.distantFuture, countsDown: false)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color("AccentColor"))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .widgetURL(sessionURL)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "stopwatch.fill")
                .font(.title2)
                .foregroundStyle(Color("AccentColor"))

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.planName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Workout in progress")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Text(timerInterval: context.attributes.startDate...Date.distantFuture, countsDown: false)
                .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
    }
}

private extension SessionActivityAttributes {
    static var preview: SessionActivityAttributes {
        SessionActivityAttributes(planName: "Push Day", startDate: .now.addingTimeInterval(-620))
    }
}

private extension SessionActivityAttributes.ContentState {
    static var preview: SessionActivityAttributes.ContentState { SessionActivityAttributes.ContentState() }
}

#Preview("Lock Screen", as: .content, using: SessionActivityAttributes.preview) {
    SessionLiveActivity()
} contentStates: {
    SessionActivityAttributes.ContentState.preview
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: SessionActivityAttributes.preview) {
    SessionLiveActivity()
} contentStates: {
    SessionActivityAttributes.ContentState.preview
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: SessionActivityAttributes.preview) {
    SessionLiveActivity()
} contentStates: {
    SessionActivityAttributes.ContentState.preview
}
