import AVFoundation
import CoreImage

/// A caption burned into the export: its picture and where it sits, in Core Image
/// coordinates (origin at the bottom left of the frame).
struct BurnedCaption {
    let image: CIImage
    let origin: CGPoint
    let start: Double
    let end: Double
}

/// One segment of the reel: which composition track to show, how to place it in the frame
/// (a ramp for photo push-ins), and the captions to burn in.
final class ReelInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening: Bool
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let startTransform: CGAffineTransform
    let endTransform: CGAffineTransform
    let captions: [BurnedCaption]

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, start: CGAffineTransform, end: CGAffineTransform, captions: [BurnedCaption]) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.startTransform = start
        self.endTransform = end
        self.captions = captions
        self.containsTweening = start != end
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }

    /// The source-to-frame transform at `time`, in AVFoundation's top-left coordinates.
    func transform(at time: CMTime) -> CGAffineTransform {
        guard containsTweening, timeRange.duration.seconds > 0 else { return startTransform }
        let p = CGFloat(min(1, max(0, (time - timeRange.start).seconds / timeRange.duration.seconds)))
        let a = startTransform, b = endTransform
        return CGAffineTransform(a: a.a + (b.a - a.a) * p, b: a.b + (b.b - a.b) * p,
                                 c: a.c + (b.c - a.c) * p, d: a.d + (b.d - a.d) * p,
                                 tx: a.tx + (b.tx - a.tx) * p, ty: a.ty + (b.ty - a.ty) * p)
    }
}

/// Draws each frame with Core Image: the segment's clip reframed onto black, then captions.
/// The editor preview and the export both render through it, so they match.
final class ReelCompositor: NSObject, AVVideoCompositing {
    enum Failure: LocalizedError {
        case frame
        var errorDescription: String? { "Twincut couldn't draw a frame of your reel. Try again." }
    }

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
    ]

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? ReelInstruction,
                  let output = request.renderContext.newPixelBuffer()
            else {
                request.finish(with: Failure.frame)
                return
            }
            let size = request.renderContext.size
            let bounds = CGRect(origin: .zero, size: size)
            var image = CIImage(color: .black).cropped(to: bounds)

            if let source = request.sourceFrame(byTrackID: instruction.trackID) {
                // AVFoundation transforms work top-down; Core Image works bottom-up. Flip into
                // AVFoundation space, place the frame, flip back.
                let sourceHeight = CGFloat(CVPixelBufferGetHeight(source))
                let toTopDown = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
                let toBottomUp = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
                let placement = toTopDown
                    .concatenating(instruction.transform(at: request.compositionTime))
                    .concatenating(toBottomUp)
                image = CIImage(cvPixelBuffer: source).transformed(by: placement).composited(over: image)
            }

            let seconds = request.compositionTime.seconds
            for caption in instruction.captions where seconds >= caption.start && seconds < caption.end {
                let placed = caption.image.transformed(by: CGAffineTransform(translationX: caption.origin.x, y: caption.origin.y))
                image = placed.composited(over: image)
            }

            context.render(image.cropped(to: bounds), to: output, bounds: bounds, colorSpace: colorSpace)
            request.finish(withComposedVideoFrame: output)
        }
    }
}
