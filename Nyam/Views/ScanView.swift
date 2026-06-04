import SwiftUI
import ARKit
import RealityKit

/// ARKit-backed scan view. Hosts a `RealityKit` `ARView` showing the live
/// camera, watches for horizontal-plane detection, and on capture hands back
/// the image + (optionally) the measured plate diameter in cm.
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var arScan = ARScanSession()
    let onCapture: (UIImage, Double?) -> Void

    var body: some View {
        ZStack {
            ARCameraView(session: arScan.session)
                .ignoresSafeArea()

            // Reticle / framing guide
            VStack {
                Spacer()
                Image(systemName: "circle.dashed")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(radius: 4)
                Spacer()
            }
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .foregroundStyle(.primary)
                    .padding(.leading, 20)
                    .padding(.top, 12)

                    Spacer()
                }

                Spacer()

                statusBanner

                Button {
                    let result = arScan.captureScan()
                    onCapture(result.image, result.diameterCm)
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(arScan.state == .ready ? Color.accentColor : .white)
                            .frame(width: 66, height: 66)
                    }
                }
                .padding(.bottom, 36)
            }
        }
        .onAppear { arScan.start() }
        .onDisappear { arScan.stop() }
    }

    @ViewBuilder
    private var statusBanner: some View {
        let (text, icon): (String, String) = {
            switch arScan.state {
            case .starting:
                return ("Starting camera…", "viewfinder")
            case .lookingForPlane:
                return ("Move your phone over the table to lock scale", "arrow.up.and.down.and.arrow.left.and.right")
            case .ready:
                return ("Center your plate, then capture", "checkmark.circle.fill")
            case .unsupported:
                return ("AR not supported on this device — using assumed plate size", "exclamationmark.triangle.fill")
            }
        }()

        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
            Text(text)
                .font(.callout)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 18)
    }
}

// MARK: - ARView wrapper

private struct ARCameraView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        // automaticallyConfigureSession: false — we already drive the session
        // from ARScanSession.start() so the SwiftUI wrapper does NOT replace
        // its configuration.
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        view.renderOptions = [.disablePersonOcclusion, .disableMotionBlur]
        view.environment.background = .cameraFeed()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
