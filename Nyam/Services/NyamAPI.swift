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

    static func scan(image: UIImage, plateDiameterCm: Double, identityToken: String?) async throws -> ScanResult {
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
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
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "image_base64": base64,
            "plate_diameter_cm": plateDiameterCm,
        ]
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
}
