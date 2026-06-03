import Foundation
import Combine

/// Local-only scan history. Stored as JSON in UserDefaults — small (a few KB
/// per scan, no images), survives app restart, cleared on sign-out.
///
/// Capped at `maxEntries` to bound storage. Newest first.
@MainActor
final class ScanHistory: ObservableObject {
    static let storageKey = "ai.gojuly.nyam.history.v1"
    static let maxEntries = 20

    @Published private(set) var entries: [HistoryEntry] = []

    init() {
        load()
    }

    func record(_ result: ScanResult) {
        let entry = HistoryEntry(result: result)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        persist()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            #if DEBUG
            print("ScanHistory load failed: \(error)")
            #endif
            entries = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            #if DEBUG
            print("ScanHistory save failed: \(error)")
            #endif
        }
    }
}
