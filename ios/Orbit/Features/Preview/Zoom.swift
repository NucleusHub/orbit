import AVKit
import NucleusUI
import SwiftUI

/// Pinch, double-tap and pan zoom for any UIKit content (photos and videos). At normal size it doesn't
/// scroll, so a horizontal swipe reaches the pager and changes the file.
struct ZoomContainer: UIViewRepresentable {
    var onTap: (() -> Void)?
    let makeContent: () -> UIView

    init(onTap: (() -> Void)? = nil, makeContent: @escaping () -> UIView) {
        self.onTap = onTap
        self.makeContent = makeContent
    }

    func makeUIView(context: Context) -> ZoomScrollView { ZoomScrollView(content: makeContent()) }

    func updateUIView(_ view: ZoomScrollView, context: Context) { view.onTap = onTap }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let content: UIView
    var onTap: (() -> Void)?

    init(content: UIView) {
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 6
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(tapped))
        single.require(toFail: double)
        addGestureRecognizer(single)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 {
            content.frame = bounds
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    @objc private func tapped() { onTap?() }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1 {
            setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: content)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}

/// A view whose layer is the player's picture.
final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        let layer = layer as! AVPlayerLayer
        layer.player = player
        layer.videoGravity = .resizeAspect
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Where a player is and whether it's playing, for the custom controls.
@MainActor
@Observable
final class Playback {
    let player: AVPlayer
    var time: Double = 0
    var duration: Double = 0
    var playing = false
    var scrubbing = false
    @ObservationIgnored private var token: Any?
    @ObservationIgnored private var status: NSKeyValueObservation?

    init(player: AVPlayer) {
        self.player = player
        token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, !self.scrubbing else { return }
                self.time = t.seconds.isFinite ? t.seconds : 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite { self.duration = d }
            }
        }
        status = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            Task { @MainActor in self?.playing = playing }
        }
    }

    /// Leaves nothing playing or observing once the page is gone.
    func stop() {
        player.pause()
        if let token { player.removeTimeObserver(token) }
        token = nil
        status = nil
    }

    func toggle() {
        if playing {
            player.pause()
        } else {
            if duration > 0, time >= duration - 0.25 { player.seek(to: .zero) }
            player.play()
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    static func clock(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s.rounded(.down))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// A zoomable video with play/pause and a scrubber; tap shows or hides them.
struct VideoPreview: View {
    let file: OrbitFile
    let isCurrent: Bool
    @Environment(FilesStore.self) private var files
    @State private var playback: Playback?
    @State private var problem: String?
    @State private var locked = false
    @State private var retried = false
    @State private var controls = true

    var body: some View {
        Group {
            if locked {
                LockedPreview(file: file)
            } else if let problem {
                PreviewProblem(message: problem)
            } else if let playback {
                ZStack(alignment: .bottom) {
                    ZoomContainer(onTap: { withAnimation(NucleusMotion.quick) { controls.toggle() } }) {
                        PlayerUIView(player: playback.player)
                    }
                    if controls {
                        bar(playback)
                            .transition(.opacity)
                    }
                }
            } else {
                ProgressView().tint(.white).controlSize(.large)
            }
        }
        .task(id: file.updatedAt) { await start(at: .zero) }
        .onChange(of: isCurrent) { _, now in if now { playback?.player.play() } else { playback?.player.pause() } }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)) { note in
            guard (note.object as? AVPlayerItem) === playback?.player.currentItem else { return }
            Task { await recover() }
        }
        .onDisappear {
            playback?.stop()
            playback = nil
        }
    }

    private func bar(_ playback: Playback) -> some View {
        HStack(spacing: 12) {
            Button { playback.toggle() } label: {
                Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NucleusPressStyle())
            .accessibilityLabel(playback.playing ? "Pause" : "Play")
            Text(verbatim: Playback.clock(playback.time)).monospacedDigit()
            Slider(value: Binding(get: { playback.time }, set: { playback.time = $0; playback.seek(to: $0) }),
                   in: 0...max(playback.duration, 0.1)) { editing in playback.scrubbing = editing }
                .tint(.white)
            Text(verbatim: Playback.clock(playback.duration)).monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .frame(height: 54)
        .nucleusGlass(in: Capsule(), interactive: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
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
            let item = AVPlayerItem(asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers]))
            let player = AVPlayer(playerItem: item)
            if time != .zero { await player.seek(to: time) }
            playback = Playback(player: player)
            if isCurrent { player.play() }
            for await status in item.publisher(for: \.status).values {
                if status == .failed { await recover(); break }
                if status == .readyToPlay { break }
            }
        } catch {
            problem = error.orbitMessage
        }
    }

    /// A long video outlives its token: refresh once and carry on where it stopped.
    private func recover() async {
        guard !retried else {
            problem = String(localized: "Can't play this file here. Share it to open it elsewhere.")
            return
        }
        retried = true
        let at = playback?.player.currentTime() ?? .zero
        try? await files.service.renewAccess()
        await start(at: at)
    }
}
