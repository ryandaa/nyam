import SwiftUI

/// Shown after the user captures a photo. Renders the still with a detected-plate
/// overlay, lets the user adjust the diameter, then kicks off the scan.
struct CalibrationSheet: View {
    @EnvironmentObject var auth: AuthManager
    let image: UIImage
    let onScanComplete: (ScanResult) -> Void
    let onCancel: () -> Void

    @State private var detected: DetectedPlate?
    @State private var diameterCm: Double = 26 // standard 10in dinner plate
    @State private var isScanning = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 24) {
                    capturedPhoto
                        .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        if let detected, detected.confidence > 0.15 {
                            Text("We detected your plate. What's its real-world diameter?")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Couldn't auto-detect the plate. Set its diameter manually:")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 12) {
                            Stepper(value: $diameterCm, in: 12...40, step: 0.5) {
                                HStack(spacing: 4) {
                                    Text("\(String(format: "%.1f", diameterCm)) cm")
                                        .font(.title3.monospacedDigit())
                                        .bold()
                                    Text("(\(String(format: "%.1f", diameterCm / 2.54)) in)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.NyamSurface.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button {
                        Task { await runScan() }
                    } label: {
                        HStack {
                            if isScanning { ProgressView().tint(.white) }
                            Text(isScanning ? "Analyzing…" : "Scan plate")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isScanning)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                if isScanning {
                    LoadingView()
                }
            }
            .navigationTitle("Confirm plate size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Retake", action: onCancel)
                }
            }
        }
        .onAppear {
            // Synchronous on .userInitiated QoS — fast enough for one still image.
            DispatchQueue.global(qos: .userInitiated).async {
                let result = PlateDetector.detect(in: image)
                DispatchQueue.main.async { detected = result }
            }
        }
    }

    private var capturedPhoto: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                if let detected, detected.confidence > 0.15 {
                    // Compute the rendered image's actual frame inside the GeometryReader.
                    let renderedRect = aspectFitRect(imageSize: image.size, in: geo.size)
                    let ellipseRect = CGRect(
                        x: renderedRect.minX + (detected.center.x - detected.size.width / 2) * renderedRect.width,
                        y: renderedRect.minY + (detected.center.y - detected.size.height / 2) * renderedRect.height,
                        width: detected.size.width * renderedRect.width,
                        height: detected.size.height * renderedRect.height
                    )
                    Ellipse()
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: ellipseRect.width, height: ellipseRect.height)
                        .position(x: ellipseRect.midX, y: ellipseRect.midY)
                }
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        var width: CGFloat
        var height: CGFloat
        if imageAspect > containerAspect {
            width = containerSize.width
            height = containerSize.width / imageAspect
        } else {
            height = containerSize.height
            width = containerSize.height * imageAspect
        }
        let x = (containerSize.width - width) / 2
        let y = (containerSize.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    @MainActor
    private func runScan() async {
        errorMessage = nil
        isScanning = true
        defer { isScanning = false }
        do {
            let result = try await NyamAPI.scan(
                image: image,
                plateDiameterCm: diameterCm,
                identityToken: auth.identityToken
            )
            onScanComplete(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
