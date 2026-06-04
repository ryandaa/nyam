import Foundation
import UIKit
import Combine

/// Local-only scan history. Stored as JSON in UserDefaults — small (a few KB
/// per scan, no images), survives app restart, cleared on sign-out.
///
/// Capped at `maxEntries` to bound storage. Newest first.
///
/// Image bytes live on disk via `ScanImageStore`; the entry holds only the
/// relative path. Deleting an entry deletes its image; `clear()` wipes the
/// entire image directory.
///
/// Storage key is versioned — bumping v1 → v2 silently drops older entries
/// that lacked the new fields (no migration code in V2).
@MainActor
final class ScanHistory: ObservableObject {
    static let storageKey = "ai.gojuly.nyam.history.v2"
    static let maxEntries = 20

    @Published private(set) var entries: [HistoryEntry] = []

    init() {
        load()
    }

    /// Record a scan with its captured image. Returns the persisted entry.
    @discardableResult
    func record(_ result: ScanResult, image: UIImage?) -> HistoryEntry {
        let id = UUID()
        let imagePath = image.flatMap { ScanImageStore.save($0, id: id) }
        let entry = HistoryEntry(id: id, date: Date(), result: result, imagePath: imagePath)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            let evicted = entries.suffix(entries.count - Self.maxEntries)
            for e in evicted { ScanImageStore.delete(relativePath: e.imagePath) }
            entries.removeLast(entries.count - Self.maxEntries)
        }
        persist()
        return entry
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        ScanImageStore.delete(relativePath: entry.imagePath)
        persist()
    }

    /// Replace the result on an existing entry — used when the user edits
    /// an item from ResultsView. Image and date stay the same.
    func updateResult(entryId: UUID, result: ScanResult) {
        guard let i = entries.firstIndex(where: { $0.id == entryId }) else { return }
        let old = entries[i]
        entries[i] = HistoryEntry(
            id: old.id,
            date: old.date,
            result: result,
            imagePath: old.imagePath
        )
        persist()
    }

    func clear() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        ScanImageStore.clearAll()
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
