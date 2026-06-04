import SwiftUI

@main
struct NyamApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var history = ScanHistory()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(history)
                .onChange(of: auth.isSignedIn) { _, signedIn in
                    if !signedIn { history.clear() }
                }
        }
    }
}

/// Wrapper so we can drive `.sheet(item:)` with a captured image without
/// retroactively conforming UIImage to Identifiable. Used by `CameraFlowView`.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Top-level router. Auth screen vs. the signed-in tab shell.
///
/// Forces `.preferredColorScheme(.light)` so the cream surface palette is
/// guaranteed regardless of the user's system theme. Beli, Notion, and most
/// food apps make this same call — the brand identity reads as warm/light,
/// and dark mode would invert the carefully-tuned sage contrast.
struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            if auth.isSignedIn {
                RootTabView()
            } else {
                AuthView()
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.22), value: auth.isSignedIn)
    }
}
