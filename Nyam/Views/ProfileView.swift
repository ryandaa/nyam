import SwiftUI

/// Profile tab: avatar + mock email + lifetime stats + sign out.
/// Replaces V1's top-right sign-out icon on ScanView.
struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var history: ScanHistory

    // TODO: replace with the real email once Sign in with Apple is restored
    // (requires a paid Apple Developer account — V1 limitation).
    private let mockEmail = "ryan@nyam.app"

    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    lifetimeStats
                    Spacer(minLength: 12)
                    signOutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 96) // floating + button clearance
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .tint(Color.accentColor)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            avatar
            VStack(spacing: 4) {
                Text(mockEmail)
                    .font(.headline)
                Text("Plate-anchored nutrition")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 92, height: 92)
            Text(initials)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .shadow(color: Color.accentColor.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private var initials: String {
        let first = mockEmail.first.map { String($0).uppercased() } ?? "?"
        return first
    }

    private var lifetimeStats: some View {
        let totalScans = history.entries.count
        let avgCalories: Double? = {
            guard totalScans > 0 else { return nil }
            let sum = history.entries.reduce(0.0) { $0 + $1.result.totals.calories }
            return sum / Double(totalScans)
        }()

        return VStack(alignment: .leading, spacing: 10) {
            Text("Lifetime")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                StatTile(
                    title: "Total scans",
                    value: "\(totalScans)"
                )
                StatTile(
                    title: "Avg kcal / meal",
                    value: avgCalories.map { "\(Int($0.rounded()))" } ?? "—"
                )
            }
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            showSignOutConfirm = true
        } label: {
            Text("Sign out")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Tiles

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
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
