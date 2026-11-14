import Foundation

/// What the planner needs to know about one of the user's clips.
struct ClipTraits: Hashable {
    /// Seconds of usable footage; nil for a photo, which can fill any length.
    var duration: Double?
    var framing: Template.Framing?
    var motion: Double
    var brightness: Double
}

/// One stretch of the finished reel and the footage that fills it.
struct Segment: Hashable, Identifiable {
    var index: Int
    var start: Double
    var end: Double
    var shotIndex: Int
    var clipIndex: Int
    /// Where in the clip this segment starts reading, in seconds.
    var sourceStart: Double
    /// How many seconds of the clip it reads. Shorter than the segment means slow motion.
    var sourceDuration: Double

    var id: Int { index }
    var duration: Double { end - start }
}

struct CutPlan: Hashable {
    var segments: [Segment]
    var duration: Double

    func clipIndex(at time: Double) -> Int? {
        segments.first { time >= $0.start && time < $0.end }?.clipIndex
    }
}

enum Arrangement: String, CaseIterable, Identifiable {
    /// Match each clip to the shot it fits best (framing, motion, light).
    case smart
    /// Use clips in the order the user picked them.
    case order

    var id: String { rawValue }
}

/// Fits any number of clips to a template without breaking its rhythm. Fewer clips than
/// shots: clips repeat, each time from a fresh part of the clip. More clips than shots: long
/// shots split on the beat nearest their middle.
enum CutPlanner {
    static let minSegment = 0.25

    static func timeline(for template: Template, clipCount: Int) -> [(start: Double, end: Double, shot: Int)] {
        var segs = template.shots.map { (start: $0.start, end: $0.end, shot: $0.index) }
        if segs.isEmpty { segs = [(0, template.duration, 0)] }
        while segs.count < clipCount {
            guard let i = segs.indices.max(by: { segs[$0].end - segs[$0].start < segs[$1].end - segs[$1].start }) else { break }
            let s = segs[i]
            guard s.end - s.start >= 2 * minSegment else { break }
            let mid = (s.start + s.end) / 2
            let onBeat = template.beats
                .filter { $0 > s.start + minSegment && $0 < s.end - minSegment }
                .min { abs($0 - mid) < abs($1 - mid) }
            let cut = onBeat ?? mid
            segs.replaceSubrange(i...i, with: [(s.start, cut, s.shot), (cut, s.end, s.shot)])
        }
        return segs
    }

    static func plan(template: Template, clips: [ClipTraits], arrangement: Arrangement) -> CutPlan {
        precondition(!clips.isEmpty, "a plan needs at least one clip")
        let slots = timeline(for: template, clipCount: clips.count)
        let owners = arrangement == .smart
            ? assignSmart(slots: slots, template: template, clips: clips)
            : slots.indices.map { $0 % clips.count }

        var segments = slots.enumerated().map { i, s in
            Segment(index: i, start: s.start, end: s.end, shotIndex: s.shot, clipIndex: owners[i], sourceStart: 0, sourceDuration: s.end - s.start)
        }
        placeSources(&segments, clips: clips)
        return CutPlan(segments: segments, duration: template.duration)
    }

    /// Spreads each clip's segments across the clip so a repeated clip never shows the same
    /// moment twice. A clip shorter than its segment plays in slow motion to fill it.
    static func placeSources(_ segments: inout [Segment], clips: [ClipTraits]) {
        for (c, clip) in clips.enumerated() {
            let mine = segments.indices.filter { segments[$0].clipIndex == c }
            guard !mine.isEmpty else { continue }
            guard let available = clip.duration else {
                for i in mine {
                    segments[i].sourceStart = 0
                    segments[i].sourceDuration = segments[i].duration
                }
                continue
            }
            let needed = mine.reduce(0) { $0 + segments[$1].duration }
            if available >= needed {
                let slack = available - needed
                var used = 0.0
                for (k, i) in mine.enumerated() {
                    segments[i].sourceStart = used + slack * (Double(k) + 0.5) / Double(mine.count)
                    segments[i].sourceDuration = segments[i].duration
                    used += segments[i].duration
                }
            } else {
                for (k, i) in mine.enumerated() {
                    let length = min(segments[i].duration, available)
                    let spread = mine.count > 1 ? Double(k) / Double(mine.count - 1) : 0.5
                    segments[i].sourceStart = (available - length) * spread
                    segments[i].sourceDuration = length
                }
            }
        }
    }

    static func fit(_ clip: ClipTraits, _ shot: Template.Shot?, length: Double) -> Double {
        var score = 0.0
        if let want = shot?.framing, let have = clip.framing {
            let order: [Template.Framing] = [.close, .medium, .wide]
            let gap = abs((order.firstIndex(of: want) ?? 1) - (order.firstIndex(of: have) ?? 1))
            score += gap == 0 ? 1 : gap == 1 ? 0.4 : 0
        } else {
            score += 0.4
        }
        if let shot {
            score += 1 - min(1, abs(shot.motion - clip.motion))
            score += 0.5 * (1 - min(1, abs(shot.brightness - clip.brightness) * 2))
        }
        if let d = clip.duration, d < length { score -= min(1, (length - d) / length) }
        return score
    }

    /// Greedy best-fit with a fair share per clip, every clip used at least once, and no clip
    /// on two consecutive slots when there is a choice.
    static func assignSmart(slots: [(start: Double, end: Double, shot: Int)], template: Template, clips: [ClipTraits]) -> [Int] {
        let n = slots.count
        let k = clips.count
        if k == 1 { return Array(repeating: 0, count: n) }
        let cap = Int((Double(n) / Double(k)).rounded(.up))
        let shotByIndex = Dictionary(uniqueKeysWithValues: template.shots.map { ($0.index, $0) })
        var owner = Array(repeating: -1, count: n)
        var uses = Array(repeating: 0, count: k)

        var pairs: [(slot: Int, clip: Int, score: Double)] = []
        for s in 0..<n {
            for c in 0..<k {
                pairs.append((s, c, fit(clips[c], shotByIndex[slots[s].shot], length: slots[s].end - slots[s].start)))
            }
        }
        pairs.sort { $0.score != $1.score ? $0.score > $1.score : ($0.slot, $0.clip) < ($1.slot, $1.clip) }

        // Pass 1: every clip gets its single best free slot.
        for p in pairs where owner[p.slot] == -1 && uses[p.clip] == 0 {
            owner[p.slot] = p.clip
            uses[p.clip] = 1
        }
        // Pass 2: remaining slots, best fit first, within the fair share, avoiding neighbours.
        for strict in [true, false] {
            for p in pairs where owner[p.slot] == -1 && uses[p.clip] < cap {
                if strict {
                    let left = p.slot > 0 ? owner[p.slot - 1] : -1
                    let right = p.slot < n - 1 ? owner[p.slot + 1] : -1
                    if left == p.clip || right == p.clip { continue }
                }
                owner[p.slot] = p.clip
                uses[p.clip] += 1
            }
        }
        for s in 0..<n where owner[s] == -1 {
            owner[s] = uses.indices.min { uses[$0] < uses[$1] } ?? 0
            uses[owner[s]] += 1
        }
        separateRepeats(&owner)
        return owner
    }

    /// Swaps owners to break up back-to-back repeats the greedy passes leave once the fair
    /// shares fill up.
    static func separateRepeats(_ owner: inout [Int]) {
        let n = owner.count
        guard n > 2 else { return }
        func clashes(_ s: Int) -> Bool {
            (s > 0 && owner[s - 1] == owner[s]) || (s < n - 1 && owner[s + 1] == owner[s])
        }
        for s in 1..<n where owner[s] == owner[s - 1] {
            for t in 0..<n where owner[t] != owner[s] {
                owner.swapAt(s, t)
                if !clashes(s) && !clashes(t) { break }
                owner.swapAt(s, t)
            }
        }
    }
}
