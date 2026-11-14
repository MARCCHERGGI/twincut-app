import SwiftUI

enum CaptionStyle: String, CaseIterable, Identifiable, Hashable {
    case clean, boxed, bold

    var id: String { rawValue }
    var label: String {
        switch self {
        case .clean: return "Clean"
        case .boxed: return "Boxed"
        case .bold: return "Bold"
        }
    }
}

/// An on-screen caption in the user's reel. Starts as the reference's caption, at the same
/// time and place, and the user rewrites it.
struct Caption: Identifiable, Hashable {
    var id = UUID()
    var text: String
    var start: Double
    var end: Double
    var position: Template.Position
    var size: Template.Size
    var style: CaptionStyle = .clean
    var enabled = true

    init(text: String, start: Double, end: Double, position: Template.Position, size: Template.Size, style: CaptionStyle = .clean) {
        self.text = text
        self.start = start
        self.end = end
        self.position = position
        self.size = size
        self.style = style
    }

    init(_ beat: Template.TextBeat) {
        self.init(text: beat.text, start: beat.start, end: beat.end, position: beat.position, size: beat.size)
    }

    var isVisible: Bool { enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func shows(at time: Double) -> Bool { isVisible && time >= start && time < end }
}

extension Template.Size {
    /// Font size as a fraction of the video frame's width.
    var scale: CGFloat {
        switch self {
        case .small: return 0.046
        case .medium: return 0.058
        case .large: return 0.074
        }
    }
}

/// Draws a caption at the size it has inside a video frame `frameWidth` wide. The editor
/// preview and the export both draw with this view, so what you see is what you post.
struct CaptionView: View {
    let caption: Caption
    let frameWidth: CGFloat

    var body: some View {
        let size = frameWidth * caption.size.scale
        Text(caption.text)
            .font(.system(size: size, weight: caption.style == .bold ? .heavy : .semibold))
            .multilineTextAlignment(.center)
            .lineSpacing(size * 0.08)
            .foregroundStyle(caption.style == .boxed ? Color.black : Color.white)
            .padding(.horizontal, caption.style == .boxed ? size * 0.45 : 0)
            .padding(.vertical, caption.style == .boxed ? size * 0.22 : 0)
            .background {
                if caption.style == .boxed {
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(Color.white)
                }
            }
            .shadow(color: .black.opacity(caption.style == .boxed ? 0 : 0.6), radius: size * 0.14, y: size * 0.05)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: frameWidth * 0.84)
    }
}

@MainActor
enum CaptionRenderer {
    /// The caption as an image for the export, sized for a frame `frameWidth` pixels wide.
    static func image(for caption: Caption, frameWidth: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: CaptionView(caption: caption, frameWidth: frameWidth).padding(frameWidth * 0.02))
        renderer.proposedSize = ProposedViewSize(width: frameWidth * 0.9, height: nil)
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.cgImage
    }
}
