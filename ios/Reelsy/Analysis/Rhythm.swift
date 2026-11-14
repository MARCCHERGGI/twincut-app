import AVFoundation

/// Tempo and beat grid from mono samples: spectral-flux onsets, autocorrelation tempo with a
/// 120 BPM prior, then dynamic-programming beat tracking (Ellis 2007). Port of the server's
/// rhythm.js, which was checked against the cut grids of real reels.
enum Rhythm {
    static let sampleRate = 22050.0

    struct Result: Equatable {
        var bpm: Double
        var beats: [Double]
        var confidence: Double
    }

    static func samples(from asset: AVAsset) async throws -> [Float]? {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var out: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { dst in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: dst.count, destination: dst.baseAddress!)
            }
            out.append(contentsOf: chunk)
        }
        return out.count > Int(sampleRate) ? out : nil
    }

    static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        re.withUnsafeMutableBufferPointer { re in
            im.withUnsafeMutableBufferPointer { im in
                var j = 0
                for i in 1..<n {
                    var bit = n >> 1
                    while j & bit != 0 {
                        j ^= bit
                        bit >>= 1
                    }
                    j ^= bit
                    if i < j {
                        re.swapAt(i, j)
                        im.swapAt(i, j)
                    }
                }
                var len = 2
                while len <= n {
                    let ang = -2 * Double.pi / Double(len)
                    let wr = cos(ang), wi = sin(ang)
                    var i = 0
                    while i < n {
                        var cr = 1.0, ci = 0.0
                        for k in 0..<(len / 2) {
                            let a = i + k, b = a + len / 2
                            let tr = re[b] * cr - im[b] * ci
                            let ti = re[b] * ci + im[b] * cr
                            re[b] = re[a] - tr
                            im[b] = im[a] - ti
                            re[a] += tr
                            im[a] += ti
                            let nr = cr * wr - ci * wi
                            ci = cr * wi + ci * wr
                            cr = nr
                        }
                        i += len
                    }
                    len <<= 1
                }
            }
        }
    }

    static func onsetEnvelope(_ samples: [Float], sampleRate: Double) -> (onset: [Double], fps: Double, offset: Double)? {
        let n = 1024
        let hop = Int((sampleRate / 50).rounded())
        guard samples.count > n else { return nil }
        let frames = (samples.count - n) / hop + 1
        guard frames >= 100 else { return nil }
        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n - 1)) }
        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)
        var prev = [Double](repeating: 0, count: n / 2 + 1)
        var cur = [Double](repeating: 0, count: n / 2 + 1)
        var raw = [Double](repeating: 0, count: frames)
        var energy = 0.0
        for f in 0..<frames {
            let off = f * hop
            for i in 0..<n {
                let v = Double(samples[off + i]) * window[i]
                re[i] = v
                im[i] = 0
                energy += v * v
            }
            fft(&re, &im)
            var flux = 0.0
            for k in 0...(n / 2) {
                let m = log1p(100 * (re[k] * re[k] + im[k] * im[k]).squareRoot())
                cur[k] = m
                if f > 0, m > prev[k] { flux += m - prev[k] }
            }
            raw[f] = flux
            swap(&prev, &cur)
        }
        guard (energy / Double(frames * n)).squareRoot() >= 1e-3 else { return nil }

        let w = 12
        var onset = [Double](repeating: 0, count: frames)
        for f in 0..<frames {
            let lo = max(0, f - w), hi = min(frames - 1, f + w)
            var s = 0.0
            for j in lo...hi { s += raw[j] }
            onset[f] = max(0, raw[f] - s / Double(hi - lo + 1))
        }
        let mean = onset.reduce(0, +) / Double(frames)
        let sd = (onset.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(frames)).squareRoot()
        let norm = sd > 0 ? sd : 1
        for f in 0..<frames { onset[f] /= norm }
        return (onset, sampleRate / Double(hop), Double(n) / 2 / sampleRate)
    }

    static func tempo(_ onset: [Double], fps: Double) -> Double? {
        let count = onset.count
        let minLag = Int((fps * 60 / 200).rounded())
        let maxLag = min(Int((fps * 60 / 55).rounded()), count - 2)
        guard maxLag > minLag else { return nil }
        var ac = [Double](repeating: 0, count: maxLag + 2)
        for lag in minLag...(maxLag + 1) where lag < count {
            var s = 0.0
            for t in lag..<count { s += onset[t] * onset[t - lag] }
            ac[lag] = s / Double(count - lag)
        }
        var best = -Double.infinity
        var bestLag = 0
        for lag in minLag...maxLag {
            let bpm = 60 * fps / Double(lag)
            let prior = exp(-0.5 * pow(log2(bpm / 120) / 0.9, 2))
            if ac[lag] * prior > best {
                best = ac[lag] * prior
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return nil }
        let y0 = ac[bestLag - 1], y1 = ac[bestLag], y2 = ac[bestLag + 1]
        let denom = y0 - 2 * y1 + y2
        let delta = denom != 0 ? max(-0.5, min(0.5, 0.5 * (y0 - y2) / denom)) : 0
        return Double(bestLag) + delta
    }

    static func trackBeats(_ onset: [Double], period: Double, tightness: Double = 100) -> [Int] {
        let count = onset.count
        var score = [Double](repeating: 0, count: count)
        var back = [Int](repeating: -1, count: count)
        for t in 0..<count {
            var bestV = -Double.infinity
            var bestTau = -1
            let lo = max(0, Int((Double(t) - 2 * period).rounded()))
            let hi = t - Int((period / 2).rounded())
            if hi >= lo {
                for tau in lo...hi {
                    let v = score[tau] - tightness * pow(log(Double(t - tau) / period), 2)
                    if v > bestV {
                        bestV = v
                        bestTau = tau
                    }
                }
            }
            if bestTau >= 0, bestV > 0 {
                score[t] = onset[t] + bestV
                back[t] = bestTau
            } else {
                score[t] = onset[t]
            }
        }
        var end = max(0, count - Int(period.rounded()))
        for t in end..<count where score[t] > score[end] { end = t }
        var beats: [Int] = []
        var t = end
        while t >= 0 {
            beats.append(t)
            t = back[t]
        }
        return beats.reversed()
    }

    static func analyze(_ samples: [Float], sampleRate: Double = Rhythm.sampleRate) -> Result? {
        guard let env = onsetEnvelope(samples, sampleRate: sampleRate),
              let period = tempo(env.onset, fps: env.fps) else { return nil }
        let frames = trackBeats(env.onset, period: period)
        guard frames.count >= 4 else { return nil }
        var atBeats = 0.0
        for f in frames {
            var m = 0.0
            for j in max(0, f - 2)...min(env.onset.count - 1, f + 2) { m = max(m, env.onset[j]) }
            atBeats += m
        }
        atBeats /= Double(frames.count)
        let mean = env.onset.reduce(0, +) / Double(env.onset.count)
        return Result(
            bpm: (60 * env.fps / period * 10).rounded() / 10,
            beats: frames.map { ((Double($0) / env.fps + env.offset) * 1000).rounded() / 1000 },
            confidence: mean > 0 ? (atBeats / mean * 100).rounded() / 100 : 0
        )
    }

    /// Share of cuts within 80 ms of the beat grid, half-beats included: montage edits often
    /// cut on eighth notes.
    static func onBeatShare(cuts: [Double], beats: [Double]) -> Double {
        guard !cuts.isEmpty, beats.count >= 2 else { return 0 }
        var grid: [Double] = []
        for i in beats.indices {
            grid.append(beats[i])
            if i + 1 < beats.count { grid.append((beats[i] + beats[i + 1]) / 2) }
        }
        let hits = cuts.filter { c in grid.contains { abs($0 - c) <= 0.08 } }.count
        return Double(hits) / Double(cuts.count)
    }
}
