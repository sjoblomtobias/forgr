import Foundation
import Combine

enum AppTab: Hashable {
    case home, exercises, plans, session

    /// The data domain this tab represents — resolved to an actual `Color` via
    /// `themeStore.theme.color(for:)` (see `ThemeStore.swift`), since whether
    /// that's the single app accent or this domain's own pastel depends on the
    /// user's chosen theme, not the tab alone.
    var domain: DataDomain {
        switch self {
        case .home: .home
        case .exercises: .exercises
        case .plans: .plans
        case .session: .session
        }
    }
}

@MainActor
final class TabRouter: ObservableObject {
    @Published var selection: AppTab = .home
}
