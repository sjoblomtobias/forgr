# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`forgr` is a native SwiftUI iOS app (target iOS 26.0+, iPhone only / Xcode 17). It's a client for a workout-tracking backend at `https://datavetenskap.com/api` — exercises, workout plans, logged sessions, and body measurements.

## Build & run

Open `forgr.xcodeproj` in Xcode, or from the CLI:

```bash
# List schemes/targets
xcodebuild -list -project forgr.xcodeproj

# List available simulator destinations
xcrun simctl list devices

# Build for a simulator (swap in an available device id from the list above)
xcodebuild -project forgr.xcodeproj -scheme forgr \
  -destination 'platform=iOS Simulator,id=<DEVICE_ID>' build
```

There is no `-destination 'generic/platform=iOS Simulator'` shortcut here — it resolves to an empty destination set on this machine; pass a concrete simulator `id` or `name` instead.

## Tests

Two targets: `forgrTests` (unit, Swift Testing framework) and `forgrUITests` (XCUITest). Run via Xcode's Test navigator or:

```bash
xcodebuild test -project forgr.xcodeproj -scheme forgr \
  -destination 'platform=iOS Simulator,id=<DEVICE_ID>'
```

## Architecture

MVVM with `ObservableObject` stores injected via `.environmentObject`, no external dependencies (pure SwiftUI + Foundation).

- **`forgrApp.swift` → `RootView`**: app entry point. `RootView` owns `AuthStore` and `FitnessStore` and switches between `LoginView` and `MainTabView` based on `AuthStore.isAuthenticated`. On successful auth it triggers `FitnessStore.loadAll()`.
- **`ViewModels/AuthStore.swift`**: session/login state. Wraps `APIClient` login/logout/verify calls.
- **`ViewModels/FitnessStore.swift`**: the single source of truth for app data (exercises, plans, sessions, active session, measurements). `loadAll()` fires all five fetches concurrently with `async let` and aggregates partial failures into one `errorMessage` rather than failing the whole load if one endpoint errors. Tracks `isLoading` (in-flight) and `hasLoadedOnce` (has completed at least one load) — views use `isLoading && !hasLoadedOnce` to distinguish "first load, show skeleton" from "pull-to-refresh, keep showing existing content."
- **`ViewModels/TabRouter.swift`**: trivial published tab selection (`AppTab`), lets views like the Dashboard programmatically switch tabs (e.g. tapping the active-session card jumps to the Session tab).
- **`Networking/APIClient.swift`**: single `@MainActor` singleton (`APIClient.shared`) wrapping all backend calls through one private `request<Response: Decodable>()` method. Handles bearer-token auth, 401 → clears token and throws `.unauthorized`, and maps non-2xx responses to `APIError.server` using the backend's `{message, errors}` JSON shape. Each endpoint method defines its own local `Body`/`Response` Codable structs inline rather than reusing shared DTOs.
- **`Networking/KeychainStore.swift`**: JWT persistence via Keychain (`kSecClassGenericPassword`).
- **`Models/FitnessModels.swift`**: all `Codable` domain models (`Exercise`, `WorkoutPlan`/`PlanExercise`, `ScheduledWorkout`, `WorkoutSession`/`SessionSet`, `Measurement`, `ExerciseHistorySet`). Field names are `snake_case` to match the API directly (no `CodingKeys` translation layer).
- **`Views/`**: one file per tab/feature (`DashboardView`, `ExercisesView`, `PlansView`, `SessionTabView`, `SessionDetailView`, `MeasurementsView`), plus `Components.swift` for shared UI (`cardStyle()`, `Badge`, `StatFigure`, `EmptyState`, `DestructiveButton`, skeleton placeholders, `DateFormatting`).

### Conventions worth matching

- Mutations on `FitnessStore` (`addExercise`, `startSession`, `saveSets`, etc.) each do their own try/catch and set `errorMessage` on failure — they don't route through `loadAll`'s aggregation.
- Dates from the API are ISO8601 strings; render them with `DateFormatting.displayString(from:)` / `DateFormatting.dayOnly`, don't format `Date` directly.
- Empty states use the shared `EmptyState` component; loading states (first load only) use the shared skeleton components (`SkeletonList`, `SkeletonCard`) rather than a bare `ProgressView`.
- List/card rows follow the established pattern: `HStack` with leading icon or text stack, `Spacer()`, trailing chevron/badge, wrapped in `.cardStyle()` for card-style rows or plain `List` rows for table-style ones.
