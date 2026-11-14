import Foundation

/// The edit structure of a reference video: where it cuts, the beat it rides, what each shot
/// looks like, and where its captions sit. Never contains the reference's pixels or audio.
struct Template: Codable, Identifiable, Hashable {
    var version: Int = 1
    var id: String
    var title: String
    var source: Source
    var duration: Double
    var aspect: Aspect
    var pace: Pace
    var tempo: Tempo?
    var beats: [Double]
    var onBeat: Double
    var shots: [Shot]
    var texts: [TextBeat]
    var tags: [String]
    var labeledBy: String?
    var createdAt: Date?

    struct Source: Codable, Hashable {
        var kind: String
        var platform: String?
    }

    struct Aspect: Codable, Hashable {
        var width: Int
        var height: Int
    }

    enum Pace: String, Codable, Hashable {
        case single, slow, steady, fast, rapid

        var label: String {
            switch self {
            case .single: return "One take"
            case .slow: return "Slow"
            case .steady: return "Steady"
            case .fast: return "Fast"
            case .rapid: return "Rapid"
            }
        }
    }

    struct Tempo: Codable, Hashable {
        var bpm: Double
        var confidence: Double
    }

    enum Framing: String, Codable, Hashable {
        case close, medium, wide
    }

    struct Shot: Codable, Hashable, Identifiable {
        var index: Int
        var start: Double
        var end: Double
        var color: String
        var brightness: Double
        var motion: Double
        var framing: Framing?
        var subject: String?
        var camera: String?
        var hint: String

        var id: Int { index }
        var duration: Double { end - start }
    }

    enum Position: String, Codable, Hashable {
        case top, middle, bottom

        /// Vertical centre of a caption as a fraction of frame height, kept clear of the
        /// app chrome Instagram and TikTok draw over the top and bottom of a reel.
        var y: Double {
            switch self {
            case .top: return 0.22
            case .middle: return 0.5
            case .bottom: return 0.72
            }
        }
    }

    enum Size: String, Codable, Hashable {
        case small, medium, large
    }

    struct TextBeat: Codable, Hashable {
        var text: String
        var start: Double
        var end: Double
        var position: Position
        var size: Size
    }

    var cutCount: Int { max(0, shots.count - 1) }

    /// Most clips a user can spread across this template: one per shot, or more when the
    /// beat grid leaves room to split long shots.
    var maxClips: Int { min(30, max(shots.count, Int(duration / 0.6))) }

    var suggestedClips: Int { min(maxClips, max(1, shots.count)) }
}

extension Template {
    static func decodeList(from data: Data) throws -> [Template] {
        try JSONDecoder.reelsy.decode([Template].self, from: data)
    }

    static func decode(from data: Data) throws -> Template {
        try JSONDecoder.reelsy.decode(Template.self, from: data)
    }
}

extension JSONDecoder {
    static let reelsy: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let reelsy: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}
