import SwiftUI

/// Detail view for a single ScanItem — pushed when the user taps a card in
/// ResultsView. Top-right Edit button flips into edit mode where every macro
/// is a number-pad text field. Save commits the edited item back via the
/// `onSave` callback. The parent view (ResultsView) handles recomputing
/// totals and persisting to ScanHistory.
struct ItemDetailView: View {
    let item: ScanItem
    let onSave: (ScanItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isEditing: Bool
    @State private var name: String
    @State private var grams: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber: String
    @State private var sodium: String

    init(item: ScanItem, onSave: @escaping (ScanItem) -> Void) {
        self.item = item
        self.onSave = onSave
        self._isEditing = State(initialValue: false)
        self._name = State(initialValue: item.name)
        self._grams = State(initialValue: ItemDetailView.format(item.estimatedGrams))
        self._calories = State(initialValue: ItemDetailView.format(item.calories))
        self._protein = State(initialValue: ItemDetailView.format(item.proteinG, places: 1))
        self._carbs = State(initialValue: ItemDetailView.format(item.carbsG, places: 1))
        self._fat = State(initialValue: ItemDetailView.format(item.fatG, places: 1))
        self._fiber = State(initialValue: ItemDetailView.format(item.fiberG, places: 1))
        self._sodium = State(initialValue: ItemDetailView.format(item.sodiumMg))
    }

    var body: some View {
        Form {
            Section("Item") {
                if isEditing {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                } else {
                    LabeledContent("Name", value: item.name.capitalized)
                }
                if isEditing {
                    macroRow("Grams", binding: $grams, unit: "g")
                } else {
                    LabeledContent("Grams", value: "\(Int(item.estimatedGrams.rounded())) g")
                }
            }

            Section("Nutrition") {
                if isEditing {
                    macroRow("Calories", binding: $calories, unit: "cal")
                    macroRow("Protein", binding: $protein, unit: "g")
                    macroRow("Carbs", binding: $carbs, unit: "g")
                    macroRow("Fat", binding: $fat, unit: "g")
                    macroRow("Fiber", binding: $fiber, unit: "g")
                    macroRow("Sodium", binding: $sodium, unit: "mg")
                } else {
                    macroDisplay("Calories", value: item.calories, unit: "cal", emphasized: true)
                    macroDisplay("Protein", value: item.proteinG, unit: "g")
                    macroDisplay("Carbs", value: item.carbsG, unit: "g")
                    macroDisplay("Fat", value: item.fatG, unit: "g")
                    macroDisplay("Fiber", value: item.fiberG, unit: "g")
                    macroDisplay("Sodium", value: item.sodiumMg, unit: "mg")
                }
            }

            if !isEditing, let source = item.nutritionSource {
                Section("Source") {
                    sourceRow(for: source)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit item" : item.name.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        commit()
                        dismiss()
                    } else {
                        isEditing = true
                    }
                }
                .font(.body.weight(.semibold))
            }
            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        resetDraft()
                        isEditing = false
                    }
                }
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    // MARK: - Components

    @ViewBuilder
    private func macroRow(_ label: String, binding: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: binding)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 90)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    @ViewBuilder
    private func macroDisplay(_ label: String, value: Double, unit: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(format(value, isWhole: unit == "cal" || unit == "mg"))
                    .font(emphasized ? .body.weight(.semibold).monospacedDigit() : .body.monospacedDigit())
                    .foregroundStyle(emphasized ? Color.NyamSage.shade5 : .primary)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sourceRow(for source: NutritionSource) -> some View {
        HStack {
            switch source {
            case .usda:
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.NyamSage.shade5)
                Text("USDA FoodData Central")
                Spacer()
                if let desc = item.usdaDescription {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            case .openFoodFacts:
                Image(systemName: "barcode")
                    .foregroundStyle(Color.NyamSage.shade5)
                Text("Open Food Facts")
            case .manual:
                Image(systemName: "pencil")
                Text("Manual entry")
            case .model:
                Image(systemName: "sparkles")
                Text("AI estimate")
            }
        }
    }

    // MARK: - Helpers

    private static func format(_ v: Double, places: Int = 0) -> String {
        if places == 0 { return String(Int(v.rounded())) }
        return String(format: "%.\(places)f", v)
    }

    private func format(_ v: Double, isWhole: Bool) -> String {
        isWhole ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }

    private func resetDraft() {
        name = item.name
        grams = ItemDetailView.format(item.estimatedGrams)
        calories = ItemDetailView.format(item.calories)
        protein = ItemDetailView.format(item.proteinG, places: 1)
        carbs = ItemDetailView.format(item.carbsG, places: 1)
        fat = ItemDetailView.format(item.fatG, places: 1)
        fiber = ItemDetailView.format(item.fiberG, places: 1)
        sodium = ItemDetailView.format(item.sodiumMg)
    }

    private func commit() {
        let new = ScanItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            plateAreaPercent: item.plateAreaPercent,
            widthCm: item.widthCm,
            depthCm: item.depthCm,
            heightCm: item.heightCm,
            estimatedGrams: Double(grams) ?? item.estimatedGrams,
            calories: Double(calories) ?? item.calories,
            proteinG: Double(protein) ?? item.proteinG,
            carbsG: Double(carbs) ?? item.carbsG,
            fatG: Double(fat) ?? item.fatG,
            fiberG: Double(fiber) ?? item.fiberG,
            sodiumMg: Double(sodium) ?? item.sodiumMg,
            // User-edited values lose their original USDA/OFF/AI provenance —
            // mark as manual so the badge in the feed is honest.
            nutritionSource: .manual,
            usdaFdcId: nil,
            usdaDescription: nil
        )
        onSave(new)
    }
}

#Preview {
    NavigationStack {
        ItemDetailView(item: ScanResult.preview.items.first!, onSave: { _ in })
    }
}
