import Foundation
import Combine

enum AppTab: Hashable {
    case home, exercises, plans, session
}

@MainActor
final class TabRouter: ObservableObject {
    @Published var selection: AppTab = .home
}
