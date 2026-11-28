import AVFoundation
import Photos
import SwiftUI
import SweepCore
import UIKit

/// Loads and shows one library item (low quality first, then sharp).
struct AssetImage: View {
    let id: String
    /// Requested size in pixels.
    let targetSize: CGSize
    var fill = false
    var blurredBackdrop = false
    /// Zoom of the picture (the blurred backdrop stays still).
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.m3) private var m3
    @State private var image: UIImage?
    @State private var loadedID: String?

    /// Zoomed in: ask Photos for a sharper version (up to 3× the size).
    private var hiRes: Bool { zoom > 1.2 }

    private struct LoadKey: Hashable {
        let id: String
        let hiRes: Bool
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    if blurredBackdrop {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 40, opaque: true)
                            .opacity(0.6)
                    }
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fill ? .fill : .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom)
                        .offset(pan)
                        .clipped()
                } else {
                    ProgressView()
                        .tint(m3.onSurfaceVariant)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: LoadKey(id: id, hiRes: hiRes)) {
            // A new photo starts empty; a sharper version of the same photo
            // replaces the current one only when it arrives.
            if loadedID != id { image = nil }
            loadedID = id
            let size = hiRes
                ? CGSize(width: min(targetSize.width * 3, 4096), height: min(targetSize.height * 3, 4096))
                : targetSize
            let stream = library.images(for: id, targetSize: size, contentMode: fill ? .aspectFill : .aspectFit)
            for await next in stream {
                if !hiRes || image == nil || next.size.width >= (image?.size.width ?? 0) { image = next }
            }
        }
    }
}

/// Plays a video without system controls (the card keeps the swipe gesture).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// The big card with the photo (or video) and its details.
struct SwipeCard: View {
    let id: String
    let isTop: Bool
    let targetSize: CGSize
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.m3) private var m3
    @State private var info: AssetInfo?
    @State private var bytes: Int64 = 0
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var loadingVideo = false

    var body: some View {
        ZStack {
            m3.surfaceContainerHighest
            AssetImage(id: id, targetSize: targetSize, blurredBackdrop: true, zoom: zoom, pan: pan)
            if let player {
                PlayerLayerView(player: player)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            details
                .opacity(zoom > 1.01 ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: zoom > 1.01)
        }
        .overlay {
            if info?.isVideo == true && isTop {
                playButton
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(m3.dark ? 0.45 : 0.14), radius: 16, y: 8)
        .task(id: id) {
            info = library.info(for: id)
            bytes = await library.fileSize(of: id)
        }
        .onChange(of: isTop) { _, top in
            if !top { stopVideo() }
        }
        .onDisappear { stopVideo() }
    }

    // MARK: Details

    private var details: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if let date = info?.date {
                    Text(date.sweepLabel)
                        .font(.m3TitleSmall)
                }
                Text(detailLine)
                    .font(.m3LabelMedium)
                    .opacity(0.85)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                if info?.isFavorite == true { badge(icon: "heart.fill", text: nil) }
                if info?.isScreenshot == true { badge(icon: "camera.viewfinder", text: nil) }
                if info?.isLivePhoto == true { badge(icon: "livephoto", text: nil) }
                if let info, info.isVideo { badge(icon: "video.fill", text: SweepFormat.duration(info.duration)) }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 36)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
    }

    private var detailLine: String {
        var parts: [String] = []
        if let info, info.pixelWidth > 0 { parts.append("\(info.pixelWidth)×\(info.pixelHeight)") }
        if bytes > 0 { parts.append(SweepFormat.bytes(bytes)) }
        return parts.joined(separator: " · ")
    }

    private func badge(icon: String, text: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            if let text { Text(text).font(.m3LabelMedium).monospacedDigit() }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(.black.opacity(0.35), in: Capsule())
    }

    // MARK: Video

    private var playButton: some View {
        Button {
            toggleVideo()
        } label: {
            ZStack {
                Circle().fill(.black.opacity(playing ? 0.0 : 0.35))
                if loadingVideo {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(playing ? 0.0 : 1))
                }
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(playing ? "Pausa" : "Riproduci")
    }

    private func toggleVideo() {
        if let player {
            if playing { player.pause() } else { player.play() }
            playing.toggle()
            return
        }
        guard !loadingVideo else { return }
        loadingVideo = true
        Task {
            let item = await library.playerItem(for: id)
            loadingVideo = false
            guard let item, isTop else { return }
            let p = AVPlayer(playerItem: item)
            p.actionAtItemEnd = .pause
            withAnimation(.easeInOut(duration: 0.2)) { player = p }
            p.play()
            playing = true
        }
    }

    private func stopVideo() {
        player?.pause()
        player = nil
        playing = false
    }
}

// MARK: - Zoom

/// Shared math for pinch / double-tap zoom.
enum ZoomMath {
    static let maxZoom: CGFloat = 5
    static let doubleTapZoom: CGFloat = 2.5

    /// Keeps the zoomed picture inside its frame.
    static func clamp(_ pan: CGSize, zoom: CGFloat, size: CGSize) -> CGSize {
        let maxX = max(0, (zoom - 1) * size.width / 2)
        let maxY = max(0, (zoom - 1) * size.height / 2)
        return CGSize(width: min(maxX, max(-maxX, pan.width)), height: min(maxY, max(-maxY, pan.height)))
    }
}

/// Full-screen photo with pinch, pan and double-tap zoom (from the duplicates).
struct PhotoViewer: View {
    let id: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            AssetImage(id: id,
                       targetSize: CGSize(width: geo.size.width * displayScale, height: geo.size.height * displayScale),
                       zoom: zoom, pan: pan)
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(ZoomMath.maxZoom, max(1, lastZoom * value.magnification))
                            pan = ZoomMath.clamp(pan, zoom: zoom, size: geo.size)
                        }
                        .onEnded { _ in
                            lastZoom = zoom
                            if zoom < 1.05 { reset() }
                        }
                        .simultaneously(with: DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                guard zoom > 1.01 else { return }
                                pan = ZoomMath.clamp(CGSize(width: lastPan.width + value.translation.width,
                                                            height: lastPan.height + value.translation.height),
                                                     zoom: zoom, size: geo.size)
                            }
                            .onEnded { value in
                                if zoom > 1.01 {
                                    lastPan = pan
                                } else if value.translation.height > 120 {
                                    dismiss()   // swipe down to close
                                }
                            })
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.35)) {
                        if zoom > 1.01 { reset() } else { zoom = ZoomMath.doubleTapZoom; lastZoom = zoom }
                    }
                }
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(PressableStyle())
            .padding(16)
            .accessibilityLabel("Chiudi")
        }
        .statusBarHidden()
    }

    private func reset() {
        zoom = 1
        lastZoom = 1
        pan = .zero
        lastPan = .zero
    }
}
