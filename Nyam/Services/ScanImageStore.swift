import Foundation
import UIKit

/// Persists captured meal photos to `Documents/scans/<uuid>.jpg` so the Home
/// feed can render the actual photo for each past scan.
///
/// Paths are stored relative to the Documents directory so they survive
/// re-installs that move the sandbox root (e.g. between dev/release builds).
enum ScanImageStore {
    private static let directoryName = "scans"

    /// Save the image. Returns the relative path on success (to store on
    /// `HistoryEntry.imagePath`), or nil if writing failed.
    @discardableResult
    static func save(_ image: UIImage, id: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.6) else { return nil }
        let directory = directoryURL()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(id.uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return "\(directoryName)/\(fileName)"
        } catch {
            #if DEBUG
            print("ScanImageStore.save failed: \(error)")
            #endif
            return nil
        }
    }

    /// Load an image by the relative path stored on `HistoryEntry.imagePath`.
    static func load(relativePath: String?) -> UIImage? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        let url = documentsURL().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Delete a single saved image. Silent on miss.
    static func delete(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        let url = documentsURL().appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    /// Wipe the entire scans directory — used on sign-out and history clear.
    static func clearAll() {
        try? FileManager.default.removeItem(at: directoryURL())
    }

    // MARK: - Paths

    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func directoryURL() -> URL {
        documentsURL().appendingPathComponent(directoryName, isDirectory: true)
    }
}
