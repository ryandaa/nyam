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
                case .home:    HomeView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BottomBar(
                selected: $selectedTab,
                onCenterTap: { showCameraFlow = true }
            )
        }
        .background(Color.NyamSurface.background.ignoresSafeArea())
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
        HStack(spacing: 0) {
            TabBarButton(
                icon: "house",
                activeIcon: "house.fill",
                label: "Home",
                isActive: selected == .home
            ) { selected = .home }

            CenterButton(onTap: onCenterTap)

            TabBarButton(
                icon: "person",
                activeIcon: "person.fill",
                label: "Profile",
                isActive: selected == .profile
            ) { selected = .profile }
        }
        .padding(.top, 10)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .background(
            Color.NyamSurface.background
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundStyle(Color(.separator)),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// Center "+" button — sits in its own slot like Beli, slightly elevated.
private struct CenterButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.NyamSage.shade5)
                    .frame(width: 56, height: 56)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: 56)
        }
        .accessibilityLabel("Scan a meal")
        .offset(y: -8)
    }
}

private struct TabBarButton: View {
    let icon: String
    let activeIcon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isActive ? activeIcon : icon)
                    .font(.system(size: 20, weight: .regular))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RootTabView()
        .environmentObject(AuthManager())
        .environmentObject(ScanHistory())
}
