import AVFoundation

/// Twincut's own beat for a template: kick on every beat, hat on every half beat, a bass line
/// under it. Generated on the device from the template's beat times, so it lands exactly on the
/// cuts and there's nothing to license.
enum BeatSynth {
    static let sampleRate = 44_100.0

    /// Deletes the cached beats made for a template.
    static func removeTracks(for templateID: String) {
        let fm = FileManager.default
        for file in (try? fm.contentsOfDirectory(at: Storage.beats, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent.hasPrefix(templateID + "-") {
            try? fm.removeItem(at: file)
        }
    }

    /// The beat for `template` as an audio file, made once and cached.
    static func track(for template: Template) throws -> URL {
        // The "v2" changes whenever the synth does, so a cached beat never outlives its recipe.
        let url = Storage.beats.appendingPathComponent("\(template.id)-\(Int(template.duration * 1000))-v2.caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let samples = render(beats: beatTimes(template), duration: template.duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let partial = url.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partial)
        do {
            let file = try AVAudioFile(forWriting: partial, settings: format.settings)
            try file.write(from: buffer)
        }
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }

    /// The template's beats; with no tempo, a beat on every cut continued to the end; with
    /// fewer than two cuts, a steady 120 BPM.
    static func beatTimes(_ template: Template) -> [Double] {
        if template.beats.count >= 2 { return extend(template.beats, to: template.duration) }
        let cuts = template.shots.map(\.start)
        if cuts.count >= 2 { return extend(cuts, to: template.duration) }
        return Array(stride(from: 0, to: template.duration - 0.05, by: 0.5))
    }

    /// Detected beats often stop short of the end; continue the grid at the median spacing.
    static func extend(_ beats: [Double], to duration: Double) -> [Double] {
        let gaps = zip(beats.dropFirst(), beats).map { $0 - $1 }.sorted()
        let step = gaps[gaps.count / 2]
        guard step > 0.2 else { return beats }
        var out = beats
        var t = out.last! + step
        while t < duration - 0.05 {
            out.append(t)
            t += step
        }
        var back = out.first! - step
        while back >= 0 {
            out.insert(back, at: 0)
            back -= step
        }
        return out
    }

    static func render(beats: [Double], duration: Double) -> [Float] {
        let n = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var noise = SystemRandomNumberGenerator()
        let hits = beats.filter { $0 >= 0 && $0 < duration }

        func add(at time: Double, length: Double, _ sample: (Double) -> Double) {
            let start = Int(time * sampleRate)
            guard start < n else { return }
            let count = min(Int(length * sampleRate), n - start)
            for k in 0..<count { out[start + k] += Float(sample(Double(k) / sampleRate)) }
        }

        for (i, beat) in hits.enumerated() {
            // Kick: a sine falling from 140 Hz to 50 Hz.
            var phase = 0.0
            add(at: beat, length: 0.35) { t in
                phase += 2 * .pi * (50 + 90 * exp(-t * 30)) / sampleRate
                return 0.9 * sin(phase) * exp(-t * 9)
            }
            // Bass: two notes a bar, held to the next beat.
            let next = i + 1 < hits.count ? hits[i + 1] : duration
            let note = (i / 2) % 2 == 0 ? 55.0 : 65.41
            add(at: beat, length: next - beat) { t in 0.25 * sin(2 * .pi * note * t) * exp(-t * 3) }
            // Hats on the beat and halfway to the next one.
            for hat in [beat, (beat + next) / 2] {
                let accent = hat == beat ? 1.0 : 1.6
                add(at: hat, length: 0.05) { t in
                    0.18 * accent * (Double(UInt8.random(in: 0...255, using: &noise)) / 127.5 - 1) * exp(-t * 80)
                }
            }
        }
        let peak = out.map(abs).max() ?? 0
        if peak > 0 {
            let gain = 0.9 / peak
            for i in out.indices { out[i] *= gain }
        }
        return out
    }
}
