import Foundation

/// Mirrors `MenuResult` in `backend/src/menu.ts`. Returned by the Worker's
/// `/menu` endpoint when the user captures a restaurant menu photo.
struct MenuResult: Codable, Equatable {
    let restaurantName: String?
    let dishes: [MenuDish]

    enum CodingKeys: String, CodingKey {
        case restaurantName = "restaurant_name"
        case dishes
    }
}

struct MenuDish: Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let description: String?
    let estimatedGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let sodiumMg: Double

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case estimatedGrams = "estimated_grams"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sodiumMg = "sodium_mg"
    }
}

extension MenuDish {
    /// Build a one-item ScanResult so this dish can be logged via the
    /// existing ScanHistory.record path.
    func asScanResult() -> ScanResult {
        let item = ScanItem(
            name: name,
            plateAreaPercent: 0,
            widthCm: 0, depthCm: 0, heightCm: 0,
            estimatedGrams: estimatedGrams,
            calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG,
            fiberG: fiberG, sodiumMg: sodiumMg,
            nutritionSource: .model,    // menu estimates are LLM-derived
            usdaFdcId: nil, usdaDescription: nil
        )
        let totals = ScanTotals(
            calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG,
            fiberG: fiberG, sodiumMg: sodiumMg
        )
        return ScanResult(
            plateDetected: false,
            title: name,
            items: [item],
            totals: totals
        )
    }
}

extension MenuResult {
    static let preview = MenuResult(
        restaurantName: "Sample Bistro",
        dishes: [
            MenuDish(name: "Grilled Salmon Bowl", description: "Atlantic salmon, jasmine rice, charred broccoli",
                     estimatedGrams: 400, calories: 620, proteinG: 38, carbsG: 52, fatG: 25, fiberG: 4, sodiumMg: 620),
            MenuDish(name: "Caesar Salad", description: "Romaine, parmesan, anchovy dressing, croutons",
                     estimatedGrams: 280, calories: 410, proteinG: 9, carbsG: 18, fatG: 32, fiberG: 3, sodiumMg: 740),
            MenuDish(name: "Margherita Pizza", description: "12-inch, fresh mozzarella, basil",
                     estimatedGrams: 540, calories: 980, proteinG: 36, carbsG: 110, fatG: 38, fiberG: 5, sodiumMg: 1480),
        ]
    )
}

// MARK: - Open Food Facts barcode lookup

struct BarcodeLookupResult: Codable, Equatable {
    let found: Bool
    let barcode: String
    let product: BarcodeProduct?
    let reason: String?
}

struct BarcodeProduct: Codable, Equatable {
    let name: String
    let brand: String?
    let imageUrl: String?
    let servingSizeG: Double?
    let nutrition: ScanTotals

    enum CodingKeys: String, CodingKey {
        case name
        case brand
        case imageUrl = "image_url"
        case servingSizeG = "serving_size_g"
        case nutrition
    }
}

extension BarcodeProduct {
    /// Build a one-item ScanResult scaled by the number of servings the user
    /// ate (typically a 0.25-step user-selected stepper value).
    func asScanResult(servings: Double) -> ScanResult {
        let item = ScanItem(
            name: [brand, name].compactMap { $0 }.joined(separator: " — "),
            plateAreaPercent: 0,
            widthCm: 0, depthCm: 0, heightCm: 0,
            estimatedGrams: (servingSizeG ?? 0) * servings,
            calories: nutrition.calories * servings,
            proteinG: nutrition.proteinG * servings,
            carbsG:   nutrition.carbsG * servings,
            fatG:     nutrition.fatG * servings,
            fiberG:   nutrition.fiberG * servings,
            sodiumMg: nutrition.sodiumMg * servings,
            nutritionSource: .openFoodFacts,
            usdaFdcId: nil,
            usdaDescription: nil
        )
        let totals = ScanTotals(
            calories: item.calories, proteinG: item.proteinG, carbsG: item.carbsG, fatG: item.fatG,
            fiberG: item.fiberG, sodiumMg: item.sodiumMg
        )
        return ScanResult(
            plateDetected: false,
            title: name,
            items: [item],
            totals: totals
        )
    }
}
