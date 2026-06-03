import SwiftUI

/// The signed-in shell: a Home/Profile split with a floating sage "+" button
/// over the middle of the bottom bar that opens the camera modal.
///
/// Uses a fully custom bottom bar (not SwiftUI's TabView) so the center
/// button can be larger and float above the bar like Strava's "+" or
/// Instagram's record button.
struct RootTabView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var history: ScanHistory

    @State private var selectedTab: Tab = .home
    @State private var showCameraFlow = false

    enum Tab {
        case home, profile
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .home: HomeView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomBar(
                selected: $selectedTab,
                onCenterTap: { showCameraFlow = true }
            )
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .fullScreenCover(isPresented: $showCameraFlow) {
            CameraFlowView(onFinish: { showCameraFlow = false })
                .environmentObject(auth)
                .environmentObject(history)
        }
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    @Binding var selected: RootTabView.Tab
    let onCenterTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // Background bar
            HStack(spacing: 0) {
                TabBarButton(
                    icon: "house.fill",
                    label: "Home",
                    isActive: selected == .home
                ) { selected = .home }

                // Spacer reserved for the floating "+" button
                Spacer().frame(maxWidth: .infinity)

                TabBarButton(
                    icon: "person.fill",
                    label: "Profile",
                    isActive: selected == .profile
                ) { selected = .profile }
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .background(
                Color(.systemBackground)
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundStyle(Color(.separator)),
                        alignment: .top
                    )
                    .ignoresSafeArea(edges: .bottom)
            )

            // Floating sage "+" button, centered, lifted above the bar
            Button(action: onCenterTap) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 10, x: 0, y: 6)
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel("Scan a meal")
            .offset(y: -22)
        }
    }
}

private struct TabBarButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RootTabView()
        .environmentObject(AuthManager())
        .environmentObject(ScanHistory())
}
