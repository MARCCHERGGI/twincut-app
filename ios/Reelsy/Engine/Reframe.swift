import CoreGraphics

enum FillMode: String, Codable, Hashable {
    /// Cover the whole 9:16 frame, cropping the edges.
    case fill
    /// Show the whole clip inside black bars.
    case fit
}

/// Maps a source track into the 1080x1920 render frame.
enum Reframe {
    /// - Parameters:
    ///   - naturalSize: the track's encoded size.
    ///   - preferredTransform: the track's rotation, as recorded by the camera.
    ///   - focus: point to keep centred, normalised to the upright picture (0...1).
    ///   - zoom: extra scale on top of the fill scale, for push-ins.
    static func transform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize,
        mode: FillMode = .fill,
        focus: CGPoint = CGPoint(x: 0.5, y: 0.5),
        zoom: CGFloat = 1
    ) -> CGAffineTransform {
        let rotated = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let upright = preferredTransform.concatenating(CGAffineTransform(translationX: -rotated.minX, y: -rotated.minY))
        let w = abs(rotated.width)
        let h = abs(rotated.height)
        guard w > 0, h > 0 else { return .identity }

        let base = mode == .fill
            ? max(renderSize.width / w, renderSize.height / h)
            : min(renderSize.width / w, renderSize.height / h)
        let scale = base * max(zoom, 1)
        let sw = w * scale
        let sh = h * scale

        var tx = renderSize.width / 2 - focus.x * sw
        var ty = renderSize.height / 2 - focus.y * sh
        if sw >= renderSize.width {
            tx = min(0, max(renderSize.width - sw, tx))
        } else {
            tx = (renderSize.width - sw) / 2
        }
        if sh >= renderSize.height {
            ty = min(0, max(renderSize.height - sh, ty))
        } else {
            ty = (renderSize.height - sh) / 2
        }
        return upright
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    /// Upright display size of a track.
    static func displaySize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let r = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }
}
