import Foundation

/// Mirrors `ScanResult` in `backend/src/types.ts` and the OpenAI structured-output
/// JSON Schema in `backend/src/schema.ts`. Keep all three in sync.
struct ScanResult: Codable, Equatable {
    let plateDetected: Bool
    /// Catchy short meal title produced by the vision model (≤5 words,
    /// title-cased). Optional on the iOS side so older v2 history entries
    /// (which predate this field) still decode.
    let title: String?
    let items: [ScanItem]
    let totals: ScanTotals

    enum CodingKeys: String, CodingKey {
        case plateDetected = "plate_detected"
        case title
        case items
        case totals
    }
}

enum NutritionSource: String, Codable, Equatable {
    /// Looked up in USDA FoodData Central, scaled by the model's grams estimate.
    case usda
    /// Vision model's own knowledge (USDA had no good match).
    case model
    /// User entered the macros by hand via ManualEntryView.
    case manual
    /// Looked up in Open Food Facts by UPC/EAN barcode.
    case openFoodFacts = "open_food_facts"
}

struct ScanItem: Codable, Equatable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let plateAreaPercent: Double
    let widthCm: Double
    let depthCm: Double
    let heightCm: Double
    let estimatedGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let sodiumMg: Double
    /// Provenance: did this item's macros come from USDA FoodData Central
    /// (scaled by the model's grams estimate) or from the model's own
    /// nutrition knowledge? Set server-side, optional for back-compat.
    let nutritionSource: NutritionSource?
    let usdaFdcId: Int?
    let usdaDescription: String?

    enum CodingKeys: String, CodingKey {
        case name
        case plateAreaPercent = "plate_area_percent"
        case widthCm = "width_cm"
        case depthCm = "depth_cm"
        case heightCm = "height_cm"
        case estimatedGrams = "estimated_grams"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sodiumMg = "sodium_mg"
        case nutritionSource = "nutrition_source"
        case usdaFdcId = "usda_fdc_id"
        case usdaDescription = "usda_description"
    }
}

struct ScanTotals: Codable, Equatable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let sodiumMg: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sodiumMg = "sodium_mg"
    }
}

extension ScanResult {
    /// Mock data for SwiftUI previews and offline testing.
    static let preview = ScanResult(
        plateDetected: true,
        title: "Grilled Chicken & Veggies",
        items: [
            ScanItem(
                name: "Grilled chicken thigh",
                plateAreaPercent: 38, widthCm: 11, depthCm: 8, heightCm: 3,
                estimatedGrams: 145,
                calories: 326, proteinG: 28, carbsG: 0, fatG: 22,
                fiberG: 0, sodiumMg: 380,
                nutritionSource: .usda, usdaFdcId: 173627,
                usdaDescription: "Chicken, broilers or fryers, thigh, meat only, cooked, roasted"
            ),
            ScanItem(
                name: "Jasmine rice",
                plateAreaPercent: 34, widthCm: 10, depthCm: 9, heightCm: 2.5,
                estimatedGrams: 180,
                calories: 234, proteinG: 5, carbsG: 51, fatG: 0.5,
                fiberG: 0.7, sodiumMg: 5,
                nutritionSource: .usda, usdaFdcId: 168878,
                usdaDescription: "Rice, white, long-grain, regular, cooked, unenriched"
            ),
            ScanItem(
                name: "Steamed broccoli",
                plateAreaPercent: 22, widthCm: 9, depthCm: 7, heightCm: 2.5,
                estimatedGrams: 90,
                calories: 31, proteinG: 2.5, carbsG: 6, fatG: 0.4,
                fiberG: 2.4, sodiumMg: 30,
                nutritionSource: .model, usdaFdcId: nil, usdaDescription: nil
            ),
        ],
        totals: ScanTotals(
            calories: 591, proteinG: 35.5, carbsG: 57, fatG: 22.9,
            fiberG: 3.1, sodiumMg: 415
        )
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
    /// Relative path under `Documents/` to the captured JPEG. Optional so old
    /// entries (and image-save failures) still render — feed will show a
    /// placeholder card in that case.
    let imagePath: String?

    init(id: UUID = UUID(), date: Date = Date(), result: ScanResult, imagePath: String? = nil) {
        self.id = id
        self.date = date
        self.result = result
        self.imagePath = imagePath
    }

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
