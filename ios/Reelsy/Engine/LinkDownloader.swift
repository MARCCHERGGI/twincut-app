import Foundation

/// Fetches a video the user linked to directly (a file on their own site, cloud drive or server).
/// Pages on websites and apps are never scraped; only a response the server itself labels as a
/// video is kept.
enum LinkDownloader {
    enum Failure: LocalizedError {
        case notAVideo, tooBig, unreachable, noRoom

        var errorDescription: String? {
            switch self {
            case .notAVideo: "That link isn't a video file. Save the video to this device, then pick it."
            case .tooBig: "That video is over 1 GB. Trim it or pick a shorter one."
            case .unreachable: "Couldn't reach that link. Check your connection and try again."
            case .noRoom: "Your device is almost out of space. Free up some room and try again."
            }
        }
    }

    static let maxBytes: Int64 = 1_000_000_000

    /// Whether `link` points straight at a video file, asking the server when it answers quickly.
    static func pointsAtVideo(_ link: VideoLink) async -> Bool {
        var request = URLRequest(url: link.url, timeoutInterval: 8)
        request.httpMethod = "HEAD"
        guard let answer = try? await URLSession.shared.data(for: request),
              let http = answer.1 as? HTTPURLResponse, (200..<400).contains(http.statusCode)
        else { return link.namesVideoFile }
        return isVideo(mime: http.mimeType, link: link)
    }

    /// Downloads the video into the clip cache and returns its file URL.
    static func download(_ link: VideoLink) async throws -> URL {
        // Refuse an oversized file before fetching it when the server says how big it is.
        var head = URLRequest(url: link.url, timeoutInterval: 8)
        head.httpMethod = "HEAD"
        if let answer = try? await URLSession.shared.data(for: head), answer.1.expectedContentLength > maxBytes {
            throw Failure.tooBig
        }
        if let free = Storage.freeBytes(), free < 2 * maxBytes / 10 {
            throw Failure.noRoom
        }
        let file: URL
        let response: URLResponse
        do {
            (file, response) = try await URLSession.shared.download(for: URLRequest(url: link.url, timeoutInterval: 30))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw Failure.unreachable
        }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw Failure.unreachable }
        guard isVideo(mime: http.mimeType, link: link) else { throw Failure.notAVideo }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size <= maxBytes else { throw Failure.tooBig }
        let ext = link.namesVideoFile ? link.url.pathExtension.lowercased() : (http.mimeType == "video/quicktime" ? "mov" : "mp4")
        let dest = Storage.newClipURL(ext: ext)
        try FileManager.default.moveItem(at: file, to: dest)
        return dest
    }

    private static func isVideo(mime: String?, link: VideoLink) -> Bool {
        let mime = (mime ?? "").lowercased()
        if mime.hasPrefix("video/") { return true }
        // Some file hosts label every download as a generic binary.
        return mime == "application/octet-stream" && link.namesVideoFile
    }
}
