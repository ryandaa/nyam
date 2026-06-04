import Foundation

/// Network client for the Worker's `/chat` endpoint.
///
/// Each call sends the full conversation transcript (the Worker is stateless)
/// plus a compact summary of the user's recent meal history so the assistant
/// has real data to reference. Returns the assistant's reply as plain text.
enum CoachAPI {
    enum APIError: LocalizedError {
        case http(Int, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case let .http(code, msg): return "Coach unavailable (\(code)): \(msg)"
            case let .decode(msg): return "Coach response error: \(msg)"
            }
        }
    }

    /// `historyEntries` should be newest-first. We send up to `maxHistory`
    /// to keep token usage modest — the model gets the most recent meals,
    /// which is what users tend to ask about.
    static let maxHistory = 14

    static func sendMessage(
        transcript: [ChatMessage],
        historyEntries: [HistoryEntry],
        identityToken: String?
    ) async throws -> String {
        var url = NyamAPI.baseURL.appendingPathComponent("chat")
        if NyamAPI.appendDevFlag {
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

        let messages = transcript.map { msg in
            ["role": msg.role.rawValue, "content": msg.text]
        }
        let summary = historyEntries.prefix(maxHistory).map { entry -> [String: Any] in
            let r = entry.result
            return [
                "title": r.title ?? entry.result.items.first?.name ?? "Meal",
                "date": entry.date.formatted(.dateTime.month(.abbreviated).day().year()),
                "calories": r.totals.calories,
                "protein_g": r.totals.proteinG,
                "carbs_g":   r.totals.carbsG,
                "fat_g":     r.totals.fatG,
                "fiber_g":   r.totals.fiberG,
                "sodium_mg": r.totals.sodiumMg,
                "items":     r.items.prefix(5).map { $0.name },
            ]
        }
        let body: [String: Any] = [
            "messages": messages,
            "history_summary": summary,
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
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let reply = obj["reply"] as? String
        else {
            throw APIError.decode("Couldn't read `reply` field")
        }
        return reply
    }
}
