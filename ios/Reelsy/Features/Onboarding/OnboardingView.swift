import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [(title: String, body: String)] = [
        ("Copy any video's edit", "Pick a video from Photos. Twincut finds every cut, the beat and where the captions sit, without uploading anything."),
        ("Your clips, its rhythm", "Choose how many clips you want. Twincut times each one to the beat, and you can pick which moment of a clip plays."),
        ("Ready to post", "Export in 1080p with a beat Twincut makes to fit your cuts. It's yours to post anywhere."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 28) {
                        Spacer(minLength: 12)
                        OnboardingArt(page: i)
                            .frame(minHeight: 120, maxHeight: 340)
                        VStack(spacing: 12) {
                            Text(pages[i].title)
                                .scaledFont(32, .bold, relativeTo: .largeTitle)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(pages[i].body)
                                .font(.body)
                                .foregroundStyle(Theme.text2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 28)
                        .layoutPriority(1)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.accent : Theme.raised)
                        .frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            .animation(.spring(response: 0.35), value: page)
            .padding(.bottom, 20)

            Button(page == pages.count - 1 ? "Get started" : "Continue") {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("onboarding-next")
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .sensoryFeedback(.selection, trigger: page)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// Drawn, not filmed: each page animates the idea it explains.
struct OnboardingArt: View {
    let page: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors: [Color] = ([0x5EE0FF, 0xFF6BA8, 0xE4FF3A, 0xB28CFF, 0xFFB547, 0x4DF0A8, 0xFF7A59, 0x8FB3FF] as [UInt32]).map { Color(hex: $0) }
    private let widths: [CGFloat] = [0.9, 0.5, 1.3, 0.7, 0.45, 1.1, 0.6, 0.85, 0.5, 1.0]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            switch page {
            case 0: scan(t)
            case 1: slots(t)
            default: export(t)
            }
        }
        .accessibilityHidden(true)
    }

    private func phone<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1.5))
            .overlay(content().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)).padding(6))
            .frame(width: 180, height: 320)
    }

    private func scan(_ t: Double) -> some View {
        let phase = (t / 3).truncatingRemainder(dividingBy: 1)
        return VStack(spacing: 22) {
            phone {
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { i in colors[i].opacity(0.85) }
                    }
                    Rectangle()
                        .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.9), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 40)
                        .offset(y: phase * 300 - 20)
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<10, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colors[i % colors.count])
                        .frame(width: widths[i] * 26, height: 26)
                        .opacity(Double(i) / 10 < phase ? 1 : 0.15)
                }
            }
        }
    }

    private func slots(_ t: Double) -> some View {
        let phase = (t / 2.4).truncatingRemainder(dividingBy: 1)
        return VStack(spacing: 30) {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colors[i])
                        .frame(width: 62, height: 110)
                        .offset(y: sin((t * 2) + Double(i)) * 6)
                }
            }
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { i in
                    let filled = Double(i) / 9 < phase
                    RoundedRectangle(cornerRadius: 5)
                        .fill(filled ? colors[i % 3] : Theme.raised)
                        .frame(width: widths[i] * 30, height: 54)
                        .scaleEffect(filled ? 1 : 0.92)
                }
            }
            .animation(.spring(response: 0.3), value: Int(phase * 9))
        }
    }

    private func export(_ t: Double) -> some View {
        let progress = min(1, (t / 2.6).truncatingRemainder(dividingBy: 1.3))
        return VStack(spacing: 26) {
            phone {
                ZStack {
                    LinearGradient(colors: [colors[0], colors[3]], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack {
                        Spacer()
                        Text("1080p")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.45)))
                            .padding(.bottom, 14)
                    }
                }
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised).frame(width: 200, height: 8)
                Capsule().fill(Theme.accent).frame(width: 200 * progress, height: 8)
            }
        }
    }
}
