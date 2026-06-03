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
        .animation(.easeInOut(duration: 0.22), value: auth.isSignedIn)
    }
}
