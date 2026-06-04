import SwiftUI
import AVFoundation
import UIKit

/// Live barcode scanner backed by `AVCaptureMetadataOutput`. Detects UPC-A,
/// UPC-E, EAN-8, EAN-13, and QR codes — the formats packaged food in the
/// US and EU actually ships with.
///
/// On a successful detection, calls `onDetect(stringValue)` exactly once and
/// then idles (the parent dismisses or pauses the scanner). De-bouncing
/// prevents the same barcode firing multiple times per session.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerVC {
        let vc = BarcodeScannerVC()
        vc.onDetect = onDetect
        return vc
    }

    func updateUIViewController(_ vc: BarcodeScannerVC, context: Context) {}
}

final class BarcodeScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetect: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasFired = false

    private let supportedTypes: [AVMetadataObject.ObjectType] = [
        .upce, .ean8, .ean13, .qr, .code128, .code39
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasFired = false
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            // Only request the types the device actually supports — anything
            // else throws on assignment.
            let available = Set(metadataOutput.availableMetadataObjectTypes)
            metadataOutput.metadataObjectTypes = supportedTypes.filter { available.contains($0) }
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        session.commitConfiguration()
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasFired else { return }
        guard
            let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = obj.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return }
        hasFired = true
        // Haptic feedback so the user feels the catch.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDetect?(value)
    }
}
