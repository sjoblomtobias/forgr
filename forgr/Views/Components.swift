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
    var color: Color = .accentColor
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
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
    var gradient: [Color] = [.accentColor, .accentColor.opacity(0.5)]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
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

// MARK: - Destructive action button (purgr's solid-red rounded button)

struct DestructiveButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .background(.red, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
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
