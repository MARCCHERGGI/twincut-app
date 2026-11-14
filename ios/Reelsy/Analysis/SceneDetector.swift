import Accelerate
import AVFoundation

struct SceneScores {
    var times: [Double]
    var scores: [Double]
}

/// Finds cuts from how much each frame differs from the one before. The score is ffmpeg's
/// scene score (min of mean absolute frame difference and its change, over 100) computed
/// on 160 px wide luma, which matched ffmpeg's full-colour cut lists on every test reel.
enum SceneDetector {
    static let width = 160

    enum Failure: Error { case reader }

    static func scores(asset: AVAsset, track: AVAssetTrack) throws -> SceneScores {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.reader }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.reader }

        var times: [Double] = []
        var scores: [Double] = []
        var frame: [UInt8] = []
        var previous: [UInt8]?
        var previousMafd = 0.0
        var height = 0

        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            let w = CVPixelBufferGetWidthOfPlane(pixels, 0)
            let h = CVPixelBufferGetHeightOfPlane(pixels, 0)
            if height == 0 {
                height = max(2, Int((Double(width) * Double(h) / Double(max(w, 1)) / 2).rounded()) * 2)
                frame = [UInt8](repeating: 0, count: width * height)
            }
            if let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) {
                var src = vImage_Buffer(data: base, height: vImagePixelCount(h), width: vImagePixelCount(w),
                                        rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixels, 0))
                frame.withUnsafeMutableBytes { dst in
                    var out = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height),
                                            width: vImagePixelCount(width), rowBytes: width)
                    _ = vImageScale_Planar8(&src, &out, nil, vImage_Flags(kvImageNoFlags))
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, .readOnly)

            var score = 0.0
            if let previous {
                let mafd = PixelStats.meanAbsDiff(previous, frame)
                let diff = abs(mafd - previousMafd)
                previousMafd = mafd
                score = min(1, max(0, min(mafd, diff) / 100))
            }
            times.append(time)
            scores.append(score)
            previous = frame
        }
        if reader.status == .failed { throw reader.error ?? Failure.reader }
        return SceneScores(times: times, scores: scores)
    }

    /// A cut is a frame whose score is a local peak and either clearly high or far above the
    /// median of its neighbourhood. The median ignores other cuts nearby, so dense montages
    /// keep their flash cuts while handheld motion (a raised neighbourhood) doesn't read as a cut.
    static func detectCuts(_ s: SceneScores, duration: Double, minShot: Double = 0.12) -> [Double] {
        let n = s.scores.count
        var found: [(t: Double, s: Double)] = []
        if n > 2 {
            for i in 1..<n {
                let v = s.scores[i]
                if v < 0.12 { continue }
                if v < s.scores[i - 1] || (i + 1 < n && v < s.scores[i + 1]) { continue }
                var near: [Double] = []
                for j in max(1, i - 12)...min(n - 1, i + 12) where abs(j - i) > 1 { near.append(s.scores[j]) }
                near.sort()
                let median = near.isEmpty ? 0 : near[near.count / 2]
                if v >= 0.32 || v >= 4 * median + 0.12 { found.append((s.times[i], v)) }
            }
        }
        var cuts: [(t: Double, s: Double)] = []
        for c in found {
            if c.t < minShot || c.t > duration - minShot { continue }
            if let last = cuts.last, c.t - last.t < minShot {
                if c.s > last.s { cuts[cuts.count - 1] = c }
                continue
            }
            cuts.append(c)
        }
        return cuts.map(\.t)
    }

    /// Mean motion per shot from the scene scores inside it, scaled to 0...1.
    static func shotMotion(_ s: SceneScores, _ shots: [(start: Double, end: Double)]) -> [Double] {
        shots.map { shot in
            var sum = 0.0
            var count = 0
            for (i, t) in s.times.enumerated() where t > shot.start + 0.07 && t < shot.end - 0.02 {
                sum += s.scores[i]
                count += 1
            }
            return count > 0 ? min(1, sum / Double(count) / 0.06) : 0
        }
    }
}
