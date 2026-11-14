import AVFoundation
import Vision

/// What one shot of the reference looks like, read from its middle frame with Apple's
/// on-device Vision models: what's in it, how tight it is, its colour, and its caption.
struct ShotLook {
    var color: String
    var brightness: Double
    var framing: Template.Framing?
    var subject: String?
    var noun: String?
    var caption: Caption?

    struct Caption {
        var text: String
        var position: Template.Position
        var size: Template.Size
    }
}

enum ShotReader {
    static func read(asset: AVAsset, shots: [(start: Double, end: Double)]) async -> [ShotLook] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let tolerance = CMTime(seconds: 0.04, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let fastText = shots.count > 40

        var looks: [ShotLook] = []
        for shot in shots {
            let mid = max(0, min(shot.start + (shot.end - shot.start) / 2, shot.end - 0.05))
            guard let image = try? await generator.image(at: CMTime(seconds: mid, preferredTimescale: 600)).image else {
                looks.append(ShotLook(color: "#5a5a66", brightness: 0.3))
                continue
            }
            looks.append(look(at: image, fastText: fastText))
        }
        return looks
    }

    static func look(at image: CGImage, fastText: Bool = false) -> ShotLook {
        let swatch = PixelStats.swatch(rgb: PixelStats.rgb(image, width: 4, height: 4))
        var look = ShotLook(color: swatch.hex, brightness: swatch.brightness)

        let classify = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = fastText ? .fast : .accurate
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        // Separate calls: if the classifier is unavailable (it is on some simulators), faces
        // and captions still get read.
        try? handler.perform([faces, text])
        try? handler.perform([classify])

        let labels = (classify.results ?? []).filter { $0.confidence >= 0.25 }.map(\.identifier)
        let largestFace = faces.results?.map(\.boundingBox.area).max() ?? 0
        let subject = Labels.subject(labels: labels, hasFace: largestFace > 0)
        look.subject = subject
        look.noun = Labels.noun(labels: labels)
        if largestFace > 0 {
            look.framing = largestFace > 0.06 ? .close : largestFace > 0.008 ? .medium : .wide
        } else if let subject {
            look.framing = ["place"].contains(subject) ? .wide : ["food", "object"].contains(subject) ? .close : .medium
        }
        look.caption = caption(from: text.results ?? [])
        return look
    }

    private static let chrome = ["tiktok", "instagram", "youtube", "shorts", "snapchat", "facebook", "capcut", "reels", "original audio", "follow", "subscribe", "@"]

    /// The reference's main on-screen caption: big text inside the safe area, lines that sit
    /// together joined in reading order. Usernames, watermarks and app chrome are skipped.
    static func caption(from observations: [VNRecognizedTextObservation]) -> ShotLook.Caption? {
        struct Line { var text: String; var box: CGRect }
        let lines: [Line] = observations.compactMap { obs in
            guard let top = obs.topCandidates(1).first, top.confidence >= 0.5 else { return nil }
            let s = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = s.lowercased()
            guard s.count >= 3, s.filter(\.isLetter).count >= 2, !chrome.contains(where: { lower.contains($0) }) else { return nil }
            // Vision boxes are normalised with the origin at the bottom left.
            let box = CGRect(x: obs.boundingBox.minX, y: 1 - obs.boundingBox.maxY, width: obs.boundingBox.width, height: obs.boundingBox.height)
            guard box.height >= 0.022, box.midY > 0.08, box.midY < 0.86 else { return nil }
            return Line(text: s, box: box)
        }.sorted { $0.box.minY < $1.box.minY }
        guard !lines.isEmpty else { return nil }

        var groups: [[Line]] = []
        for line in lines {
            if let last = groups.last?.last,
               line.box.minY - last.box.maxY < 1.6 * max(line.box.height, last.box.height),
               abs(line.box.midX - last.box.midX) < 0.25 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        guard let main = groups.max(by: { a, b in
            a.reduce(0) { $0 + $1.box.area } < b.reduce(0) { $0 + $1.box.area }
        }) else { return nil }

        let text = main.map(\.text).joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
        let centre = (main.first!.box.minY + main.last!.box.maxY) / 2
        let lineHeight = main.reduce(0) { $0 + $1.box.height } / CGFloat(main.count)
        return ShotLook.Caption(
            text: String(text.prefix(120)),
            position: centre < 0.38 ? .top : centre > 0.62 ? .bottom : .middle,
            size: lineHeight > 0.045 ? .large : lineHeight > 0.03 ? .medium : .small
        )
    }
}

/// Turns Vision's image classes into the plain words the template shows.
enum Labels {
    private static let generic: Set<String> = [
        "outdoor", "indoor", "structure", "material", "textile", "liquid", "art", "wood_processed",
        "blue_sky", "light", "darkness", "night", "sky", "land", "water", "conveyance", "machine",
        "people", "adult", "consumable", "recreation", "games", "sport", "plant", "foliage",
    ]
    private static let uncountable: Set<String> = ["food", "coffee", "traffic", "snow", "nature", "fireworks", "rain", "sand"]

    static func subject(labels: [String], hasFace: Bool) -> String? {
        if hasFace { return "person" }
        for label in labels {
            let l = label.lowercased()
            if ["food", "drink", "coffee", "dessert", "fruit", "meal", "cake", "beverage"].contains(where: { l.contains($0) }) { return "food" }
            if ["dog", "cat", "animal", "bird", "horse", "pet"].contains(where: { l.contains($0) }) { return "animal" }
            if ["people", "adult", "child", "person", "crowd", "baby"].contains(where: { l.contains($0) }) { return "people" }
            if ["city", "skyscraper", "building", "street", "landscape", "mountain", "beach", "ocean", "sea", "lake",
                "sunset", "interior", "room", "bridge", "sky", "park", "forest", "road", "waterfall", "shore"].contains(where: { l.contains($0) }) { return "place" }
            if ["car", "vehicle", "train", "bicycle", "shoe", "clothing", "bag", "phone", "computer", "book"].contains(where: { l.contains($0) }) { return "object" }
        }
        return labels.isEmpty ? nil : "other"
    }

    static func noun(labels: [String]) -> String? {
        guard let label = labels.first(where: { !generic.contains($0) }) else { return nil }
        if label == "sunset_sunrise" { return "sunset" }
        return label.replacingOccurrences(of: "_", with: " ")
    }

    static func withArticle(_ noun: String) -> String {
        if uncountable.contains(noun) || noun.hasSuffix("s") { return noun }
        return ("aeiou".contains(noun.first ?? "x") ? "an " : "a ") + noun
    }

    /// One short line telling the creator what kind of clip fits a slot.
    static func hint(framing: Template.Framing?, subject: String?, noun: String?, motion: Double, length: Double) -> String {
        let moving = motion > 0.6 ? ", moving" : ""
        switch subject {
        case "person":
            switch framing {
            case .close: return "Close-up of a face\(moving)"
            case .medium: return "A person, waist up\(moving)"
            default: return "A person in a wide shot\(moving)"
            }
        case "people":
            return "A group of people\(moving)"
        default:
            break
        }
        if let noun {
            switch subject {
            case "place": return "Wide shot of \(withArticle(noun))\(moving)"
            case "food", "object": return "Close-up of \(withArticle(noun))"
            case "animal": return "\(withArticle(noun).capitalizedFirst) in frame\(moving)"
            default: return "\(withArticle(noun).capitalizedFirst)\(moving)"
            }
        }
        if length < 0.6 { return "A quick, punchy moment" }
        if motion > 0.6 { return "A clip with lots of movement" }
        if length > 3 { return "A steady shot that holds" }
        return "Any clip you love"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
