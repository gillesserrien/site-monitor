import Foundation

nonisolated struct SiteStore: Sendable {
    let fileURL = URL.applicationSupportDirectory.appending(path: "SiteMonitor/sites.json")

    func load() -> [Site]? {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else { return nil }
        do {
            return try JSONDecoder().decode([Site].self, from: Data(contentsOf: fileURL))
        } catch {
            // Back up the unreadable file so the next save doesn't destroy it.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("broken.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            print("Could not read \(fileURL.path()): \(error)")
            return nil
        }
    }

    func save(_ sites: [Site]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sites).write(to: fileURL, options: .atomic)
        } catch {
            print("Could not save sites: \(error)")
        }
    }
}
