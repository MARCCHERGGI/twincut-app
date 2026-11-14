import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x08080A)
    static let surface = Color(hex: 0x141417)
    static let raised = Color(hex: 0x1E1E23)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color.white
    static let text2 = Color(white: 0.72)
    static let text3 = Color(white: 0.64)
    static let accent = Color(hex: 0xE4FF3A)
    static let onAccent = Color.black
    static let danger = Color(hex: 0xFF5A4E)
    static let radius: CGFloat = 22
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// "#rrggbb" from a template; falls back to a neutral grey.
    init(hexString: String) {
        let clean = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(clean, radix: 16) ?? 0x5A5A66)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(Theme.accent.opacity(isEnabled ? 1 : 0.35)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(Theme.raised))
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PillButtonStyle: ButtonStyle {
    var filled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Theme.onAccent : Theme.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(Capsule().fill(filled ? Theme.accent : Theme.raised))
            .opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.75 : 1)
    }
}

/// A text-only button: accent text with a full 44 pt tap target.
struct LinkButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(color)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct StatChip: View {
    let text: String
    var highlight = false

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(highlight ? Theme.onAccent : Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(highlight ? Theme.accent : Theme.raised))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Double {
    /// "0.4 s", "12 s", "1:05".
    var secondsLabel: String {
        if self >= 60 { return String(format: "%d:%02d", Int(self) / 60, Int(self) % 60) }
        if self < 10 { return String(format: "%.1f s", self) }
        return "\(Int(self.rounded())) s"
    }
}

/// A system font at a design size that still grows and shrinks with the user's text size.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let digits: Bool

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle, digits: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.digits = digits
    }

    func body(content: Content) -> some View {
        content.font(digits ? .system(size: size, weight: weight).monospacedDigit() : .system(size: size, weight: weight))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body, digits: Bool = false) -> some View {
        modifier(ScaledFont(size: size, weight: weight, relativeTo: style, digits: digits))
    }
}
