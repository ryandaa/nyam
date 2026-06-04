import Foundation
import ARKit
import Combine
import RealityKit
import UIKit
import Vision
import simd

/// ARKit-backed scan session: detects the table as a horizontal plane, then on
/// capture computes the **real-world plate diameter in cm** by combining
/// Vision's plate-ellipse detection with an ARKit raycast onto the plane.
///
/// The big win vs the V2 manual-diameter flow: no calibration sheet — the
/// plate's size becomes an output of the measurement, not an input.
///
/// Fallback: if no horizontal plane is found, or the raycast misses, the
/// session returns `nil` for the diameter and `CameraFlowView` falls back to
/// the V2 26 cm assumption with the CalibrationSheet override.
@MainActor
final class ARScanSession: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()

    enum State {
        case starting
        case lookingForPlane
        case ready
        case unsupported
    }

    @Published private(set) var state: State = .starting

    private var hasHorizontalPlane: Bool = false

    override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            state = .unsupported
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.worldAlignment = .gravity
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        state = .lookingForPlane
    }

    func stop() {
        session.pause()
    }

    // MARK: - Capture

    /// Capture the current AR frame, run plate detection, and try to compute
    /// a real-world diameter. Returns the captured image plus, when possible,
    /// the diameter in cm.
    func captureScan() -> (image: UIImage, diameterCm: Double?) {
        guard let frame = session.currentFrame else {
            return (UIImage(), nil)
        }
        let image = uiImage(from: frame.capturedImage, orientation: currentImageOrientation())
        let diameter = computePlateDiameterCm(frame: frame, image: image)
        return (image, diameter)
    }

    // MARK: - Plate measurement

    /// 1. Run `PlateDetector` on the captured still to locate the plate ellipse
    ///    in image-normalized coords (Y-down).
    /// 2. Raycast from the plate's screen-space center onto the detected
    ///    horizontal plane to get the plate's 3D world position.
    /// 3. Distance from camera to that world point ≈ overhead height to plate.
    /// 4. real_radius = pixel_radius * distance / focal_length_px.
    private func computePlateDiameterCm(frame: ARFrame, image: UIImage) -> Double? {
        guard hasHorizontalPlane,
              let plate = PlateDetector.detect(in: image)
        else { return nil }

        // PlateDetector returns coords normalized to the displayed image
        // (Y-down). Project that into ARKit's image space (pixels).
        let imgSize = image.size
        let centerPx = CGPoint(
            x: plate.center.x * imgSize.width,
            y: plate.center.y * imgSize.height
        )

        guard let query = frame.raycastQuery(
            from: centerPx,
            allowing: .estimatedPlane,
            alignment: .horizontal
        ) else { return nil }

        let results = session.raycast(query)
        guard let hit = results.first else { return nil }

        // Distance from camera to the hit point on the plane (meters)
        let camT = frame.camera.transform.columns.3
        let cameraPos = SIMD3<Float>(camT.x, camT.y, camT.z)
        let hitT = hit.worldTransform.columns.3
        let hitPos = SIMD3<Float>(hitT.x, hitT.y, hitT.z)
        let distanceM = simd_distance(cameraPos, hitPos)

        // Plate's pixel radius (longer axis to be conservative on perspective)
        let widthPx = plate.size.width * imgSize.width
        let heightPx = plate.size.height * imgSize.height
        let pixelDiameter = max(widthPx, heightPx)

        // Focal length in pixels comes straight from ARKit's intrinsics.
        // intrinsics[0][0] = f_x, in pixels at the ARFrame.capturedImage resolution.
        let intrinsics = frame.camera.intrinsics
        let fx = Double(intrinsics.columns.0.x)
        guard fx > 0 else { return nil }

        // Pinhole: real_size_m = pixel_size * distance_m / f_px
        let diameterM = Double(pixelDiameter) * Double(distanceM) / fx
        let diameterCm = diameterM * 100

        // Sanity bound: real plates are 12–40 cm. Reject anything outside.
        guard diameterCm >= 12, diameterCm <= 40 else { return nil }
        return diameterCm
    }

    // MARK: - Image conversion

    private func currentImageOrientation() -> UIImage.Orientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        case .portraitUpsideDown: return .left
        default: return .right
        }
    }

    private func uiImage(from pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
            return UIImage()
        }
        return UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let hasPlane = anchors.contains(where: { ($0 as? ARPlaneAnchor)?.alignment == .horizontal })
        if hasPlane {
            Task { @MainActor in
                self.hasHorizontalPlane = true
                self.state = .ready
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            #if DEBUG
            print("ARSession failed: \(error.localizedDescription)")
            #endif
        }
    }
}
