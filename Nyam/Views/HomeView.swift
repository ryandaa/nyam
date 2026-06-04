import SwiftUI

/// Beli-style feed of past meals. Wordmark top-left, no card backgrounds,
/// hairline dividers between entries, score circle on the right.
struct HomeView: View {
    @EnvironmentObject var history: ScanHistory

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    EmptyHomeState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(history.entries) { entry in
                                NavigationLink(value: entry) {
                                    MealRow(
                                        entry: entry,
                                        onDelete: { history.delete(entry) }
                                    )
                                }
                                .buttonStyle(.plain)
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 96)
                        .animation(.easeInOut(duration: 0.22), value: history.entries.count)
                    }
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("nyam")
                        .font(.system(size: 28, weight: .bold, design: .serif).italic())
                        .foregroundStyle(Color.NyamSage.shade5)
                        .padding(.leading, 4)
                }
            }
            .navigationDestination(for: HistoryEntry.self) { entry in
                ResultsView(result: entry.result, onScanAgain: nil)
            }
        }
        .tint(Color.NyamSage.shade5)
    }
}

// MARK: - Empty state

private struct EmptyHomeState: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.NyamSage.tint7)
                    .frame(width: 96, height: 96)
                Image(systemName: "fork.knife")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color.NyamSage.shade4)
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

// MARK: - Meal row (Beli-style feed entry)

private struct MealRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false
    @State private var showShare = false

    private var displayTitle: String {
        if let title = entry.result.title, !title.isEmpty { return title }
        return entry.result.items.max(by: { $0.calories < $1.calories })?.name.capitalized ?? "Empty Plate"
    }

    private var itemCountText: String {
        let n = entry.result.items.count
        return n == 1 ? "1 item" : "\(n) items"
    }

    /// Single line summary of detected items, e.g. "chicken, rice, broccoli".
    private var detectedSummary: String {
        entry.result.items.prefix(3).map { $0.name.lowercased() }.joined(separator: ", ")
    }

    private var dayOfWeek: String {
        entry.date.formatted(.dateTime.weekday(.wide))
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
                        Text(itemCountText + " · " + entry.date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                ScoreCircle(calories: entry.result.totals.calories)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Hero photo
            heroImage

            // Notes
            if !detectedSummary.isEmpty {
                (Text("Notes: ").font(.subheadline.weight(.semibold)) +
                 Text(detectedSummary).font(.subheadline))
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }

            // Action row
            HStack(spacing: 22) {
                Button { showShare = true } label: {
                    Image(systemName: "paperplane")
                }
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
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

            // Day label
            Text(dayOfWeek)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 2)
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
            Text("\(displayTitle) will be removed from your history. This can't be undone.")
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
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

// MARK: - Score circle (Beli's signature — calories as the "score")

private struct ScoreCircle: View {
    let calories: Double

    private var color: Color {
        switch calories {
        case ..<400:        return Color.NyamSage.shade3   // light meal
        case 400..<800:     return Color.NyamSage.shade4   // typical
        case 800..<1200:    return Color.NyamSage.shade5   // heavier
        default:            return Color.NyamSage.shade6   // heavy
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

// MARK: - Avatar (sage circle with initial — same as ProfileView)

struct AvatarCircle: View {
    /// Defaults to "R" — the user identity is mock for V1.
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

#Preview("With entries") {
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

#Preview("MealRow alone") {
    MealRow(
        entry: HistoryEntry(result: .preview),
        onDelete: { print("delete") }
    )
}
