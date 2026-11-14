import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A movie handed over by the photo picker, copied into the app's cache.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = Storage.newClipURL(ext: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum ClipImporter {
    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? { "One of those items couldn't be opened. If it's in iCloud, check your connection and try again." }
    }

    static func isMovie(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
    }

    /// Copies a picked movie into the cache and returns its file URL.
    static func movieURL(_ item: PhotosPickerItem) async throws -> URL {
        guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { throw Failure.unreadable }
        return movie.url
    }

    /// Copies a movie chosen in Files into the cache, downloading it first if it lives in iCloud.
    static func copyFile(_ picked: URL) async throws -> URL {
        try await Task.detached {
            let scoped = picked.startAccessingSecurityScopedResource()
            defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
            let dest = Storage.newClipURL(ext: picked.pathExtension)
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: picked, options: [], error: &coordinationError) { readable in
                do { try FileManager.default.copyItem(at: readable, to: dest) } catch { copyError = error }
            }
            if coordinationError != nil || copyError != nil { throw Failure.unreadable }
            return dest
        }.value
    }

    static func importClip(_ item: PhotosPickerItem) async throws -> ClipAsset {
        if isMovie(item) {
            return try await ClipProbe.probe(url: try await movieURL(item), isPhoto: false)
        }
        guard let data = try await item.loadTransferable(type: Data.self),
              let upright = StillVideo.upright(data)
        else { throw Failure.unreadable }
        let url = Storage.newClipURL(ext: "mp4")
        try await StillVideo.write(upright, to: url)
        return try await ClipProbe.probe(url: url, isPhoto: true)
    }

    /// Imports in the order picked, a few at a time, reporting how many are done.
    static func importClips(_ items: [PhotosPickerItem], progress: @escaping @MainActor (Int) -> Void) async throws -> [ClipAsset] {
        var results = [ClipAsset?](repeating: nil, count: items.count)
        var done = 0
        try await withThrowingTaskGroup(of: (Int, ClipAsset).self) { group in
            var next = 0
            while next < min(3, items.count) {
                let i = next
                group.addTask { (i, try await importClip(items[i])) }
                next += 1
            }
            while let (i, clip) = try await group.next() {
                results[i] = clip
                done += 1
                await progress(done)
                if next < items.count {
                    let j = next
                    group.addTask { (j, try await importClip(items[j])) }
                    next += 1
                }
            }
        }
        return results.compactMap { $0 }
    }

    /// The bundled sample clips, so anyone can try the full flow without their own footage.
    static func sampleClips(count: Int, progress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> [ClipAsset] {
        let urls = (1...8).compactMap { Bundle.main.url(forResource: "sample-\($0)", withExtension: "mp4") }
        guard !urls.isEmpty else { throw Failure.unreadable }
        var clips: [ClipAsset] = []
        for i in 0..<max(1, count) {
            let source = urls[i % urls.count]
            try Task.checkCancellation()
            clips.append(try await ClipProbe.probe(url: source, isPhoto: false))
            await progress(i + 1)
        }
        return clips
    }
}
