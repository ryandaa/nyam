import SwiftUI

/// Full-screen modal flow opened by the bottom-bar "+" button.
/// Owns the state machine: Scan → Calibration → Results → Done.
struct CameraFlowView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var history: ScanHistory
    let onFinish: () -> Void

    @State private var captured: CapturedPhoto?
    @State private var result: ScanResult?
    @State private var lastResultImage: UIImage?

    var body: some View {
        ZStack {
            if let result {
                NavigationStack {
                    ResultsView(
                        result: result,
                        onScanAgain: {
                            self.result = nil
                            self.captured = nil
                            self.lastResultImage = nil
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { onFinish() }
                        }
                    }
                }
            } else {
                ScanView(onCapture: { image in
                    captured = CapturedPhoto(image: image)
                })
                .sheet(item: $captured) { photo in
                    CalibrationSheet(
                        image: photo.image,
                        onScanComplete: { newResult in
                            history.record(newResult, image: photo.image)
                            lastResultImage = photo.image
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
        .animation(.easeInOut(duration: 0.22), value: result != nil)
    }
}
