import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var history: ScanHistory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(history.entries) { entry in
                            NavigationLink(value: entry) {
                                row(entry)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HistoryEntry.self) { entry in
                ResultsView(result: entry.result, onScanAgain: nil)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No scans yet")
                .font(.headline)
            Text("Your last 20 scans will show up here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func row(_ entry: HistoryEntry) -> some View {
        let topItem = entry.result.items.max(by: { $0.calories < $1.calories })
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(topItem?.name.capitalized ?? "Empty plate")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(entry.result.totals.calories.rounded())) kcal")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            history.delete(history.entries[index])
        }
    }
}

#Preview {
    let history = ScanHistory()
    history.record(.preview)
    return HistoryView()
        .environmentObject(history)
}
