import SwiftUI

/// Beli-style profile: name top-left, large centered avatar, 3-stat row,
/// action pills, list with circular icons, two stat tiles, calorie-goal card.
struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var history: ScanHistory

    // TODO: replace with the real email once Sign in with Apple is restored.
    private let mockName = "Ryan Da"
    private let mockHandle = "@ryanda"
    private let memberSince = "Member since May"

    @State private var showSignOutConfirm = false
    @State private var showEditGoals = false

    /// User-settable daily targets, persisted via UserDefaults so Home,
    /// the Coach prompt, and any future surface read the same value.
    @AppStorage("nyam.dailyCalorieGoal") private var dailyCalorieGoal: Double = 2000
    @AppStorage("nyam.dailyProteinGoal") private var dailyProteinGoal: Double = 150

    private var totalScans: Int { history.entries.count }

    private var scansThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        return history.entries.filter { $0.date >= weekAgo }.count
    }

    private var avgCalories: Int? {
        guard totalScans > 0 else { return nil }
        let sum = history.entries.reduce(0.0) { $0 + $1.result.totals.calories }
        return Int((sum / Double(totalScans)).rounded())
    }

    /// Same strict-streak definition as HomeView's chip: consecutive days
    /// back from today with at least one logged meal. 0 if today has none.
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    statsRow
                    tileRow
                    goalCard
                    Spacer(minLength: 12)
                    signOutButton
                }
                .padding(.bottom, 96)
            }
            .background(Color.NyamSurface.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(mockName)
                        .font(.title2.weight(.bold))
                }
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showEditGoals) {
                EditGoalsSheet(
                    calorieGoal: $dailyCalorieGoal,
                    proteinGoal: $dailyProteinGoal
                )
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    // MARK: - Header (avatar + handle)

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.NyamSage.shade4)
                    .frame(width: 110, height: 110)
                Text(String(mockName.prefix(1)))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)
            .padding(.bottom, 10)

            Text(mockHandle)
                .font(.title3.weight(.semibold))

            Text(memberSince)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats row (Total / Week / Avg)

    private var statsRow: some View {
        HStack(spacing: 0) {
            StatColumn(value: "\(totalScans)", label: "Total scans")
            StatColumn(value: "\(scansThisWeek)", label: "This week")
            StatColumn(
                value: avgCalories.map { "\($0)" } ?? "—",
                label: "Avg cal"
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    // MARK: - Pill buttons row

    // MARK: - Tile row (Rank + Streak)

    private var tileRow: some View {
        HStack(spacing: 10) {
            StatTile(
                icon: "trophy.fill",
                title: "Avg cal / meal",
                value: avgCalories.map { "\($0)" } ?? "—",
                locked: false
            )
            StatTile(
                icon: "flame.fill",
                title: "Current Streak",
                value: "\(currentStreak) day\(currentStreak == 1 ? "" : "s")",
                locked: false
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    // MARK: - Goal card

    private var goalCard: some View {
        Button {
            showEditGoals = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.NyamSage.shade5.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "target")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.NyamSage.shade5)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily goals")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 12) {
                        GoalSnapshot(value: "\(Int(dailyCalorieGoal))", unit: "cal")
                        GoalSnapshot(value: "\(Int(dailyProteinGoal))", unit: "g protein")
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button(role: .destructive) {
            showSignOutConfirm = true
        } label: {
            Text("Sign out")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
                )
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }
}

// MARK: - Components

private struct StatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.NyamSage.shade5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(value)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.NyamSage.shade5)
                }
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

/// Inline summary of one goal in the daily-goals card.
private struct GoalSnapshot: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.NyamSage.shade5)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Edit goals sheet

private struct EditGoalsSheet: View {
    @Binding var calorieGoal: Double
    @Binding var proteinGoal: Double
    @Environment(\.dismiss) private var dismiss

    @State private var caloriesText: String = ""
    @State private var proteinText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("2000", text: $caloriesText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 90)
                        Text("cal")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("150", text: $proteinText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 90)
                        Text("g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Daily targets")
                } footer: {
                    Text("Used by the week strip and your AI dietitian to gauge how you're tracking. Common starting points: 1800–2500 cal, 100–180 g protein.")
                }
            }
            .navigationTitle("Daily goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.body.weight(.semibold))
                }
            }
            .onAppear {
                caloriesText = "\(Int(calorieGoal))"
                proteinText = "\(Int(proteinGoal))"
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    private func save() {
        if let c = Double(caloriesText.trimmingCharacters(in: .whitespaces)), c >= 500, c <= 8000 {
            calorieGoal = c
        }
        if let p = Double(proteinText.trimmingCharacters(in: .whitespaces)), p >= 10, p <= 500 {
            proteinGoal = p
        }
        dismiss()
    }
}

#Preview("Empty") {
    ProfileView()
        .environmentObject(AuthManager())
        .environmentObject(ScanHistory())
}

#Preview("With history") {
    let history = ScanHistory()
    history.record(.preview, image: nil)
    history.record(.preview, image: nil)
    return ProfileView()
        .environmentObject(AuthManager())
        .environmentObject(history)
}
