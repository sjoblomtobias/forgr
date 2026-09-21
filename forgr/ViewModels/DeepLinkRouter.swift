import Foundation
import Combine

/// Holds a deep-linked invite code (from `forgr://invite?code=...`) until the
/// unauthenticated Login flow is on screen and ready to consume it by pushing
/// straight into Register with the code pre-filled.
@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var pendingInviteCode: String?
}
