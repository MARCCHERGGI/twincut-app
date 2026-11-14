import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var referenceItem: PhotosPickerItem?
    @State private var analyzing: AnalyzeRequest?
    @State private var finished: Template?
    @State private var showHowTo = false
    @State private var showSettings = false
    @State private var renaming: Template?
    @State private var newTitle = ""
    @State private var checkingLink = false
    @State private var pageLink: VideoLink?
    @State private var awaitingSave = false
    @State private var showPicker = false
    @State private var pickAfterSheet = false
    @State private var showFiles = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                hero
                section(title: "Start from a template", templates: model.library.starters, idPrefix: "starter")
                yours
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: referenceItem) { _, item in
            guard let item else { return }
            analyzing = AnalyzeRequest(source: .photos(item))
            referenceItem = nil
        }
        .fullScreenCover(item: $analyzing, onDismiss: {
            if let t = finished {
                finished = nil
                model.open(t)
            }
        }) { request in
            AnalyzeView(source: request.source) { template in
                model.library.add(template)
                finished = template
                analyzing = nil
            } onCancel: {
                analyzing = nil
            }
        }
        .sheet(item: $pageLink, onDismiss: {
            // Present the picker only once the sheet is gone; two presentations at once drop one.
            if pickAfterSheet {
                pickAfterSheet = false
                showPicker = true
            }
        }) { link in
            GetVideoSheet(link: link) {
                awaitingSave = true
                pageLink = nil
                openURL(link.url)
            } onPickNow: {
                pickAfterSheet = true
                pageLink = nil
            }
        }
        // Back from the other app with the video saved: open the picker, newest first.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && awaitingSave {
                awaitingSave = false
                showPicker = true
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $referenceItem, matching: .videos, preferredItemEncoding: .current)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie]) { result in
            if case .success(let url) = result { analyzing = AnalyzeRequest(source: .file(url)) }
        }
        .sheet(isPresented: $showHowTo) { WhatToCopyView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("Rename template", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Save") {
                if let t = renaming { model.library.rename(t.id, to: newTitle) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var header: some View {
        HStack {
            Text("Twincut")
                .scaledFont(30, .heavy, relativeTo: .largeTitle)
                .tracking(-0.5)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .scaledFont(17, .semibold)
                    .foregroundStyle(Theme.text2)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.raised))
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings")
        }
        .padding(.top, 8)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroBars()
                .frame(height: 70)
            Text("Copy any video's edit")
                .scaledFont(28, .bold, relativeTo: .title)
            Text("Pick a video or paste a link from any app. Twincut finds every cut, the beat and where the captions sit, without uploading anything.")
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            PhotosPicker(selection: $referenceItem, matching: .videos, preferredItemEncoding: .current) {
                Label("Choose a video", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("choose-reel")
            PasteLinkBox(checking: checkingLink) { link in
                Task { await open(link) }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    filesButton
                    Spacer()
                    copyHelp
                    Spacer()
                    sampleButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    filesButton
                    copyHelp
                    sampleButton
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.stroke))
    }

    private var filesButton: some View {
        Button("From Files") { showFiles = true }
            .buttonStyle(LinkButtonStyle())
            .accessibilityIdentifier("choose-file")
    }

    /// A direct video link is read straight away; a page opens in its own app first.
    private func open(_ link: VideoLink) async {
        checkingLink = true
        defer { checkingLink = false }
        if await LinkDownloader.pointsAtVideo(link) {
            analyzing = AnalyzeRequest(source: .link(link))
        } else {
            pageLink = link
        }
    }

    private var copyHelp: some View {
        Button("What can I copy?") { showHowTo = true }
            .buttonStyle(LinkButtonStyle())
    }

    private var sampleButton: some View {
        Button("Try a sample reel") { analyzing = AnalyzeRequest(source: .sample) }
            .buttonStyle(LinkButtonStyle())
            .accessibilityIdentifier("sample-reel")
    }

    private func section(title: String, templates: [Template], idPrefix: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: title)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(templates.enumerated()), id: \.element.id) { i, t in
                        Button { model.open(t) } label: { TemplateCard(template: t) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(idPrefix)-card-\(i)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private var yours: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Your templates")
            if model.library.templates.isEmpty {
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        Text("Videos you copy are saved here as templates you can use again.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.text2)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(model.library.templates) { t in
                        Button { model.open(t) } label: { TemplateCard(template: t, fillsWidth: true) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") {
                                    newTitle = t.title
                                    renaming = t
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    model.library.delete(t.id)
                                }
                            }
                    }
                }
            }
        }
    }
}

struct AnalyzeRequest: Identifiable {
    let id = UUID()
    let source: ReelSource
}

/// Poster for a template: a frame of footage for starters (bundled `<id>.jpg`), otherwise its
/// shots as a colour barcode; the cut rhythm runs along the bottom either way.
struct TemplateCard: View {
    let template: Template
    var fillsWidth = false

    private var poster: UIImage? {
        Bundle.main.url(forResource: template.id, withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    }

    private func barcode(width: CGFloat) -> some View {
        let scale: CGFloat = width / CGFloat(max(template.duration, 0.01))
        return ZStack(alignment: .leading) {
            ForEach(template.shots) { shot in
                Rectangle()
                    .fill(Color(hexString: shot.color))
                    .frame(width: max(1, CGFloat(shot.duration) * scale - 1))
                    .offset(x: CGFloat(shot.start) * scale)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                Group {
                    if let poster {
                        Image(uiImage: poster)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .overlay(alignment: .bottom) { barcode(width: geo.size.width).frame(height: 5) }
                    } else {
                        barcode(width: geo.size.width)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    if let bpm = template.tempo?.bpm {
                        Text("\(Int(bpm.rounded())) BPM")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.black.opacity(0.8)))
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(height: fillsWidth ? 200 : 230)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2, reservesSpace: !fillsWidth)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(template.shots.count) shots · \(template.duration.secondsLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.text3)
            }
        }
        .frame(width: fillsWidth ? nil : 150)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardLabel)
    }

    private var cardLabel: String {
        var parts = [template.title, "\(template.shots.count) shots", template.duration.secondsLabel]
        if let bpm = template.tempo?.bpm { parts.append("\(Int(bpm.rounded())) BPM") }
        return parts.joined(separator: ", ")
    }
}

/// Decorative strip on the home card: bars pulsing like an edit on the beat.
struct HeroBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let widths: [CGFloat] = [0.7, 0.35, 1.0, 0.5, 0.3, 0.85, 0.45, 0.6, 0.3, 0.9, 0.55, 0.4]
    private let colors: [Color] = ([0xE4FF3A, 0x5EE0FF, 0xFF6BA8, 0xB28CFF, 0xFFB547, 0x4DF0A8] as [UInt32]).map { Color(hex: $0) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let beat: Double = context.date.timeIntervalSinceReferenceDate * 2
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(widths.indices, id: \.self) { i in
                        bar(i, beat: beat, size: geo.size)
                    }
                }
                .frame(height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(_ i: Int, beat: Double, size: CGSize) -> some View {
        let total: CGFloat = widths.reduce(0, +)
        let usable: CGFloat = size.width - 3 * CGFloat(widths.count - 1)
        let pulse: CGFloat = CGFloat(max(0, cos((beat - Double(i) * 0.5) * Double.pi)))
        let height: CGFloat = size.height * (0.55 + 0.45 * pulse)
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(colors[i % colors.count])
            .frame(width: usable * widths[i] / total, height: height)
    }
}
