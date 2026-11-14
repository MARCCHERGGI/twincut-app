import AVFoundation
import Photos

enum Exporter {
    enum Failure: LocalizedError {
        case session, space
        var errorDescription: String? {
            switch self {
            case .session: return "Twincut couldn't start the export. Try again."
            case .space: return "Your device is almost out of space. Free up some room and try again."
            }
        }
    }

    /// Renders the reel to an H.264 1080x1920 MP4 on the device.
    static func export(_ spec: RenderSpec, to url: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        if let free = Storage.freeBytes(), free < 300_000_000 { throw Failure.space }
        let built = try await Composer.build(spec, burnCaptions: true)
        guard let session = AVAssetExportSession(asset: built.asset, presetName: AVAssetExportPresetHighestQuality)
        else { throw Failure.session }
        session.videoComposition = built.video
        session.audioTimePitchAlgorithm = .spectral
        session.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: url)

        let monitor = Task {
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let p) = state { await progress(p.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: url, as: .mp4)
        await progress(1)
    }
}

enum PhotoSaver {
    enum Failure: LocalizedError {
        case denied
        var errorDescription: String? { "Twincut needs permission to add videos to Photos. Allow it in Settings, then tap Save again." }
    }

    /// Saves the video to the library (add-only permission).
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
