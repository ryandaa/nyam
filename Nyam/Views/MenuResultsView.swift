import SwiftUI

/// Shown after the user captures a restaurant menu photo. Displays each
/// detected dish with macros + a "Log this" action that records it as a
/// meal via the existing ScanHistory pipeline.
///
/// Cal AI is post-meal-photo only. Nyam's menu mode is a *pre-meal* decision
/// tool — see calories before you order.
struct MenuResultsView: View {
    @EnvironmentObject var history: ScanHistory
    @Environment(\.dismiss) private var dismiss

    let menu: MenuResult
    let menuImage: UIImage?
    let onFinish: () -> Void

    @State private var loggedDishIDs: Set<String> = []

    private var sortedDishes: [MenuDish] {
        menu.dishes.sorted { $0.calories > $1.calories }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    dishList
                }
                .padding(.bottom, 32)
            }
            .background(Color.NyamSurface.background.ignoresSafeArea())
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onFinish() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = menuImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.0), .black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = menu.restaurantName, !name.isEmpty {
                                Text(name)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("Menu")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            Text("\(menu.dishes.count) dish\(menu.dishes.count == 1 ? "" : "es") detected")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(14)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            Text("Tap a dish to log it as your meal. We've ranked them by calories so you can compare.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
    }

    private var dishList: some View {
        LazyVStack(spacing: 10) {
            ForEach(sortedDishes) { dish in
                Button {
                    logDish(dish)
                } label: {
                    DishRow(dish: dish, isLogged: loggedDishIDs.contains(dish.id))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func logDish(_ dish: MenuDish) {
        guard !loggedDishIDs.contains(dish.id) else { return }
        let result = dish.asScanResult()
        history.record(result, image: menuImage)
        loggedDishIDs.insert(dish.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Dish row

private struct DishRow: View {
    let dish: MenuDish
    let isLogged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dish.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let desc = dish.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(dish.calories.rounded()))")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Color.NyamSage.shade5)
                    Text("kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Chip(label: "P",  value: "\(Int(dish.proteinG.rounded()))g")
                Chip(label: "C",  value: "\(Int(dish.carbsG.rounded()))g")
                Chip(label: "F",  value: "\(Int(dish.fatG.rounded()))g")
                Chip(label: "Fi", value: "\(Int(dish.fiberG.rounded()))g")
                Chip(label: "Na", value: "\(Int(dish.sodiumMg.rounded()))mg")

                Spacer()

                if isLogged {
                    Label("Logged", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.NyamSage.shade5)
                } else {
                    Label("Log", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.NyamSage.shade5)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.NyamSurface.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isLogged ? Color.NyamSage.shade5.opacity(0.45) : Color(.separator).opacity(0.5),
                    lineWidth: 1
                )
        )
    }
}

private struct Chip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground), in: Capsule())
    }
}

#Preview {
    MenuResultsView(menu: .preview, menuImage: nil, onFinish: {})
        .environmentObject(ScanHistory())
}
