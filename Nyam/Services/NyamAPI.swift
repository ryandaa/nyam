import Foundation
import UIKit

/// Network client for the Cloudflare Worker.
///
/// Point `baseURL` at:
///   - your deployed Worker (`https://nyam-backend.<subdomain>.workers.dev`), or
///   - your local Worker for development (`http://<mac-lan-ip>:8787`)
///
/// For local dev, append `?dev=1` to skip Apple JWT verification:
///   `static let baseURL = URL(string: "10.31.98.79")!`
///   `static let appendDevFlag = true`
enum NyamAPI {
    /// EDIT ME before running: point at your deployed Worker or your Mac's LAN IP.
    static let baseURL = URL(string: "https://nyam-backend.ryandaa.workers.dev")!

    /// When true, append `?dev=1` so the Worker skips auth verification.
    /// Required in V1 because we ship a stub token (free Apple Developer tier
    /// can't sign apps with Sign in with Apple).
    static let appendDevFlag = true

    enum APIError: LocalizedError {
        case badImage
        case http(Int, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .badImage: return "Could not encode image."
            case let .http(code, msg): return "Server error (\(code)): \(msg)"
            case let .decode(msg): return "Bad response: \(msg)"
            }
        }
    }

    /// Max edge length of the image we upload. GPT-4o vision processes at
    /// 768x768 / 2048x2048 internally so anything larger is wasted upload
    /// time. iPhone Pro photos can be 4032 px wide — without this they'd
    /// be ~5 MB of base64 and Cloudflare drops the connection mid-stream.
    static let maxUploadDimension: CGFloat = 1536

    static func scan(
        image: UIImage,
        plateDiameterCm: Double?,
        foodVolumeCm3: Double? = nil,
        identityToken: String?
    ) async throws -> ScanResult {
        let downscaled = downscaled(image, maxDimension: maxUploadDimension)
        guard let jpeg = downscaled.jpegData(compressionQuality: 0.6) else {
            throw APIError.badImage
        }
        let base64 = jpeg.base64EncodedString()

        var url = baseURL.appendingPathComponent("scan")
        if appendDevFlag {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "dev", value: "1")]
            if let resolved = components?.url { url = resolved }
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = identityToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // GPT-4o vision is typically 10–25s end-to-end; give plenty of
        // headroom so a slow cellular upload doesn't get killed first.
        req.timeoutInterval = 120

        var body: [String: Any] = [
            "image_base64": base64,
        ]
        if let plateDiameterCm {
            body["plate_diameter_cm"] = plateDiameterCm
        }
        if let foodVolumeCm3 {
            body["food_volume_cm3"] = foodVolumeCm3
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decode("Non-HTTP response")
        }
        if http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.http(http.statusCode, msg)
        }

        do {
            return try JSONDecoder().decode(ScanResult.self, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }

    // MARK: - V5.1: Menu scanning

    static func scanMenu(image: UIImage, identityToken: String?) async throws -> MenuResult {
        let downscaled = downscaled(image, maxDimension: maxUploadDimension)
        guard let jpeg = downscaled.jpegData(compressionQuality: 0.6) else {
            throw APIError.badImage
        }
        let base64 = jpeg.base64EncodedString()

        var url = baseURL.appendingPathComponent("menu")
        if appendDevFlag {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "dev", value: "1")]
            if let resolved = components?.url { url = resolved }
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = identityToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 120
        req.httpBody = try JSONSerialization.data(withJSONObject: ["image_base64": base64])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decode("Non-HTTP response")
        }
        if http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.http(http.statusCode, msg)
        }
        do {
            return try JSONDecoder().decode(MenuResult.self, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }

    // MARK: - V5.1: Barcode lookup

    static func lookupBarcode(_ code: String) async throws -> BarcodeLookupResult {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = baseURL.appendingPathComponent("barcode").appendingPathComponent(cleanCode)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decode("Non-HTTP response")
        }
        if http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "<binary>"
            throw APIError.http(http.statusCode, msg)
        }
        do {
            return try JSONDecoder().decode(BarcodeLookupResult.self, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Aspect-preserving downscale so the longest edge is `maxDimension`.
    /// Returns the original image if it's already small enough.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
