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
/// retroactively conforming UIImage to Identifiable.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Top-level router. Shows Auth or the Scan flow based on sign-in state.
struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var history: ScanHistory
    @State private var captured: CapturedPhoto?
    @State private var result: ScanResult?

    var body: some View {
        Group {
            if !auth.isSignedIn {
                AuthView()
            } else if let result {
                ResultsView(result: result, onScanAgain: {
                    self.result = nil
                    self.captured = nil
                })
            } else {
                ScanView(onCapture: { image in
                    captured = CapturedPhoto(image: image)
                })
                .sheet(item: $captured) { photo in
                    CalibrationSheet(
                        image: photo.image,
                        onScanComplete: { newResult in
                            history.record(newResult)
                            captured = nil
                            result = newResult
                        },
                        onCancel: {
                            captured = nil
                        }
                    )
                    .interactiveDismissDisabled()
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.22), value: result != nil)
    }
}
