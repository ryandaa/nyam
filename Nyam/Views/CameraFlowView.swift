import SwiftUI

/// Full-screen modal flow opened by the bottom-bar "+" button.
/// Owns the state machine: Scan → (auto-measure or calibrate) → Results → Done.
///
/// If ARKit returns a measured plate diameter, we skip the CalibrationSheet
/// and run the scan immediately — the V3 magic moment. If measurement fails
/// (no plane found, raycast miss), we fall back to V2's manual CalibrationSheet
/// so the demo never dead-ends.
struct CameraFlowView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var history: ScanHistory
    let onFinish: () -> Void

    @State private var pendingCalibration: CapturedPhoto?
    @State private var analyzing: AnalyzingScan?
    @State private var result: ScanResult?
    @State private var errorMessage: String?

    /// Captured frame for which ARKit returned a confident diameter — we go
    /// straight to /scan, no manual sheet.
    private struct AnalyzingScan: Identifiable {
        let id = UUID()
        let image: UIImage
        let diameterCm: Double
    }

    var body: some View {
        ZStack {
            if let result {
                NavigationStack {
                    ResultsView(
                        result: result,
                        onScanAgain: {
                            self.result = nil
                            self.pendingCalibration = nil
                            self.analyzing = nil
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { onFinish() }
                        }
                    }
                }
            } else {
                ScanView(onCapture: handleCapture(image:diameterCm:))
                    .sheet(item: $pendingCalibration) { photo in
                        CalibrationSheet(
                            image: photo.image,
                            onScanComplete: { newResult in
                                history.record(newResult, image: photo.image)
                                pendingCalibration = nil
                                result = newResult
                            },
                            onCancel: { pendingCalibration = nil }
                        )
                        .interactiveDismissDisabled()
                    }
                    .overlay {
                        if analyzing != nil {
                            LoadingView()
                                .transition(.opacity)
                        }
                    }
            }

            if let errorMessage {
                ErrorToast(message: errorMessage) {
                    self.errorMessage = nil
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: result != nil)
        .animation(.easeInOut(duration: 0.18), value: analyzing != nil)
    }

    private func handleCapture(image: UIImage, diameterCm: Double?) {
        if let diameterCm {
            let scan = AnalyzingScan(image: image, diameterCm: diameterCm)
            analyzing = scan
            Task { await runDirectScan(scan) }
        } else {
            // ARKit couldn't measure — fall back to manual calibration sheet.
            pendingCalibration = CapturedPhoto(image: image)
        }
    }

    @MainActor
    private func runDirectScan(_ scan: AnalyzingScan) async {
        do {
            let newResult = try await NyamAPI.scan(
                image: scan.image,
                plateDiameterCm: scan.diameterCm,
                identityToken: auth.identityToken
            )
            history.record(newResult, image: scan.image)
            analyzing = nil
            result = newResult
        } catch {
            errorMessage = error.localizedDescription
            analyzing = nil
        }
    }
}

// MARK: - Error toast

private struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(14)
            .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
