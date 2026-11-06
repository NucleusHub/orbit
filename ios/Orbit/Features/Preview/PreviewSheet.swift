import AVKit
import NucleusUI
import PDFKit
import SwiftUI

/// Files full-screen, one page each: swipe to the next or previous file in the folder or search (the web's FilePreviewModal).
struct PreviewSheet: View {
    let file: OrbitFile
    let folderID: String?
    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String?
    @State private var sharing = false

    /// The files the preview was opened among, in their order.
    private var pages: [OrbitFile] {
        if let l = files.listing(folderID), l.files.contains(where: { $0.id == file.id }) { return l.files }
        if let s = files.searchResults, s.files.contains(where: { $0.id == file.id }) { return s.files }
        return [files.file(file.id) ?? file]
    }

    /// Follows the listing, so a conversion's progress shows here too.
    private var current: OrbitFile {
        let id = currentID ?? file.id
        return pages.first { $0.id == id } ?? files.file(id) ?? file
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                pager
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
        .onAppear { if currentID == nil { currentID = file.id } }
        .onChange(of: files.isFaceIDLocked(.file(current))) { _, locked in
            // Relocked while open (back from the background): close rather than keep the file on screen.
            if locked, files.faceIDLock(for: current.id) == nil { dismiss() }
        }
        .onChange(of: currentID) { _, _ in Haptics.selection() }
        .task(id: "\(current.id)-\(current.transcodeStatus.isActive)") {
            // Keeps the progress moving even when the folder page behind isn't polling (search results).
            while current.transcodeStatus.isActive, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await files.refreshFolder(of: current)
            }
        }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages) { page in
                    FilePage(file: page, isCurrent: page.id == (currentID ?? file.id))
                        .opacity(currentID == nil ? 0 : 1)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(page.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(spacing: 10) {
            GlassCircleButton("xmark") { dismiss() }
                .accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: current.filename)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if pages.count > 1, let i = pages.firstIndex(where: { $0.id == current.id }) {
                    Text("\(i + 1) of \(pages.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if current.transcodeStatus.isActive {
                ConvertingLabel(file: current)
            } else if current.canConvert, current.canEdit, !files.isFaceIDLocked(.file(current)) {
                GlassCircleButton("arrow.triangle.2.circlepath") {
                    ItemActions(files: files, navigator: navigator, folderID: folderID).convert(current)
                }
                .accessibilityLabel("Convert")
            }
            GlassCircleButton(sharing ? "hourglass" : "square.and.arrow.up") {
                guard !sharing, !files.isFaceIDLocked(.file(current)) else { return }
                sharing = true
                Task {
                    defer { sharing = false }
                    do { try await ShareExport.share(current, files: files) } catch { navigator.fail(error) }
                }
            }
            .accessibilityLabel("Share or save")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// One file in the pager.
private struct FilePage: View {
    let file: OrbitFile
    let isCurrent: Bool
    @Environment(FilesStore.self) private var files

    var body: some View {
        if files.isFaceIDLocked(.file(file)) {
            FaceIDPage(file: file)
        } else {
            switch file.kind {
            case .image: ImagePreview(file: file)
            case .video: VideoPreview(file: file, isCurrent: isCurrent)
            case .audio: MediaPreview(file: file, isCurrent: isCurrent)
            case .pdf: PDFPreview(file: file)
            case .text, .code: TextPreview(file: file)
            case .archive, .other: NoPreview(file: file)
            }
        }
    }
}

private struct FaceIDPage: View {
    let file: OrbitFile
    @Environment(FilesStore.self) private var files
    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "faceid").font(.system(size: 44)).foregroundStyle(.white.opacity(0.8))
            Text("Locked with Face ID").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Button {
                // After a password fallback the preview comes back on this file.
                let file = file
                ItemActions(files: files, navigator: navigator, folderID: file.folderId).faceID(.file(file)) {
                    if navigator.sheet == nil { navigator.present(.preview(file, in: file.folderId)) }
                }
            } label: {
                Label("Unlock with Face ID", systemImage: "faceid")
            }
            .buttonStyle(NucleusPrimaryButtonStyle())
            .fixedSize()
        }
    }
}

private struct NoPreview: View {
    let file: OrbitFile

    var body: some View {
        VStack(spacing: 16) {
            TypeGlyph(kind: file.kind, size: 40)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text("No preview available").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Text(verbatim: Formatting.size(file.size)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
            Text("Share it to open it in another app or save it to Files.")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

/// Loads a file's bytes for a preview, with a spinner and an error.
private struct Loaded<Content: View>: View {
    let file: OrbitFile
    let maxBytes: Int64?
    @ViewBuilder let content: (Data) -> Content
    @Environment(FilesStore.self) private var files
    @State private var data: Data?
    @State private var problem: String?
    @State private var locked = false

    var body: some View {
        Group {
            if let data {
                content(data)
            } else if locked {
                LockedPreview(file: file)
            } else if let problem {
                PreviewProblem(message: problem)
            } else {
                ProgressView().tint(.white).controlSize(.large)
            }
        }
        .onDisappear { data = nil }
        .task(id: "\(file.id)-\(file.updatedAt)") {
            if let maxBytes, file.size > maxBytes {
                problem = String(localized: "This file is too large to preview. Share it to open it elsewhere.")
                return
            }
            do {
                data = try await files.data(for: file)
            } catch OrbitError.forbidden {
                // A search hit inside a protected folder: its plain URL is refused until unlocked.
                locked = true
            } catch {
                problem = error.orbitMessage
            }
        }
    }
}

/// A search hit inside a protected folder: its plain URL is refused until unlocked.
struct LockedPreview: View {
    let file: OrbitFile
    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(spacing: 16) {
            PreviewProblem(message: String(localized: "This file is in a protected folder."))
            Button("Unlock") {
                // The unlock sheet replaces this one, then reopens the preview with the unlocked URL.
                let file = file
                navigator.unlock(.file(file)) { navigator.present(.preview(file, in: file.folderId)) }
            }
            .buttonStyle(NucleusPrimaryButtonStyle())
            .fixedSize()
        }
    }
}

struct PreviewProblem: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 30)).foregroundStyle(.white.opacity(0.7))
            Text(verbatim: message).font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct ImagePreview: View {
    let file: OrbitFile

    var body: some View {
        Loaded(file: file, maxBytes: nil) { data in
            // Screen-sized, so swiping through many photos doesn't keep full-resolution bitmaps around.
            if let image = ThumbnailCache.downsample(data, maxPixel: 3000) {
                ZoomContainer {
                    let view = UIImageView(image: image)
                    view.contentMode = .scaleAspectFit
                    return view
                }
                .accessibilityLabel(Text(verbatim: file.filename))
            } else {
                PreviewProblem(message: String(localized: "This image can't be shown here. Share it to open it elsewhere."))
            }
        }
    }
}

struct PDFPreview: View {
    let file: OrbitFile

    var body: some View {
        Loaded(file: file, maxBytes: nil) { data in
            if let document = PDFDocument(data: data) {
                PDFKitView(document: document)
            } else {
                PreviewProblem(message: String(localized: "This PDF can't be shown here. Share it to open it elsewhere."))
            }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .black
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

struct TextPreview: View {
    let file: OrbitFile

    var body: some View {
        Loaded(file: file, maxBytes: 1_000_000) { data in
            ScrollView {
                Text(verbatim: String(decoding: data, as: UTF8.self))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }
}

/// Video and audio, streamed with the sign-in header. A long video outlives its token, so a failure retries once fresh.
struct MediaPreview: View {
    let file: OrbitFile
    var isCurrent = true
    @Environment(FilesStore.self) private var files
    @State private var player: AVPlayer?
    @State private var problem: String?
    @State private var locked = false
    @State private var retried = false

    var body: some View {
        Group {
            if locked {
                LockedPreview(file: file)
            } else if let problem {
                PreviewProblem(message: problem)
            } else if let player {
                VideoPlayer(player: player) {
                    if file.kind == .audio {
                        VStack(spacing: 14) {
                            TypeGlyph(kind: .audio, size: 40).frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            Text(verbatim: file.filename).foregroundStyle(.white).font(.system(size: 15, weight: .medium))
                        }
                    }
                }
            } else {
                ProgressView().tint(.white).controlSize(.large)
            }
        }
        .task(id: file.updatedAt) { await start(at: .zero) }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)) { note in
            guard (note.object as? AVPlayerItem) === player?.currentItem else { return }
            Task { await recover() }
        }
        .onDisappear { player?.pause() }
        .onChange(of: isCurrent) { _, now in if now { player?.play() } else { player?.pause() } }
    }

    private func start(at time: CMTime) async {
        do {
            // AVPlayer can't tell a refused stream from a broken one; ask first so a locked file gets its prompt.
            try await files.probe(file)
        } catch OrbitError.forbidden {
            locked = true
            return
        } catch {
            problem = error.orbitMessage
            return
        }
        guard let path = files.resolvedURL(for: file) else { locked = true; return }
        do {
            let (url, headers) = try await files.service.streamRequest(for: path)
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item = AVPlayerItem(asset: asset)
            let next = AVPlayer(playerItem: item)
            if time != .zero { await next.seek(to: time) }
            player = next
            if isCurrent { next.play() }
            for await status in item.publisher(for: \.status).values {
                if status == .failed { await recover(); break }
                if status == .readyToPlay { break }
            }
        } catch {
            problem = error.orbitMessage
        }
    }

    private func recover() async {
        guard !retried else {
            problem = String(localized: "Can't play this file here. Share it to open it elsewhere.")
            return
        }
        retried = true
        let at = player?.currentTime() ?? .zero
        try? await files.service.renewAccess()
        await start(at: at)
    }
}
