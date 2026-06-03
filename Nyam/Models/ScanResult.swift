import Foundation

/// Mirrors `ScanResult` in `backend/src/types.ts` and the OpenAI structured-output
/// JSON Schema in `backend/src/schema.ts`. Keep all three in sync.
struct ScanResult: Codable, Equatable {
    let plateDetected: Bool
    let items: [ScanItem]
    let totals: ScanTotals

    enum CodingKeys: String, CodingKey {
        case plateDetected = "plate_detected"
        case items
        case totals
    }
}

struct ScanItem: Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let plateAreaPercent: Double
    let estimatedGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case name
        case plateAreaPercent = "plate_area_percent"
        case estimatedGrams = "estimated_grams"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

struct ScanTotals: Codable, Equatable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

extension ScanResult {
    /// Mock data for SwiftUI previews and offline testing.
    static let preview = ScanResult(
        plateDetected: true,
        items: [
            ScanItem(name: "Grilled chicken thigh", plateAreaPercent: 38, estimatedGrams: 145, calories: 326, proteinG: 28, carbsG: 0, fatG: 22),
            ScanItem(name: "Jasmine rice", plateAreaPercent: 34, estimatedGrams: 180, calories: 234, proteinG: 5, carbsG: 51, fatG: 0.5),
            ScanItem(name: "Steamed broccoli", plateAreaPercent: 22, estimatedGrams: 90, calories: 31, proteinG: 2.5, carbsG: 6, fatG: 0.4),
        ],
        totals: ScanTotals(calories: 591, proteinG: 35.5, carbsG: 57, fatG: 22.9)
    )
}

/// A scan plus when it happened. Stored in UserDefaults via `ScanHistory`.
///
/// Hashable conformance keys off `id` only so we can use HistoryEntry as the
/// value type for `NavigationLink(value:)` and `navigationDestination(for:)`.
struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let result: ScanResult

    init(id: UUID = UUID(), date: Date = Date(), result: ScanResult) {
        self.id = id
        self.date = date
        self.result = result
    }

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
