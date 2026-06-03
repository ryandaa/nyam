import SwiftUI

@main
struct NyamApp: App {
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
        }
    }
}

/// Top-level router. Shows Auth or the Scan flow based on sign-in state.
struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var capturedImage: UIImage?
    @State private var result: ScanResult?

    var body: some View {
        Group {
            if !auth.isSignedIn {
                AuthView()
            } else if let result {
                ResultsView(result: result, onScanAgain: {
                    self.result = nil
                    self.capturedImage = nil
                })
            } else {
                ScanView(onCapture: { image in
                    capturedImage = image
                })
                .sheet(item: $capturedImage) { image in
                    CalibrationSheet(
                        image: image,
                        onScanComplete: { newResult in
                            capturedImage = nil
                            result = newResult
                        },
                        onCancel: {
                            capturedImage = nil
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

// Make UIImage usable with `.sheet(item:)` by giving it Identifiable conformance.
extension UIImage: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
