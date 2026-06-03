import SwiftUI

/// The Home tab — a Strava-style feed of past meals.
/// Top to bottom, newest first. Each card shows the meal photo, top food
/// name, relative date, and four headline stats: Calories, Protein, Fiber,
/// Sodium. Tap a card → detail view (existing ResultsView).
struct HomeView: View {
    @EnvironmentObject var history: ScanHistory

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    EmptyHomeState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(history.entries) { entry in
                                NavigationLink(value: entry) {
                                    MealCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 96) // leave room for the floating + button
                    }
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Nyam")
            .navigationDestination(for: HistoryEntry.self) { entry in
                ResultsView(result: entry.result, onScanAgain: nil)
            }
        }
        .tint(Color.accentColor)
    }
}

// MARK: - Empty state

private struct EmptyHomeState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "fork.knife")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 6) {
                Text("No meals yet")
                    .font(.title3.weight(.semibold))
                Text("Tap the + button to scan your first plate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Meal card

private struct MealCard: View {
    let entry: HistoryEntry

    private var topItemName: String {
        entry.result.items.max(by: { $0.calories < $1.calories })?.name.capitalized ?? "Empty plate"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroImage

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(topItemName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    StatChip(value: "\(Int(entry.result.totals.calories.rounded()))", unit: "kcal", emphasized: true)
                    StatChip(value: "\(Int(entry.result.totals.proteinG.rounded()))", unit: "P · g")
                    StatChip(value: "\(Int(entry.result.totals.fiberG.rounded()))", unit: "Fi · g")
                    StatChip(value: "\(Int(entry.result.totals.sodiumMg.rounded()))", unit: "Na · mg")
                }
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
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
                    colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(height: 200)
        .clipped()
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
    }
}

// MARK: - Stat chip

private struct StatChip: View {
    let value: String
    let unit: String
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(emphasized ? .system(.headline, design: .rounded).monospacedDigit() : .system(.subheadline, design: .rounded).monospacedDigit().weight(.semibold))
                .foregroundStyle(emphasized ? Color.accentColor : Color.primary)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(emphasized ? Color.accentColor.opacity(0.12) : Color(.systemBackground))
        )
    }
}

#Preview("With entries") {
    let history = ScanHistory()
    history.record(.preview, image: nil)
    return HomeView()
        .environmentObject(history)
}

#Preview("Empty") {
    HomeView()
        .environmentObject(ScanHistory())
}
