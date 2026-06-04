import SwiftUI

/// Full-screen modal flow opened by the bottom-bar "+" button.
/// Hosts the three capture modes:
///   - Food   → ARKit scan (live or library) → /scan → ResultsView
///   - Menu   → photo capture → /menu → MenuResultsView
///   - QR     → barcode detection → /barcode/<code> → PortionFulfillmentView
struct CameraFlowView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var history: ScanHistory
    let onFinish: () -> Void

    @State private var analyzing: AnalyzingFoodScan?
    @State private var result: ScanResult?
    @State private var errorMessage: String?

    // Menu-mode state
    @State private var menuCaptured: CapturedPhoto?
    @State private var menuResult: MenuResult?
    @State private var menuIsAnalyzing = false

    // Barcode-mode state
    @State private var barcodeLookup: BarcodeLookupResult?
    @State private var barcodeIsLooking = false

    // Manual-entry fallback (kicked off when barcode lookup misses
    // and the user chooses to log manually).
    @State private var showManualEntry = false

    private struct AnalyzingFoodScan: Identifiable {
        let id = UUID()
        let image: UIImage
        /// Optional — ARKit-measured when present, nil for library photos
        /// or when AR couldn't lock on. The Worker handles both cases.
        let diameterCm: Double?
        let foodVolumeCm3: Double?
    }

    var body: some View {
        ZStack {
            if let result {
                NavigationStack {
                    ResultsView(
                        result: result,
                        onScanAgain: {
                            self.result = nil
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
                ScanView(onCapture: handleCapture(_:))
                    .fullScreenCover(item: $menuResult) { menu in
                        MenuResultsView(
                            menu: menu,
                            menuImage: menuCaptured?.image,
                            onFinish: {
                                menuResult = nil
                                menuCaptured = nil
                                onFinish()
                            }
                        )
                        .environmentObject(history)
                    }
                    .sheet(item: $barcodeLookup) { lookup in
                        PortionFulfillmentView(
                            lookup: lookup,
                            onLogged: {
                                barcodeLookup = nil
                                onFinish()
                            },
                            onLogManually: {
                                barcodeLookup = nil
                                showManualEntry = true
                            }
                        )
                        .environmentObject(history)
                    }
                    .sheet(isPresented: $showManualEntry) {
                        ManualEntryView()
                            .environmentObject(history)
                            .onDisappear { onFinish() }
                    }
                    .overlay {
                        if analyzing != nil || menuIsAnalyzing || barcodeIsLooking {
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
        .animation(.easeInOut(duration: 0.18), value: menuIsAnalyzing)
        .animation(.easeInOut(duration: 0.18), value: barcodeIsLooking)
    }

    // MARK: - Capture dispatch

    private func handleCapture(_ result: CaptureResult) {
        switch result {
        case .food(let measurement):
            handleFoodCapture(measurement)
        case .menu(let image):
            handleMenuCapture(image)
        case .barcode(let code):
            handleBarcodeCapture(code)
        }
    }

    private func handleFoodCapture(_ measurement: ARMeasurement) {
        // Always go straight to /scan — Worker handles both anchored
        // (ARKit measured a plate diameter) and unanchored (library photo,
        // or AR couldn't lock) cases. No CalibrationSheet step in V5.2.
        let scan = AnalyzingFoodScan(
            image: measurement.image,
            diameterCm: measurement.diameterCm,
            foodVolumeCm3: measurement.foodVolumeCm3
        )
        analyzing = scan
        Task { await runScan(scan) }
    }

    private func handleMenuCapture(_ image: UIImage) {
        menuCaptured = CapturedPhoto(image: image)
        menuIsAnalyzing = true
        Task { await runMenuScan(image: image) }
    }

    private func handleBarcodeCapture(_ code: String) {
        barcodeIsLooking = true
        Task { await runBarcodeLookup(code: code) }
    }

    // MARK: - Network calls

    @MainActor
    private func runScan(_ scan: AnalyzingFoodScan) async {
        do {
            let newResult = try await NyamAPI.scan(
                image: scan.image,
                plateDiameterCm: scan.diameterCm,
                foodVolumeCm3: scan.foodVolumeCm3,
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

    @MainActor
    private func runMenuScan(image: UIImage) async {
        do {
            let menu = try await NyamAPI.scanMenu(image: image, identityToken: auth.identityToken)
            menuIsAnalyzing = false
            menuResult = menu
        } catch {
            errorMessage = error.localizedDescription
            menuIsAnalyzing = false
            menuCaptured = nil
        }
    }

    @MainActor
    private func runBarcodeLookup(code: String) async {
        do {
            let lookup = try await NyamAPI.lookupBarcode(code)
            barcodeIsLooking = false
            barcodeLookup = lookup
        } catch {
            errorMessage = error.localizedDescription
            barcodeIsLooking = false
        }
    }
}

// MARK: - Identifiable conformance for the menu cover

extension MenuResult: Identifiable {
    public var id: String {
        (restaurantName ?? "menu") + "-" + dishes.map(\.name).joined(separator: ",")
    }
}

extension BarcodeLookupResult: Identifiable {
    public var id: String { barcode }
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
