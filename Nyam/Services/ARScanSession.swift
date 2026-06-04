import Foundation
import ARKit
import Combine
import RealityKit
import UIKit
import Vision
import simd

/// Which measurement tier this device + session can actually deliver.
/// Picked at runtime; informs the demo's honest disclosure of accuracy.
enum MeasurementTier: String, Codable {
    /// iPhone Pro with LiDAR — sceneDepth gives real 3D volume per pixel.
    case lidar
    /// Any iPhone with ARKit world tracking — plate diameter measured via raycast,
    /// per-item heights still estimated by the model.
    case ar
    /// No AR session available (simulator, library photo, AR failed) — user must
    /// confirm plate diameter manually via the CalibrationSheet.
    case manual

    var displayName: String {
        switch self {
        case .lidar:  return "LiDAR · 3D"
        case .ar:     return "AR · plate"
        case .manual: return "Standard"
        }
    }

    var icon: String {
        switch self {
        case .lidar:  return "cube.transparent.fill"
        case .ar:     return "camera.metering.center.weighted"
        case .manual: return "ruler"
        }
    }
}

/// Captured ARKit measurement. `diameterCm` is what V3 produces; `foodVolumeCm3`
/// is the LiDAR bonus on Pro phones. Both nil = falls back to manual sheet.
struct ARMeasurement {
    let image: UIImage
    let diameterCm: Double?
    let foodVolumeCm3: Double?
    let tier: MeasurementTier
}

/// ARKit-backed scan session: detects the table as a horizontal plane, computes
/// the **real-world plate diameter in cm** by combining Vision's plate-ellipse
/// detection with an ARKit raycast onto the plane. On Pro iPhones, also reads
/// `ARFrame.sceneDepth` and computes total food volume in cm³ above the plate.
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
    @Published private(set) var tier: MeasurementTier = .ar

    private var hasHorizontalPlane: Bool = false

    /// Whether we asked for sceneDepth at session start. Set in start().
    private var sceneDepthEnabled: Bool = false

    override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            state = .unsupported
            tier = .manual
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.worldAlignment = .gravity

        // LiDAR upgrade: on iPhone Pro, ask for sceneDepth so we can do real
        // 3D volume reconstruction. supportsFrameSemantics returns false on
        // every non-Pro device → tier stays .ar.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            sceneDepthEnabled = true
            tier = .lidar
        } else {
            sceneDepthEnabled = false
            tier = .ar
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        state = .lookingForPlane
    }

    func stop() {
        session.pause()
    }

    // MARK: - Capture

    /// Capture the current AR frame, run plate detection, raycast to the plane
    /// for diameter, and on LiDAR-capable phones also sample sceneDepth for
    /// total food volume.
    func captureScan() -> ARMeasurement {
        guard let frame = session.currentFrame else {
            return ARMeasurement(image: UIImage(), diameterCm: nil, foodVolumeCm3: nil, tier: .manual)
        }
        let image = uiImage(from: frame.capturedImage, orientation: currentImageOrientation())

        // V3 plate-anchored diameter (works on every AR-capable phone)
        let diameter = computePlateDiameterCm(frame: frame, image: image)

        // LiDAR bonus volume (Pro only). Requires we successfully computed
        // the plate's world position too — that's the floor of the volume integral.
        let volume: Double?
        if tier == .lidar, diameter != nil {
            volume = computeFoodVolumeCm3(frame: frame, image: image)
        } else {
            volume = nil
        }

        let resolvedTier: MeasurementTier
        if diameter == nil {
            resolvedTier = .manual    // AR couldn't measure → CalibrationSheet path
        } else if volume != nil {
            resolvedTier = .lidar
        } else {
            resolvedTier = .ar
        }

        return ARMeasurement(image: image, diameterCm: diameter, foodVolumeCm3: volume, tier: resolvedTier)
    }

    // MARK: - Plate diameter (every AR phone)

    /// 1. Run `PlateDetector` on the captured still to locate the plate ellipse.
    /// 2. Raycast from the plate's screen-space center onto the detected
    ///    horizontal plane to get the plate's 3D world position.
    /// 3. Distance from camera to that world point ≈ overhead height to plate.
    /// 4. real_radius = pixel_radius * distance / focal_length_px.
    private func computePlateDiameterCm(frame: ARFrame, image: UIImage) -> Double? {
        guard hasHorizontalPlane,
              let plate = PlateDetector.detect(in: image)
        else { return nil }

        let imgSize = image.size
        let centerPx = CGPoint(
            x: plate.center.x * imgSize.width,
            y: plate.center.y * imgSize.height
        )

        let query = frame.raycastQuery(
            from: centerPx,
            allowing: .estimatedPlane,
            alignment: .horizontal
        )
        let results = session.raycast(query)
        guard let hit = results.first else { return nil }

        let camT = frame.camera.transform.columns.3
        let cameraPos = SIMD3<Float>(camT.x, camT.y, camT.z)
        let hitT = hit.worldTransform.columns.3
        let hitPos = SIMD3<Float>(hitT.x, hitT.y, hitT.z)
        let distanceM = simd_distance(cameraPos, hitPos)

        let widthPx = plate.size.width * imgSize.width
        let heightPx = plate.size.height * imgSize.height
        let pixelDiameter = max(widthPx, heightPx)

        let intrinsics = frame.camera.intrinsics
        let fx = Double(intrinsics.columns.0.x)
        guard fx > 0 else { return nil }

        let diameterM = Double(pixelDiameter) * Double(distanceM) / fx
        let diameterCm = diameterM * 100
        guard diameterCm >= 12, diameterCm <= 40 else { return nil }
        return diameterCm
    }

    // MARK: - LiDAR food volume (Pro phones with sceneDepth)

    /// Compute the total food volume on the plate by sampling the LiDAR depth
    /// map. For each depth pixel above the detected plate plane (i.e. depth
    /// closer than the plate's depth), accumulate `height_above_plate × pixel_area`.
    ///
    /// The math:
    ///   - For a depth pixel at distance d, with the camera's depth-map
    ///     focal length fx_d, fy_d, the pixel covers d/fx_d × d/fy_d meters
    ///     of real area at that depth.
    ///   - height_above_plate = plate_distance - pixel_depth (positive iff food)
    ///   - contribution = height × area (m³, converted to cm³)
    ///
    /// We restrict sampling to depth pixels whose backprojected (x, z) lies
    /// inside the plate's world disk — otherwise the user's hand, the table
    /// edge, etc. would all count as "food".
    private func computeFoodVolumeCm3(frame: ARFrame, image: UIImage) -> Double? {
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else { return nil }
        guard let plate = PlateDetector.detect(in: image) else { return nil }

        // Re-do the raycast to get the plate's world position + the plane Y
        let imgSize = image.size
        let centerPx = CGPoint(
            x: plate.center.x * imgSize.width,
            y: plate.center.y * imgSize.height
        )
        let query = frame.raycastQuery(from: centerPx, allowing: .estimatedPlane, alignment: .horizontal)
        let results = session.raycast(query)
        guard let hit = results.first else { return nil }
        let plateWorld = SIMD3<Float>(
            hit.worldTransform.columns.3.x,
            hit.worldTransform.columns.3.y,
            hit.worldTransform.columns.3.z
        )

        let camTransform = frame.camera.transform

        // Camera intrinsics scale: the RGB image and the depth map are
        // different resolutions. ARKit's intrinsics are for the capturedImage,
        // so we scale them by (depthWidth / imageWidth, depthHeight / imageHeight).
        let depthMap = depthData.depthMap
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let imageRes = frame.camera.imageResolution
        let sx = Float(depthWidth) / Float(imageRes.width)
        let sy = Float(depthHeight) / Float(imageRes.height)
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics.columns.0.x * sx
        let fy = intrinsics.columns.1.y * sy
        let cx = intrinsics.columns.2.x * sx
        let cy = intrinsics.columns.2.y * sy

        // Plate radius in real meters (we already have diameter, but recompute
        // from the world disk: project the plate ellipse's width onto the plane).
        let plateRadiusM: Float = {
            let widthPx = Float(plate.size.width * imgSize.width)
            let camPos = SIMD3<Float>(camTransform.columns.3.x, camTransform.columns.3.y, camTransform.columns.3.z)
            let distance = simd_distance(camPos, plateWorld)
            return (widthPx * distance) / intrinsics.columns.0.x / 2
        }()

        // Lock depth + confidence buffers for raw access.
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
        let depthPtr = depthBase.assumingMemoryBound(to: Float32.self)

        let confidenceMap = depthData.confidenceMap
        var confidencePtr: UnsafePointer<UInt8>?
        var confidenceStride = 0
        if let cMap = confidenceMap {
            CVPixelBufferLockBaseAddress(cMap, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(cMap) {
                confidencePtr = UnsafePointer<UInt8>(base.assumingMemoryBound(to: UInt8.self))
                confidenceStride = CVPixelBufferGetBytesPerRow(cMap)
            }
        }
        defer {
            if let cMap = confidenceMap { CVPixelBufferUnlockBaseAddress(cMap, .readOnly) }
        }

        var totalVolumeM3: Double = 0
        let plateY = plateWorld.y
        let plateXZ = SIMD2<Float>(plateWorld.x, plateWorld.z)

        for v in 0..<depthHeight {
            for u in 0..<depthWidth {
                // High-confidence depth pixels only (ARConfidenceLevel: 0/1/2; we want >= 1).
                if let cPtr = confidencePtr {
                    let conf = cPtr[v * confidenceStride + u]
                    if conf == 0 { continue }
                }
                let d = depthPtr[v * depthStride + u]
                if !d.isFinite || d <= 0 || d > 3 { continue } // sanity bound (0–3 m)

                // Back-project pixel (u, v) at depth d into camera space.
                let xCam = (Float(u) - cx) * d / fx
                let yCam = (Float(v) - cy) * d / fy
                let pCam = SIMD4<Float>(xCam, yCam, -d, 1) // ARKit camera is -Z forward
                let pWorld4 = camTransform * pCam
                let pWorld = SIMD3<Float>(pWorld4.x, pWorld4.y, pWorld4.z)

                // Mask: must be inside plate disk (XZ plane) and above plate.
                let dxz = SIMD2<Float>(pWorld.x, pWorld.z) - plateXZ
                if simd_length(dxz) > plateRadiusM { continue }

                let h = pWorld.y - plateY
                if h <= 0 { continue }       // below plate plane (probably noise) — skip
                if h > 0.20 { continue }     // > 20 cm above plate is implausible — clip

                // Real area per depth pixel at depth d
                let areaM2 = (d * d) / (fx * fy)
                totalVolumeM3 += Double(h) * Double(areaM2)
            }
        }

        let volumeCm3 = totalVolumeM3 * 1_000_000  // 1 m³ = 10⁶ cm³

        // Sanity: a typical plate has 100–1500 cm³ of food. Anything outside
        // is almost certainly a measurement artifact (noisy plane, lighting, etc.).
        guard volumeCm3 > 30, volumeCm3 < 3000 else { return nil }
        return volumeCm3
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
