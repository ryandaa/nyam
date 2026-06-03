import SwiftUI

struct ResultsView: View {
    let result: ScanResult
    let onScanAgain: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TotalsCard(totals: result.totals)
                        .padding(.top, 8)

                    if result.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(result.items) { item in
                            ItemCard(item: item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Your plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Scan again", action: onScanAgain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("We couldn't identify any food on this plate.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Totals

private struct TotalsCard: View {
    let totals: ScanTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Total")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(totals.calories.rounded()))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                Text("kcal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                MacroPill(label: "Protein", grams: totals.proteinG, color: .blue)
                MacroPill(label: "Carbs", grams: totals.carbsG, color: .orange)
                MacroPill(label: "Fat", grams: totals.fatG, color: .pink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MacroPill: View {
    let label: String
    let grams: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(grams.rounded()))g")
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Per-item

private struct ItemCard: View {
    let item: ScanItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.capitalized)
                        .font(.headline)
                    Text("\(Int(item.estimatedGrams.rounded()))g · \(String(format: "%.0f", item.plateAreaPercent))% of plate")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(item.calories.rounded()))")
                        .font(.title3.bold().monospacedDigit())
                    Text("kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                MacroChip(label: "P", grams: item.proteinG, color: .blue)
                MacroChip(label: "C", grams: item.carbsG, color: .orange)
                MacroChip(label: "F", grams: item.fatG, color: .pink)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MacroChip: View {
    let label: String
    let grams: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(color)
            Text("\(Int(grams.rounded()))g")
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10), in: Capsule())
    }
}

#Preview {
    ResultsView(result: .preview, onScanAgain: {})
}
