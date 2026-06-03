import Foundation
import Vision
import CoreImage
import UIKit

/// Detects the largest near-circular shape in an image — meant to be the plate.
///
/// Uses `VNDetectContoursRequest` (good for round-ish objects) and falls back to
/// `VNDetectRectanglesRequest` if no good contour is found. Returns a unit-square
/// normalized ellipse (origin at top-left, +Y down) — the same coordinate space
/// SwiftUI uses for previews.
struct DetectedPlate {
    /// Center of the ellipse, normalized to [0,1] x [0,1] in image space (Y-down).
    let center: CGPoint
    /// Width and height of the bounding box, normalized to [0,1].
    let size: CGSize
    /// Confidence in [0,1]. Higher = more plate-like.
    let confidence: Double
}

enum PlateDetector {
    /// Run plate detection on a still image. Synchronous, suitable for use after capture.
    /// Returns nil if no plausible plate is found.
    static func detect(in image: UIImage) -> DetectedPlate? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.5
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 1024

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return rectangleFallback(cgImage: cgImage)
        }

        guard let observation = request.results?.first as? VNContoursObservation else {
            return rectangleFallback(cgImage: cgImage)
        }

        // Walk top-level contours, pick the one whose bbox is most circle-like and largest.
        var best: (rect: CGRect, score: Double)?
        for i in 0..<observation.topLevelContourCount {
            guard let contour = try? observation.topLevelContour(at: i) else { continue }
            // Vision contours use a unit normalized coord space, Y-up.
            let bbox = contour.normalizedPath.boundingBox
            let area = Double(bbox.width * bbox.height)
            if area < 0.05 { continue } // ignore tiny contours
            let aspect = Double(bbox.width / max(bbox.height, 0.0001))
            let aspectScore = 1.0 - min(abs(aspect - 1.0), 1.0) // 1.0 when square/circle
            let score = aspectScore * area
            if best == nil || score > best!.score {
                best = (bbox, score)
            }
        }

        guard let chosen = best, chosen.score > 0.05 else {
            return rectangleFallback(cgImage: cgImage)
        }

        // Convert Y-up Vision space → Y-down SwiftUI/UIImage space.
        let yDown = 1.0 - chosen.rect.origin.y - chosen.rect.height
        let normalized = CGRect(x: chosen.rect.origin.x, y: yDown, width: chosen.rect.width, height: chosen.rect.height)

        return DetectedPlate(
            center: CGPoint(x: normalized.midX, y: normalized.midY),
            size: normalized.size,
            confidence: chosen.score
        )
    }

    private static func rectangleFallback(cgImage: CGImage) -> DetectedPlate? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumAspectRatio = 0.7
        request.maximumAspectRatio = 1.3
        request.minimumSize = 0.2
        request.minimumConfidence = 0.5

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }
        // Vision rectangles use Y-up normalized coords with .boundingBox.
        let bbox = observation.boundingBox
        let yDown = 1.0 - bbox.origin.y - bbox.height
        let normalized = CGRect(x: bbox.origin.x, y: yDown, width: bbox.width, height: bbox.height)

        return DetectedPlate(
            center: CGPoint(x: normalized.midX, y: normalized.midY),
            size: normalized.size,
            confidence: Double(observation.confidence)
        )
    }
}
