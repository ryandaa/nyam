import SwiftUI

/// Cal-AI-style combined home: streak chip + week strip + calorie hero
/// + macro cards + recently-uploaded feed. Daily progress at the top,
/// the chronological feed below.
struct HomeView: View {
    @EnvironmentObject var history: ScanHistory

    @State private var showManualEntry = false

    /// User-settable daily calorie target — edited in Profile, picked up here
    /// for the week-strip ring progress. Defaults to 2000 kcal until the user
    /// chooses their own.
    @AppStorage("nyam.dailyCalorieGoal") private var dailyCalorieGoal: Double = 2000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    weekStrip
                    recentlyUploaded
                }
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
            .background(Color.NyamSurface.background.ignoresSafeArea())
            .sheet(isPresented: $showManualEntry) {
                ManualEntryView()
                    .environmentObject(history)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("nyam")
                        .font(.system(size: 28, weight: .bold, design: .serif).italic())
                        .foregroundStyle(Color.NyamSage.shade5)
                        .padding(.leading, 4)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    StreakChip(days: currentStreak)
                }
            }
            .navigationDestination(for: HistoryEntry.self) { entry in
                ResultsView(result: entry.result, onScanAgain: nil)
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    // MARK: - Computed week / day data

    private var weekStart: Date {
        let cal = Calendar.current
        let today = Date()
        // Week starts on Sunday (US default) — weekday 1 = Sunday in Calendar.
        let weekday = cal.component(.weekday, from: today)
        let offset = -(weekday - 1)
        return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: today)) ?? today
    }

    fileprivate struct DayEntry: Identifiable {
        let id = UUID()
        let date: Date
        let dayShortName: String   // "Sun"
        let dayNumber: Int         // 10
        let calories: Double
        let isToday: Bool
        let isFuture: Bool
    }

    private var weekDays: [DayEntry] {
        let cal = Calendar.current
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let today = cal.startOfDay(for: Date())
        return (0..<7).map { offset in
            let date = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let entriesForDay = history.entries.filter { cal.isDate($0.date, inSameDayAs: date) }
            let calories = entriesForDay.reduce(0.0) { $0 + $1.result.totals.calories }
            return DayEntry(
                date: date,
                dayShortName: labels[offset],
                dayNumber: cal.component(.day, from: date),
                calories: calories,
                isToday: cal.isDate(date, inSameDayAs: today),
                isFuture: date > today
            )
        }
    }

    /// Strict streak: number of consecutive days back from today that have
    /// at least one logged meal. If today has none, streak = 0.
    private var currentStreak: Int {
        let cal = Calendar.current
        var streak = 0
        var checkDate = cal.startOfDay(for: Date())
        while history.entries.contains(where: { cal.isDate($0.date, inSameDayAs: checkDate) }) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    // MARK: - Sections

    private var weekStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(weekHeaderText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 4)

            HStack(spacing: 8) {
                ForEach(weekDays) { day in
                    DayRing(
                        day: day,
                        progress: day.calories / dailyCalorieGoal
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// "June 2026" — wide month + year of the current week's anchor day.
    private var weekHeaderText: String {
        weekStart.formatted(.dateTime.month(.wide).year())
    }

    private var recentlyUploaded: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recently uploaded")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    showManualEntry = true
                } label: {
                    Label("Log manually", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.NyamSage.shade5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 8)

            if history.entries.isEmpty {
                EmptyHomeState()
                    .padding(.top, 12)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(history.entries) { entry in
                        NavigationLink(value: entry) {
                            MealRow(
                                entry: entry,
                                onDelete: { history.delete(entry) }
                            )
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: history.entries.count)
            }
        }
    }
}

// MARK: - Day ring (week strip)

private struct DayRing: View {
    let day: HomeView.DayEntry
    let progress: Double

    var body: some View {
        VStack(spacing: 6) {
            Text(day.dayShortName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 2)
                if day.isFuture {
                    Circle()
                        .strokeBorder(
                            Color(.separator).opacity(0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                } else if !day.isFuture {
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(Color.NyamSage.shade4, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if day.isToday {
                    Circle()
                        .strokeBorder(Color.NyamSage.shade5, lineWidth: 1.5)
                }
                Text("\(day.dayNumber)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(day.isToday ? Color.NyamSage.shade5 : .primary)
            }
            .frame(width: 38, height: 38)
        }
    }
}

// MARK: - Streak chip

private struct StreakChip: View {
    let days: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            Text("\(days)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Empty state

private struct EmptyHomeState: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.NyamSage.tint7)
                    .frame(width: 72, height: 72)
                Image(systemName: "fork.knife")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.NyamSage.shade4)
            }
            VStack(spacing: 4) {
                Text("No meals yet today")
                    .font(.subheadline.weight(.semibold))
                Text("Tap the + button to scan your first plate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Meal row (recently uploaded feed entry — same Beli-style as before)

struct MealRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var displayTitle: String {
        if let title = entry.result.title, !title.isEmpty { return title }
        return entry.result.items.max(by: { $0.calories < $1.calories })?.name.capitalized ?? "Empty Plate"
    }

    private var detectedSummary: String {
        entry.result.items.prefix(3).map { $0.name.lowercased() }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row — avatar + title block + score circle
            HStack(alignment: .top, spacing: 12) {
                AvatarCircle()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Text("You scanned ")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            + Text(displayTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let count = entry.result.items.count
                        Text("\(count) item\(count == 1 ? "" : "s") · \(entry.date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                ScoreCircle(calories: entry.result.totals.calories)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            heroImage

            if !detectedSummary.isEmpty {
                (Text("Notes: ").font(.subheadline.weight(.semibold)) +
                 Text(detectedSummary).font(.subheadline))
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }

            HStack(spacing: 22) {
                Image(systemName: "paperplane")
                Spacer()
                Menu {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete meal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .contentShape(Rectangle())
        .confirmationDialog(
            "Delete this meal?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(displayTitle) will be removed from your history.")
        }
    }

    @ViewBuilder
    private var heroImage: some View {
        let image = ScanImageStore.load(relativePath: entry.imagePath)
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color.NyamSage.tint5, Color.NyamSage.tint7],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

/// Calorie-as-score circle on each MealRow (same as V4).
private struct ScoreCircle: View {
    let calories: Double

    private var color: Color {
        switch calories {
        case ..<400:        return Color.NyamSage.shade3
        case 400..<800:     return Color.NyamSage.shade4
        case 800..<1200:    return Color.NyamSage.shade5
        default:            return Color.NyamSage.shade6
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.55), lineWidth: 1.5)
                .frame(width: 56, height: 56)
            VStack(spacing: 0) {
                Text("\(Int(calories.rounded()))")
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text("kcal")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color.opacity(0.7))
            }
        }
    }
}

struct AvatarCircle: View {
    var initial: String = "R"
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.NyamSage.shade4)
            Text(initial)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

#Preview("With meals today") {
    let history = ScanHistory()
    history.record(.preview, image: nil)
    history.record(.preview, image: nil)
    return HomeView()
        .environmentObject(history)
}

#Preview("Empty") {
    HomeView()
        .environmentObject(ScanHistory())
}
