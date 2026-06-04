import SwiftUI

/// Sheet shown after a barcode is successfully scanned and resolved against
/// Open Food Facts. Displays the product + per-serving nutrition + a stepper
/// asking how many servings the user actually ate. Submit logs the result
/// scaled by the chosen servings.
struct PortionFulfillmentView: View {
    @EnvironmentObject var history: ScanHistory
    @Environment(\.dismiss) private var dismiss

    let lookup: BarcodeLookupResult
    let onLogged: () -> Void

    @State private var servings: Double = 1.0

    /// Scaled per-serving nutrition, ready to show.
    private var scaled: ScanTotals? {
        guard let p = lookup.product else { return nil }
        let n = p.nutrition
        let s = servings
        return ScanTotals(
            calories: n.calories * s,
            proteinG: n.proteinG * s,
            carbsG:   n.carbsG * s,
            fatG:     n.fatG * s,
            fiberG:   n.fiberG * s,
            sodiumMg: n.sodiumMg * s
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let product = lookup.product, lookup.found {
                    foundBody(product: product)
                } else {
                    notFoundBody
                }
            }
            .background(Color.NyamSurface.background.ignoresSafeArea())
            .navigationTitle("Log this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if lookup.found {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Log") { logIt() }
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    @ViewBuilder
    private func foundBody(product: BarcodeProduct) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                productHeader(product: product)
                servingStepper(product: product)
                if let totals = scaled {
                    nutritionGrid(totals: totals)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
    }

    private var notFoundBody: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 60)
            ZStack {
                Circle()
                    .fill(Color.NyamSage.shade5.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.NyamSage.shade5)
            }
            VStack(spacing: 8) {
                Text("Couldn't find that product")
                    .font(.title3.weight(.semibold))
                Text(lookup.reason ?? "Open Food Facts doesn't have an entry for barcode \(lookup.barcode). Try logging it manually.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    private func productHeader(product: BarcodeProduct) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: URL(string: product.imageUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    ZStack {
                        Color.NyamSage.tint7
                        Image(systemName: "shippingbox").foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(product.name)
                    .font(.title3.weight(.semibold))
                if let g = product.servingSizeG {
                    Text("Serving: \(Int(g)) g")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                    Text("Open Food Facts · #\(lookup.barcode)")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Color.NyamSage.shade5)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    private func servingStepper(product: BarcodeProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How many servings?")
                .font(.headline)
            HStack(spacing: 16) {
                Button {
                    servings = max(0.25, servings - 0.25)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.NyamSage.shade5)
                }
                Text(servings.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 80)
                Button {
                    servings = min(20, servings + 0.25)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.NyamSage.shade5)
                }
                Spacer()
                if let g = product.servingSizeG {
                    Text("= \(Int(g * servings)) g")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }

    private func nutritionGrid(totals: ScanTotals) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nutrition for \(servings.formatted(.number.precision(.fractionLength(0...2)))) serving\(servings == 1.0 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 8), count: 2), spacing: 8) {
                StatCell(label: "Calories", value: "\(Int(totals.calories.rounded()))", unit: "kcal", emphasized: true)
                StatCell(label: "Protein",  value: "\(Int(totals.proteinG.rounded()))", unit: "g")
                StatCell(label: "Carbs",    value: "\(Int(totals.carbsG.rounded()))", unit: "g")
                StatCell(label: "Fat",      value: "\(Int(totals.fatG.rounded()))", unit: "g")
                StatCell(label: "Fiber",    value: "\(Int(totals.fiberG.rounded()))", unit: "g")
                StatCell(label: "Sodium",   value: "\(Int(totals.sodiumMg.rounded()))", unit: "mg")
            }
        }
    }

    private func logIt() {
        guard let product = lookup.product else { return }
        let result = product.asScanResult(servings: servings)
        history.record(result, image: nil)
        onLogged()
        dismiss()
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    let unit: String
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(emphasized ? .title2.bold().monospacedDigit() : .title3.bold().monospacedDigit())
                    .foregroundStyle(emphasized ? Color.NyamSage.shade5 : Color.primary)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.NyamSurface.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
        )
    }
}

#Preview("Found") {
    PortionFulfillmentView(
        lookup: BarcodeLookupResult(
            found: true,
            barcode: "049000028911",
            product: BarcodeProduct(
                name: "Diet Coke",
                brand: "Coca-Cola",
                imageUrl: nil,
                servingSizeG: 355,
                nutrition: ScanTotals(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sodiumMg: 40)
            ),
            reason: nil
        ),
        onLogged: {}
    )
    .environmentObject(ScanHistory())
}

#Preview("Not found") {
    PortionFulfillmentView(
        lookup: BarcodeLookupResult(found: false, barcode: "0000", product: nil, reason: "Product not in Open Food Facts"),
        onLogged: {}
    )
    .environmentObject(ScanHistory())
}
