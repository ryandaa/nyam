import SwiftUI

struct ResultsView: View {
    let result: ScanResult
    /// When non-nil, the top-right "Scan again" button is shown — used for the
    /// fresh-scan flow. Pass nil when this view is pushed from history (the
    /// nav-stack back button handles dismissal).
    let onScanAgain: (() -> Void)?

    private var navTitle: String {
        if let t = result.title, !t.isEmpty { return t }
        return "Your plate"
    }

    var body: some View {
        content
            .background(Color.NyamSurface.background.ignoresSafeArea())
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onScanAgain {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Scan again", action: onScanAgain)
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if onScanAgain != nil {
            // Fresh-scan flow: wrap in its own NavigationStack so the toolbar shows.
            NavigationStack { scrollBody }
        } else {
            // Pushed from a parent stack (history): inherit that stack.
            scrollBody
        }
    }

    private var scrollBody: some View {
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
                    .foregroundStyle(Color.accentColor)
                Text("kcal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                MacroPill(label: "Protein", value: "\(Int(totals.proteinG.rounded()))", unit: "g", intensity: 1.0)
                MacroPill(label: "Fiber",   value: "\(Int(totals.fiberG.rounded()))",   unit: "g", intensity: 0.72)
                MacroPill(label: "Sodium",  value: "\(Int(totals.sodiumMg.rounded()))", unit: "mg", intensity: 0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.NyamSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MacroPill: View {
    let label: String
    let value: String
    let unit: String
    /// 1.0 = full accent, 0.5 = half — used to differentiate stats in the same
    /// hue without resorting to off-palette colors.
    let intensity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.accentColor.opacity(0.55 + 0.45 * intensity))
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color.accentColor.opacity(0.06 + 0.06 * intensity),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}

// MARK: - Per-item

private struct ItemCard: View {
    let item: ScanItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name.capitalized)
                        .font(.headline)
                    Text("\(Int(item.estimatedGrams.rounded()))g · \(String(format: "%.0f", item.plateAreaPercent))% of plate")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    NutritionSourceBadge(item: item)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(item.calories.rounded()))")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                    Text("kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // All five micros for the detail row, headlines (P/Fi/Na) emphasized.
            HStack(spacing: 6) {
                MacroChip(label: "P",  value: "\(Int(item.proteinG.rounded()))", unit: "g",  emphasized: true)
                MacroChip(label: "Fi", value: "\(Int(item.fiberG.rounded()))",   unit: "g",  emphasized: true)
                MacroChip(label: "Na", value: "\(Int(item.sodiumMg.rounded()))", unit: "mg", emphasized: true)
                MacroChip(label: "C",  value: "\(Int(item.carbsG.rounded()))",   unit: "g",  emphasized: false)
                MacroChip(label: "F",  value: "\(Int(item.fatG.rounded()))",     unit: "g",  emphasized: false)
            }
        }
        .padding(16)
        .background(Color.NyamSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Small chip in the corner of each item card showing where the nutrition
/// numbers came from. "USDA" means the macros were scaled from FoodData
/// Central's per-100g values; "Estimate" means USDA had no good match and
/// these are the vision model's own numbers.
private struct NutritionSourceBadge: View {
    let item: ScanItem

    var body: some View {
        switch item.nutritionSource {
        case .usda:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                Text("USDA")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .help(item.usdaDescription ?? "Nutrition from USDA FoodData Central")
        case .manual:
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(.caption2)
                Text("Manual entry")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color(.label).opacity(0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.label).opacity(0.08), in: Capsule())
        case .model, .none:
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("AI estimate")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemBackground), in: Capsule())
        }
    }
}

private struct MacroChip: View {
    let label: String
    let value: String
    let unit: String
    let emphasized: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            (emphasized ? Color.accentColor.opacity(0.10) : Color(.tertiarySystemBackground)),
            in: Capsule()
        )
    }
}

#Preview("Fresh scan") {
    ResultsView(result: .preview, onScanAgain: {})
}

#Preview("From history") {
    NavigationStack {
        ResultsView(result: .preview, onScanAgain: nil)
    }
}
