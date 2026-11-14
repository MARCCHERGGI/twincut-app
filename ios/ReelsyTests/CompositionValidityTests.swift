import AVFoundation
import XCTest
@testable import Reelsy

/// Apple's own validator over a built composition: no gaps, no bad track ids, no bad values.
final class CompositionValidityTests: XCTestCase {
    private final class Validator: NSObject, AVVideoCompositionValidationHandling {
        var issues: [String] = []
        func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidValueForKey key: String) -> Bool {
            issues.append("invalid value for key \(key)"); return true
        }
        func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingEmptyTimeRange timeRange: CMTimeRange) -> Bool {
            issues.append("empty time range \(timeRange.start.seconds)...\(timeRange.end.seconds)"); return true
        }
        func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTimeRangeIn videoCompositionInstruction: any AVVideoCompositionInstructionProtocol) -> Bool {
            issues.append("invalid instruction time range \(videoCompositionInstruction.timeRange.start.seconds)"); return true
        }
        func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTrackIDIn videoCompositionInstruction: any AVVideoCompositionInstructionProtocol, layerInstruction: AVVideoCompositionLayerInstruction, asset: AVAsset) -> Bool {
            issues.append("invalid track id \(layerInstruction.trackID)"); return true
        }
    }

    func testBuiltCompositionIsValid() async throws {
        let red = try await ClipProbe.probe(url: try await Synth.video([(.red, 2)], size: CGSize(width: 640, height: 360)), isPhoto: false)
        let blue = try await ClipProbe.probe(url: try await Synth.video([(.blue, 0.6)], size: CGSize(width: 360, height: 640)), isPhoto: false)
        let template = Synth.template(shots: [1, 1, 1, 1])
        let plan = CutPlanner.plan(template: template, clips: [red.traits, blue.traits], arrangement: .order)
        let built = try await Composer.build(RenderSpec(plan: plan, clips: [red, blue], captions: [], sound: .clips))

        let duration = try await built.asset.load(.duration)
        XCTAssertEqual(duration.seconds, 4, accuracy: 0.05)
        let validator = Validator()
        let valid = try await built.video.isValid(for: built.asset, timeRange: CMTimeRange(start: .zero, duration: duration), validationDelegate: validator)
        XCTAssertTrue(valid, "issues: \(validator.issues)")
        XCTAssertTrue(validator.issues.isEmpty, "issues: \(validator.issues)")
    }

    /// The editor preview path: frames drawn by ReelCompositor without an export.
    func testCompositorDrawsEachSegment() async throws {
        let red = try await ClipProbe.probe(url: try await Synth.video([(.red, 1.5)], size: CGSize(width: 640, height: 360)), isPhoto: false)
        let blue = try await ClipProbe.probe(url: try await Synth.video([(.blue, 1.5)], size: CGSize(width: 360, height: 640)), isPhoto: false)
        let plan = CutPlanner.plan(template: Synth.template(shots: [1, 1]), clips: [red.traits, blue.traits], arrangement: .order)
        let built = try await Composer.build(RenderSpec(plan: plan, clips: [red, blue], captions: [], sound: .off))

        let generator = AVAssetImageGenerator(asset: built.asset)
        generator.videoComposition = built.video
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let w = 108, h = 192
        for (time, expected) in [(0.5, "red"), (1.5, "blue")] {
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            XCTAssertEqual(image.width, 1080)
            XCTAssertEqual(image.height, 1920)
            let rgb = PixelStats.rgb(image, width: w, height: h)
            let centre = Synth.pixel(rgb, x: w / 2, y: h / 2, width: w)
            XCTAssertEqual(Synth.dominant(centre), expected, "frame at \(time): \(centre)")
            XCTAssertGreaterThan(Int(centre.r) + Int(centre.g) + Int(centre.b), 150, "not black at \(time)")
        }
    }
}
