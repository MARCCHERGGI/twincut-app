import Foundation

/// Where Twincut keeps files. Clips and renders live in Caches and are swept after two days;
/// templates live in Application Support.
enum Storage {
    static var clips: URL { folder(.cachesDirectory, "Clips") }
    static var renders: URL { folder(.cachesDirectory, "Renders") }
    static var support: URL { folder(.applicationSupportDirectory, "Twincut") }
    static var beats: URL { folder(.cachesDirectory, "Beats") }

    static func newClipURL(ext: String) -> URL {
        clips.appendingPathComponent("\(UUID().uuidString).\(ext.isEmpty ? "mov" : ext)")
    }

    static func newRenderURL() -> URL {
        renders.appendingPathComponent("Twincut-\(UUID().uuidString.prefix(8)).mp4")
    }

    private static func folder(_ base: FileManager.SearchPathDirectory, _ name: String) -> URL {
        let url = FileManager.default.urls(for: base, in: .userDomainMask)[0].appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Deletes cached clips, renders and beats older than `age`, so they don't pile up.
    static func sweep(olderThan age: TimeInterval = 2 * 24 * 3600) {
        let fm = FileManager.default
        // TestFlight builds 1-4 kept copied reels' audio here; 1.0 keeps none.
        try? fm.removeItem(at: support.appendingPathComponent("Songs"))
        let cutoff = Date().addingTimeInterval(-age)
        for dir in [clips, renders, beats] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if date < cutoff { try? fm.removeItem(at: file) }
            }
        }
    }

    /// Bytes free for files the user asked for, or nil when the system can't say.
    static func freeBytes() -> Int64? {
        let values = try? support.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
