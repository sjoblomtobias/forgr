import SwiftUI
import UIKit

// MARK: - App icon

extension Image {
    /// The app's actual home-screen icon (as rendered by the asset catalog / Icon
    /// Composer file), for use as a brand mark on the Login/Splash screens instead
    /// of a stand-in SF Symbol.
    static var appIcon: Image {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last,
              let uiImage = UIImage(named: name)
        else { return Image(systemName: "app.dashed") }
        return Image(uiImage: uiImage)
    }

    /// datavetenskap.com's small mark (its favicon/apple-touch-icon — the site's navbar
    /// brand itself is live text, not an image), used to badge screens that authenticate
    /// against its account system.
    static var datavetenskapLogo: Image {
        Image("DatavetenskapLogo")
    }
}

// MARK: - Data-domain colors
//
// A soft, cohesive pastel palette — one color per *kind of data*, not per
// screen. The point is recognition: the same muted mint that marks a
// measurement on the Dashboard is the same mint used throughout the
// Measurements tab, so a glance at the color says what you're looking at
// before you've read a word. `Home` is deliberately neutral (a soft sky
// blue) rather than a sixth "kind of data" — it's the aggregator, not a
// domain of its own. Defined as asset-catalog colors (matching how
// `AccentColor` itself is defined) rather than inline RGB literals, so
// they're in one place if the palette ever needs retuning — Xcode
// auto-generates `Color.domainHome`/`.domainExercises`/`.domainPlans`/
// `.domainSession`/`.domainMeasurements` from the DomainHome/etc. colorsets
// in Assets.xcassets, so there's no manual extension to maintain here.

// MARK: - Per-page tint

/// Each tab (and a couple of sub-pages reached from Home) sets this to its own
/// domain color via `.environment(\.pageTint, ...)` on its root view. Plain
/// `Color.accentColor` doesn't track `.tint(_:)` set by an ancestor — it always
/// resolves to the single app-wide asset color — so anywhere that wants to vary
/// by page reads this instead. Screens that mix domains (the Dashboard, which
/// shows plans/sessions/measurements side by side) don't rely on this single
/// ambient value — each element there reads its own `Color.domain...` directly
/// instead, since "page tint" can only ever hold one color at a time. Defaults
/// to `.accentColor` for screens (forms, auth) that intentionally stay on the
/// app's single default color.
private struct PageTintKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var pageTint: Color {
        get { self[PageTintKey.self] }
        set { self[PageTintKey.self] = newValue }
    }
}

// MARK: - Card container matching purgr's rounded-card convention

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 20) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Frosted badge (purgr's ultraThinMaterial capsule pattern)

struct Badge: View {
    let text: String
    var systemImage: String?
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Big rounded stat number (purgr's .rounded design for stat figures)

struct StatFigure: View {
    let value: String
    let label: String
    var systemImage: String?
    /// `nil` (the default) uses whatever `.pageTint` the enclosing page set.
    var color: Color?
    @Environment(\.pageTint) private var pageTint

    var body: some View {
        VStack(spacing: 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(color ?? pageTint)
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color ?? pageTint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty state (purgr's SF Symbol + gradient icon + title/subtitle)

struct EmptyState: View {
    let systemImage: String
    let title: String
    let subtitle: String
    /// `nil` (the default) derives a gradient from whatever `.pageTint` the
    /// enclosing page set, rather than the single app-wide accent color.
    var gradient: [Color]?
    @Environment(\.pageTint) private var pageTint

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: gradient ?? [pageTint, pageTint.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Leading-icon field background (login/register text fields)

private struct IconFieldBackground: ViewModifier {
    let systemName: String
    func body(content: Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func fieldIcon(_ systemName: String) -> some View {
        modifier(IconFieldBackground(systemName: systemName))
    }
}

// MARK: - Dismiss keyboard on tap outside a text field (number pads have no
// built-in "Done" key, so without this there's no way to close them)

/// Window-level tap recognizer that resigns first responder for any tap that
/// doesn't land on a text field. `cancelsTouchesInView = false` and the
/// simultaneous-recognition delegate mean it never blocks the tap it's
/// riding along with — buttons, steppers, and list rows still get their own
/// taps normally.
private final class KeyboardDismissGestureRecognizer: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = false
        addTarget(self, action: #selector(handleTap))
    }

    @objc private func handleTap() {
        (view as? UIWindow)?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UITextField)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let alreadyInstalled = window.gestureRecognizers?.contains { $0 is KeyboardDismissGestureRecognizer } ?? false
            guard !alreadyInstalled else { return }
            window.addGestureRecognizer(KeyboardDismissGestureRecognizer())
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    /// Closes the keyboard when the user taps anywhere except the focused
    /// text field itself.
    func dismissesKeyboardOnBackgroundTap() -> some View {
        background(KeyboardDismissInstaller())
    }
}

// MARK: - Destructive action button (purgr's solid-red rounded button)

struct DestructiveButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        // Paint the row itself red rather than a shape drawn inside it, so the
        // corners come from the same automatic Form/Section rounding every
        // other row gets (e.g. Change Password above) instead of a hand-drawn
        // RoundedRectangle fighting that rounding from inside a zeroed-out row.
        .listRowBackground(Color.red)
    }
}

// MARK: - Delete confirmation (every destructive delete in the app routes through this)

extension View {
    /// Shows a "this can't be undone" confirmation before running `onDelete`.
    /// Bind `item` to a `@State` var set to the pending item when a delete is
    /// requested; this clears it back to `nil` on both confirm and cancel.
    func deleteConfirmation<Item>(
        _ item: Binding<Item?>,
        title: String,
        message: String = "This can't be undone.",
        onDelete: @escaping (Item) -> Void
    ) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { value in
            Button("Delete", role: .destructive) {
                onDelete(value)
                item.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) { item.wrappedValue = nil }
        } message: { _ in
            Text(message)
        }
    }
}

// MARK: - Skeleton loading placeholders (shown while data is fetching async)

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width)
                    .blendMode(.plusLighter)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.tertiarySystemFill))
            .frame(width: width, height: height)
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: 22, height: 22, cornerRadius: 11)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 140, height: 14)
                SkeletonBlock(width: 80, height: 10)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SkeletonList: View {
    var rows: Int = 6
    var body: some View {
        List(0..<rows, id: \.self) { _ in SkeletonRow() }
            .listStyle(.plain)
            .scrollDisabled(true)
            .shimmering()
    }
}

struct SkeletonCard: View {
    var lines: Int = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<lines, id: \.self) { index in
                SkeletonBlock(height: 14)
                    .frame(maxWidth: index == lines - 1 ? 100 : .infinity, alignment: .leading)
            }
        }
        .cardStyle()
        .shimmering()
    }
}

// MARK: - Formatting helpers

enum DateFormatting {
    static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let fractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Handles timestamps with no "T"/"Z" (e.g. "2026-09-09 17:20:50.283000") by
    /// treating them as UTC, which is what the backend's raw SQL timestamps mean.
    private static let fallbackFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static func date(from iso: String) -> Date? {
        if let date = ISO8601Formatter.shared.date(from: iso) { return date }
        if let date = fractionalSecondsFormatter.date(from: iso) { return date }
        if let date = ISO8601DateFormatter().date(from: iso) { return date }

        // Some backends emit non-millisecond fractional precision (e.g. microseconds)
        // or a space instead of "T", which none of the ISO8601 formatters above accept.
        // Normalize before falling back to a manual formatter.
        var normalized = iso.replacingOccurrences(of: " ", with: "T")
        if let dotIndex = normalized.firstIndex(of: ".") {
            var digitsEnd = normalized.index(after: dotIndex)
            while digitsEnd < normalized.endIndex, normalized[digitsEnd].isNumber {
                digitsEnd = normalized.index(after: digitsEnd)
            }
            normalized.removeSubrange(dotIndex..<digitsEnd)
        }
        if normalized.hasSuffix("Z") {
            normalized.removeLast()
        } else if let timeStart = normalized.firstIndex(of: "T"),
                  let offsetStart = normalized[normalized.index(after: timeStart)...].firstIndex(where: { $0 == "+" || $0 == "-" }) {
            normalized.removeSubrange(offsetStart..<normalized.endIndex)
        }

        return fallbackFormatter.date(from: normalized)
    }

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static func displayString(from iso: String) -> String {
        guard let date = date(from: iso) else { return iso }
        return display.string(from: date)
    }

    /// Formats the elapsed time between two ISO8601 timestamps as e.g. "1h 12m" or "45m".
    static func durationString(from startIso: String, to endIso: String) -> String? {
        guard let start = date(from: startIso), let end = date(from: endIso) else { return nil }
        let totalMinutes = Int(end.timeIntervalSince(start) / 60)
        guard totalMinutes >= 0 else { return nil }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
