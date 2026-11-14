import CoreGraphics
import Foundation

/// One of the user's clips, copied into the app's cache. Photos become short still videos so
/// the whole engine works on one kind of media.
struct ClipAsset: Identifiable {
    let id: UUID
    let url: URL
    let isPhoto: Bool
    var duration: Double
    var displaySize: CGSize
    var focus: CGPoint
    var framing: Template.Framing?
    var motion: Double
    var brightness: Double
    var thumbnail: CGImage?
    var fill: FillMode = .fill

    var traits: ClipTraits {
        ClipTraits(duration: isPhoto ? nil : duration, framing: framing, motion: motion, brightness: brightness)
    }

    var isLandscape: Bool { displaySize.width > displaySize.height }
}
