import SwiftUI
import UniformTypeIdentifiers

/// A link the user pasted, from any app or website. Twincut downloads a link only when it points
/// straight at a video file off the big video apps (5.2.3: no media from third-party sources);
/// for anything else it asks the user to pick a video saved on the device.
struct VideoLink: Identifiable, Equatable {
    let url: URL
    var id: URL { url }

    /// The first web link in `text`, if any. Bare addresses like "vimeo.com/123" count too.
    init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              var parts = match.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }),
              parts.scheme == "https" || parts.scheme == "http",
              parts.host?.contains(".") == true
        else { return nil }
        // iOS only loads secure links; nearly every site serves the same address over https.
        parts.scheme = "https"
        guard let url = parts.url else { return nil }
        self.url = url
    }

    /// True when the address itself names a video file, like ".../clip.mp4".
    var namesVideoFile: Bool {
        ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    /// Where the link goes: a video app's name, otherwise the site.
    var siteName: String {
        if let platform { return platform }
        let host = (url.host() ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The video app this link belongs to, including the servers it streams its videos from.
    /// Twincut never fetches from these: their videos aren't the user's to download.
    var platform: String? { Self.platform(of: url) }

    /// The video app an address belongs to; also checked on every redirect a link takes.
    static func platform(of url: URL) -> String? {
        // "www.youtube.com." is the same host as "www.youtube.com".
        var host = (url.host() ?? "").lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        return platforms.first { $0.domains.contains { host == $0 || host.hasSuffix("." + $0) } }?.name
    }

    private static let platforms: [(name: String, domains: [String])] = [
        ("TikTok", ["tiktok.com", "tiktokcdn.com", "tiktokcdn-us.com", "tiktokv.com", "ibytedtos.com", "byteoversea.com", "muscdn.com"]),
        ("Instagram", ["instagram.com", "instagr.am", "cdninstagram.com"]),
        ("Facebook", ["facebook.com", "fb.watch", "fb.com", "fbcdn.net"]),
        ("Threads", ["threads.net", "threads.com"]),
        ("YouTube", ["youtube.com", "youtu.be", "youtube-nocookie.com", "googlevideo.com", "ytimg.com"]),
        ("X", ["x.com", "twitter.com", "twimg.com", "t.co"]),
        ("Snapchat", ["snapchat.com", "sc-cdn.net", "snap.com"]),
        ("Pinterest", ["pinterest.com", "pin.it", "pinimg.com"]),
        ("Vimeo", ["vimeo.com", "vimeocdn.com"]),
        ("LinkedIn", ["linkedin.com", "licdn.com", "lnkd.in"]),
        ("Reddit", ["reddit.com", "redd.it", "redditmedia.com"]),
        ("Twitch", ["twitch.tv", "ttvnw.net"]),
        ("Dailymotion", ["dailymotion.com", "dai.ly", "dmcdn.net"]),
        ("Tumblr", ["tumblr.com"]),
    ]
}

/// The link box on Home: type or paste a link, or tap Paste.
struct PasteLinkBox: View {
    let checking: Bool
    let onLink: (VideoLink) -> Void
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                Image(systemName: "link")
                    .scaledFont(16, .semibold)
                    .foregroundStyle(Theme.text2)
                    .accessibilityHidden(true)
                TextField("Video link", text: $text, prompt: Text("Paste a link"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { submit(text) }
                    .accessibilityIdentifier("link-field")
                if checking {
                    ProgressView()
                        .tint(Theme.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Checking link")
                } else if text.isEmpty {
                    PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
                        Task { @MainActor in
                            for provider in providers {
                                if let pasted = await Self.text(from: provider) {
                                    text = pasted
                                    submit(pasted)
                                    return
                                }
                            }
                            invalid = true
                        }
                    }
                    .labelStyle(.titleOnly)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("paste-link")
                } else {
                    Button("Go") { submit(text) }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.accent))
                        .accessibilityIdentifier("open-link")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
            if invalid {
                Text("That isn't a link. Paste a web address, like a link to a video file in your cloud drive.")
                    .font(.footnote)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func submit(_ value: String) {
        guard let link = VideoLink(text: value) else {
            invalid = true
            return
        }
        invalid = false
        focused = false
        text = ""
        onLink(link)
    }

    /// The pasted link or text, whichever the copying app put on the clipboard.
    private static func text(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { done in
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url?.absoluteString) }
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in done.resume(returning: string) }
            } else {
                done.resume(returning: nil)
            }
        }
    }
}

/// After pasting a link that isn't a video file Twincut may fetch: pick a saved video instead.
struct GetVideoSheet: View {
    let link: VideoLink
    let onClose: () -> Void
    let onPickNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Use a video on this device")
                    .font(.title2.weight(.bold))
                    .padding(.top, 8)
                Text(link.platform.map { "Twincut doesn't take videos from \($0)." }
                     ?? "This link opens a page on \(link.siteName), not a video file.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("link-sheet-reason")
                Text("Pick a video saved in Photos or Files that's yours or that you have the right to use. A link straight to a video file, like one from your own cloud drive, works too.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onPickNow()
                } label: {
                    Label("Choose a video", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pick-saved-video")
                Button("Not now") { onClose() }
                    .buttonStyle(LinkButtonStyle(color: Theme.text))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("close-link-sheet")
            }
            .padding(24)
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
