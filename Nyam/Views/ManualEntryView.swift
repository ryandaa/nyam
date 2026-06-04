import SwiftUI
import PhotosUI

/// Sheet for logging a meal manually — no scan, no AR, no LLM. The user
/// types title + macros, optionally picks a photo, and Nyam records a
/// `nutrition_source: .manual` history entry.
///
/// Use cases: leftovers without a plate, restaurant meal where the nutrition
/// label is already known, a quick snack you don't want to photograph.
struct ManualEntryView: View {
    @EnvironmentObject var history: ScanHistory
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var fiber: String = ""
    @State private var sodium: String = ""

    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(calories) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What did you eat?") {
                    TextField("e.g. Iced latte", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Photo (optional)") {
                    PhotosPicker(
                        selection: $photoItem,
                        matching: .images
                    ) {
                        HStack {
                            if let photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text("Change photo")
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.title3)
                                    .foregroundStyle(Color.NyamSage.shade5)
                                Text("Add a photo")
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("Nutrition") {
                    macroField("Calories", value: $calories, unit: "cal")
                    macroField("Protein",  value: $protein,  unit: "g")
                    macroField("Carbs",    value: $carbs,    unit: "g")
                    macroField("Fat",      value: $fat,      unit: "g")
                    macroField("Fiber",    value: $fiber,    unit: "g")
                    macroField("Sodium",   value: $sodium,   unit: "mg")
                }
            }
            .navigationTitle("Log manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { submit() }
                        .disabled(!canSubmit)
                        .font(.body.weight(.semibold))
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photo = image
                    }
                }
            }
        }
        .tint(Color.NyamSage.shade5)
    }

    @ViewBuilder
    private func macroField(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    private func submit() {
        let cal = Double(calories) ?? 0
        let p = Double(protein) ?? 0
        let c = Double(carbs) ?? 0
        let f = Double(fat) ?? 0
        let fi = Double(fiber) ?? 0
        let na = Double(sodium) ?? 0

        let item = ScanItem(
            name: title.trimmingCharacters(in: .whitespaces),
            plateAreaPercent: 100,
            widthCm: 0, depthCm: 0, heightCm: 0,
            estimatedGrams: 0,
            calories: cal, proteinG: p, carbsG: c, fatG: f,
            fiberG: fi, sodiumMg: na,
            nutritionSource: .manual,
            usdaFdcId: nil, usdaDescription: nil
        )
        let totals = ScanTotals(
            calories: cal, proteinG: p, carbsG: c, fatG: f,
            fiberG: fi, sodiumMg: na
        )
        let result = ScanResult(
            plateDetected: false,
            title: title.trimmingCharacters(in: .whitespaces),
            items: [item],
            totals: totals
        )

        history.record(result, image: photo)
        dismiss()
    }
}

#Preview {
    ManualEntryView()
        .environmentObject(ScanHistory())
}
