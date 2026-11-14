import SwiftUI
import UniformTypeIdentifiers

/// A link the user pasted, from any app or website. Twincut downloads a link only when it points
/// straight at a video file; a page link is opened so the user can save the video there.
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

    /// Where the link goes, for buttons like "Open in YouTube": a known app's name, otherwise the site.
    var siteName: String {
        let host = (url.host() ?? "").lowercased()
        let known: [(String, String)] = [
            ("tiktok.com", "TikTok"), ("instagram.com", "Instagram"), ("instagr.am", "Instagram"),
            ("youtube.com", "YouTube"), ("youtu.be", "YouTube"), ("facebook.com", "Facebook"),
            ("fb.watch", "Facebook"), ("x.com", "X"), ("twitter.com", "X"), ("snapchat.com", "Snapchat"),
            ("threads.net", "Threads"), ("threads.com", "Threads"), ("pinterest.com", "Pinterest"),
            ("pin.it", "Pinterest"), ("vimeo.com", "Vimeo"), ("linkedin.com", "LinkedIn"), ("reddit.com", "Reddit"),
        ]
        if let name = known.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) })?.1 { return name }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
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
                Text("That isn't a link. In any app, tap Share on the video, then Copy link.")
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

/// After pasting a link to a page: open it, save the video there, come back.
struct GetVideoSheet: View {
    let link: VideoLink
    let onClose: () -> Void
    let onOpen: () -> Void
    let onPickNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Save the video first")
                    .font(.title2.weight(.bold))
                    .padding(.top, 8)
                Text("Twincut doesn't download from websites or other apps. It reads videos on this device.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 16) {
                    step(1, "Open the link in \(link.siteName).")
                    step(2, "If the video is yours or you have the right to use it, save it to this device there.")
                    step(3, "Come back to Twincut. Your newest videos open on their own.")
                }
                Button {
                    onOpen()
                } label: {
                    Label("Open link", systemImage: "arrow.up.right")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("open-in-app")
                Button("I already have it") { onPickNow() }
                    .buttonStyle(LinkButtonStyle())
                    .frame(maxWidth: .infinity)
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

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(n)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.black)
                .frame(minWidth: 26, minHeight: 26)
                .background(Circle().fill(Theme.accent))
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
