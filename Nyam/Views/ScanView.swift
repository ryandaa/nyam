import SwiftUI
import AVFoundation

/// Full-screen camera viewfinder with a capture button.
///
/// On capture, hands off the still image via `onCapture` — the parent decides what
/// to show next (calibration sheet, then results).
struct ScanView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var session = CameraSession()
    @State private var showSignOutConfirm = false
    @State private var showHistory = false
    let onCapture: (UIImage) -> Void

    var body: some View {
        ZStack {
            CameraPreview(session: session.captureSession)
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
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .foregroundStyle(.primary)
                    .padding(.leading, 20)
                    .padding(.top, 12)

                    Spacer()

                    Button {
                        showSignOutConfirm = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .foregroundStyle(.primary)
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                }

                Spacer()

                VStack(spacing: 6) {
                    Text("Center your plate in the circle")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 18)

                Button {
                    session.capture { image in
                        guard let image else { return }
                        onCapture(image)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(.white)
                            .frame(width: 66, height: 66)
                    }
                }
                .padding(.bottom, 36)
            }
        }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
    }
}

// MARK: - Camera plumbing

/// AVCaptureSession wrapper. Not main-actor isolated — methods dispatch to a
/// dedicated session queue per Apple's guidance. SwiftUI views hold this via
/// `@State`; `@Observable` is here only to satisfy SwiftUI's preference, no
/// properties are actually observed.
@Observable
final class CameraSession {
    let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "ai.gojuly.nyam.cameraQueue")
    private var configured = false
    private var activeDelegate: PhotoCaptureDelegate?

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    func capture(_ completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { completion(nil); return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            let delegate = PhotoCaptureDelegate { image in
                DispatchQueue.main.async { completion(image) }
            }
            self.activeDelegate = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: camera),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        captureSession.commitConfiguration()
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let _ = error {
            completion(nil)
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion(nil); return
        }
        completion(image)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_: PreviewView, context _: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
