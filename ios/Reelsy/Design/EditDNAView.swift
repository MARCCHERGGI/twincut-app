import SwiftUI

/// A template drawn as a strip: one bar per shot (width = its length, colour = its look),
/// beat ticks underneath, caption spans on top. When `playhead` is set, the shot under it
/// lights up.
struct EditDNAView: View {
    let template: Template
    var height: CGFloat = 56
    var playhead: Double?
    var showsBeats = true
    var showsCaptions = true
    /// When set, colours segments by clip instead of by shot.
    var plan: CutPlan?

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let scale: CGFloat = w / CGFloat(max(template.duration, 0.01))
            VStack(spacing: 6) {
                if showsCaptions && !template.texts.isEmpty {
                    ZStack(alignment: .leading) {
                        ForEach(Array(template.texts.enumerated()), id: \.offset) { _, t in
                            Capsule()
                                .fill(Theme.text2)
                                .frame(width: max(4, CGFloat(t.end - t.start) * scale - 2), height: 3)
                                .offset(x: CGFloat(t.start) * scale)
                        }
                    }
                    .frame(width: w, height: 3, alignment: .leading)
                }
                ZStack(alignment: .leading) {
                    ForEach(bars, id: \.index) { bar in
                        barView(bar, scale: scale)
                    }
                    if let playhead {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 2.5, height: height + 10)
                            .offset(x: min(w - 2.5, max(0, CGFloat(playhead) * scale - 1.25)))
                    }
                }
                .frame(width: w, height: height, alignment: .leading)
                if showsBeats && !template.beats.isEmpty {
                    ZStack(alignment: .leading) {
                        ForEach(Array(template.beats.enumerated()), id: \.offset) { _, b in
                            Circle()
                                .fill(Theme.text3)
                                .frame(width: 3, height: 3)
                                .offset(x: CGFloat(b) * scale - 1.5)
                        }
                    }
                    .frame(width: w, height: 3, alignment: .leading)
                }
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement()
        .accessibilityLabel("Edit timeline: \(template.shots.count) shots over \(template.duration.secondsLabel)")
    }

    private func barView(_ bar: Bar, scale: CGFloat) -> some View {
        let lit: Bool = playhead.map { $0 >= bar.start && $0 < bar.end } ?? false
        let width: CGFloat = CGFloat(bar.end - bar.start) * scale
        let x: CGFloat = CGFloat(bar.start) * scale
        return RoundedRectangle(cornerRadius: min(6, max(1.5, width / 3)), style: .continuous)
            .fill(bar.color)
            .brightness(lit ? 0.18 : 0)
            .frame(width: max(1, width - 1.5), height: height)
            .scaleEffect(y: lit ? 1.06 : 1)
            .offset(x: x)
    }

    private var totalHeight: CGFloat {
        var h = height
        if showsBeats && !template.beats.isEmpty { h += 9 }
        if showsCaptions && !template.texts.isEmpty { h += 9 }
        return h
    }

    private struct Bar {
        let index: Int
        let start: Double
        let end: Double
        let color: Color
    }

    private static let clipPalette: [Color] = [
        Color(hex: 0xE4FF3A), Color(hex: 0x5EE0FF), Color(hex: 0xFF6BA8), Color(hex: 0xB28CFF),
        Color(hex: 0xFFB547), Color(hex: 0x4DF0A8), Color(hex: 0xFF7A59), Color(hex: 0x8FB3FF),
    ]

    static func clipColor(_ index: Int) -> Color { clipPalette[index % clipPalette.count] }

    private var bars: [Bar] {
        if let plan {
            return plan.segments.map { Bar(index: $0.index, start: $0.start, end: $0.end, color: Self.clipColor($0.clipIndex)) }
        }
        return template.shots.map { Bar(index: $0.index, start: $0.start, end: $0.end, color: Color(hexString: $0.color)) }
    }
}
