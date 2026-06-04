import SwiftUI

/// GitHub-contribution-style weekly summary. Seven sage-intensity bubbles
/// (Mon → Sun, current week), today's calorie + protein intake below,
/// and the weekly totals beneath.
struct SummaryView: View {
    @EnvironmentObject var history: ScanHistory

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    weekHeader
                    weekGrid
                    todaySection
                    weekSection
                }
                .padding(.bottom, 96)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Summary")
                        .font(.title2.weight(.bold))
                }
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    // MARK: - Data

    private struct DayData: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String   // "M", "T", "W", "T", "F", "S", "S"
        let calories: Double
        let protein: Double
        let isToday: Bool
        let isFuture: Bool
    }

    /// Monday of the current calendar week.
    private var weekStart: Date {
        let calendar = Calendar.current
        let today = Date()
        // weekday: 1=Sun, 2=Mon, …, 7=Sat (Calendar default)
        let weekday = calendar.component(.weekday, from: today)
        // Offset back to Monday. Sunday (1) goes back 6, all others by (weekday-2).
        let offset = weekday == 1 ? -6 : -(weekday - 2)
        return calendar.date(
            byAdding: .day,
            value: offset,
            to: calendar.startOfDay(for: today)
        ) ?? today
    }

    private var weekDays: [DayData] {
        let calendar = Calendar.current
        let labels = ["M", "T", "W", "T", "F", "S", "S"]
        let today = calendar.startOfDay(for: Date())

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let entriesForDay = history.entries.filter {
                calendar.isDate($0.date, inSameDayAs: date)
            }
            let calories = entriesForDay.reduce(0.0) { $0 + $1.result.totals.calories }
            let protein = entriesForDay.reduce(0.0) { $0 + $1.result.totals.proteinG }
            return DayData(
                date: date,
                dayLabel: labels[offset],
                calories: calories,
                protein: protein,
                isToday: calendar.isDate(date, inSameDayAs: today),
                isFuture: date > today
            )
        }
    }

    private var todayData: DayData? { weekDays.first(where: \.isToday) }

    private var weeklyTotalCalories: Double {
        weekDays.reduce(0.0) { $0 + $1.calories }
    }
    private var weeklyTotalProtein: Double {
        weekDays.reduce(0.0) { $0 + $1.protein }
    }

    private var daysWithMeals: Int {
        weekDays.filter { $0.calories > 0 }.count
    }

    // MARK: - Sections

    private var weekHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(daysWithMeals) of 7 days logged")
                    .font(.title3.weight(.semibold))
                Text("Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var weekGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(weekDays) { day in
                    DayBubble(day: day)
                        .frame(maxWidth: .infinity)
                }
            }

            // Less / More legend, GitHub-style
            HStack(spacing: 6) {
                Spacer()
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    Circle()
                        .fill(intensityColor(level: level))
                        .frame(width: 10, height: 10)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let today = todayData {
                    Text(today.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                MetricTile(
                    title: "Calories",
                    value: "\(Int((todayData?.calories ?? 0).rounded()))",
                    unit: "kcal"
                )
                MetricTile(
                    title: "Protein",
                    value: "\(Int((todayData?.protein ?? 0).rounded()))",
                    unit: "g"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week total")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(weekDays.first?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "") – \(weekDays.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                MetricTile(
                    title: "Calories",
                    value: "\(Int(weeklyTotalCalories.rounded()))",
                    unit: "kcal"
                )
                MetricTile(
                    title: "Protein",
                    value: "\(Int(weeklyTotalProtein.rounded()))",
                    unit: "g"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    // MARK: - Intensity color bands

    /// Calorie ranges → 5 intensity levels (level 0 = empty / no meals).
    /// Tuned so a typical full day (~1800–2200 kcal) lands in level 3,
    /// and a heavy day (>2500) lands at level 4 (darkest).
    fileprivate static func intensityColor(level: Int) -> Color {
        switch level {
        case 0:  return Color(.tertiarySystemFill)
        case 1:  return Color.NyamSage.tint5
        case 2:  return Color.NyamSage.tint3
        case 3:  return Color.NyamSage.primary
        default: return Color.NyamSage.shade3
        }
    }

    fileprivate static func levelForCalories(_ kcal: Double) -> Int {
        switch kcal {
        case 0:                return 0
        case 0.1..<700:        return 1
        case 700..<1400:       return 2
        case 1400..<2200:      return 3
        default:               return 4
        }
    }

    private func intensityColor(level: Int) -> Color {
        Self.intensityColor(level: level)
    }
}

// MARK: - Day bubble

private struct DayBubble: View {
    let day: SummaryView.DayData

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(bubbleFill)
                    .frame(width: 36, height: 36)
                Circle()
                    .strokeBorder(
                        day.isToday ? Color.NyamSage.shade5 : Color.clear,
                        lineWidth: 2
                    )
                    .frame(width: 36, height: 36)
                if day.isFuture {
                    Circle()
                        .strokeBorder(
                            Color(.separator).opacity(0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                        .frame(width: 36, height: 36)
                }
            }
            Text(day.dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(day.isToday ? Color.NyamSage.shade5 : .secondary)
        }
    }

    private var bubbleFill: Color {
        if day.isFuture { return Color(.tertiarySystemFill).opacity(0.3) }
        return SummaryView.intensityColor(level: SummaryView.levelForCalories(day.calories))
    }
}

// MARK: - Metric tile

private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.NyamSage.shade5)
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }
}

#Preview("With meals") {
    let history = ScanHistory()
    history.record(.preview, image: nil)
    history.record(.preview, image: nil)
    return SummaryView()
        .environmentObject(history)
}

#Preview("Empty") {
    SummaryView()
        .environmentObject(ScanHistory())
}
