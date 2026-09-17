import SwiftUI

/// The full trailing-year activity view, pushed from the Dashboard's compact
/// "Activity" card via its "Full Year" link. Reuses the same calendar-month
/// grid as the Dashboard card, one per month, so the whole page reads as one
/// consistent style rather than switching to a different chart type.
struct WorkoutActivityYearView: View {
    let sessions: [WorkoutSession]

    private var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        return cal
    }

    /// The trailing 12 months, most recent first, so the page picks up right
    /// where the Dashboard card's current month left off.
    private var monthReferences: [Date] {
        let start = calendar.startOfDay(for: Date())
        return (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: start) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(yearSessionsCount)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("workouts in the last year")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(monthReferences, id: \.self) { month in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(DateFormatting.monthYear.string(from: month))
                            .font(.subheadline.weight(.semibold))
                        MonthActivityGrid(sessions: sessions, monthReference: month)
                    }
                    .cardStyle()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var yearSessionsCount: Int {
        let today = calendar.startOfDay(for: Date())
        let cutoff = calendar.date(byAdding: .day, value: -364, to: today) ?? today
        return sessions.filter { session in
            guard session.status == .completed, let date = DateFormatting.date(from: session.captured_at) else { return false }
            return date >= cutoff
        }.count
    }
}

// MARK: - Calendar-month activity grid

/// A traditional calendar-month layout (weeks as rows, aligned to real
/// weekdays), shaded by how many sets were logged that day. Used both by the
/// Dashboard's compact "Activity" card (current month) and, repeated once per
/// month, by `WorkoutActivityYearView`.
struct MonthActivityGrid: View {
    let sessions: [WorkoutSession]
    /// Any date within the month to render; defaults to the current month.
    var monthReference: Date = Date()

    private var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        return cal
    }

    private var today: Date { calendar.startOfDay(for: Date()) }

    private var countsByDay: [Date: Int] {
        var counts: [Date: Int] = [:]
        for session in sessions where session.status == .completed {
            guard let date = DateFormatting.date(from: session.captured_at) else { continue }
            let day = calendar.startOfDay(for: date)
            counts[day, default: 0] += max(session.sets.count, 1)
        }
        return counts
    }

    /// The month's days, Monday-first, padded with nils so every row has 7 slots.
    private var weeks: [[Date?]] {
        guard let monthStart = calendar.dateInterval(of: .month, for: monthReference)?.start,
              let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }

        let leadingBlanks = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks) + days
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let counts = countsByDay
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        dayCell(date, count: date.flatMap { counts[$0] } ?? 0)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout activity: \(counts.count) active days")
    }

    @ViewBuilder
    private func dayCell(_ date: Date?, count: Int) -> some View {
        if let date {
            let isToday = calendar.isDate(date, inSameDayAs: today)
            Text("\(calendar.component(.day, from: date))")
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundStyle(count > 0 ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(activityColor(for: count), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isToday ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 30)
        }
    }
}

/// Shared count -> color mapping so the Dashboard card and the year page's
/// month grids shade activity identically: logged a workout that day, or not.
func activityColor(for count: Int) -> Color {
    count > 0 ? Color.accentColor : Color(.systemGray5)
}

#Preview {
    NavigationStack {
        WorkoutActivityYearView(sessions: [])
    }
}
