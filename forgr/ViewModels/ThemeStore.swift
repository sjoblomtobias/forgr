import SwiftUI
import Combine

/// The "kind of data" a screen or element represents — not tied 1:1 to a tab
/// (Measurements is reached from Home, but is its own domain). Purely a lookup
/// key into the pastel palette; see `Components.swift` for the actual
/// `Color.domain...` asset colors.
enum DataDomain {
    case home, exercises, plans, session, measurements

    fileprivate var pastelColor: Color {
        switch self {
        case .home: .domainHome
        case .exercises: .domainExercises
        case .plans: .domainPlans
        case .session: .domainSession
        case .measurements: .domainMeasurements
        }
    }
}

/// `standard` is how the app looked before per-domain coloring existed — every
/// accent-styled element uses the single app-wide `AccentColor` asset, same as
/// forms/auth screens still do today. `colorful` is the pastel, per-data-domain
/// palette. Both are offered as an in-app toggle (see `ThemeStore`) so real
/// usage can settle which one users actually prefer, rather than guessing.
enum AppTheme: String, CaseIterable, Identifiable {
    case standard = "Default"
    case colorful = "Colorful"

    var id: String { rawValue }

    func color(for domain: DataDomain) -> Color {
        switch self {
        case .standard: .accentColor
        case .colorful: domain.pastelColor
        }
    }
}

/// Local-only preference — deliberately `UserDefaults`, not synced through the
/// backend. This is an experiment (see if people prefer `colorful` over
/// `standard`), not an account setting, so it stays per-device.
@MainActor
final class ThemeStore: ObservableObject {
    private static let storageKey = "appTheme"

    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        theme = stored.flatMap(AppTheme.init(rawValue:)) ?? .standard
    }
}
