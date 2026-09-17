import ActivityKit
import Foundation

/// Drives the Live Activity shown on the Lock Screen / Dynamic Island while a
/// workout session is in progress. This file is compiled into both the app
/// target and the widget extension target (kept as two identical copies,
/// `forgr/Models/SessionActivityAttributes.swift` and
/// `forgrWidget/SessionActivityAttributes.swift`) — ActivityKit matches
/// activities structurally, not by module, so both sides just need to agree
/// on this shape.
nonisolated struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    let planName: String
    let startDate: Date
}
