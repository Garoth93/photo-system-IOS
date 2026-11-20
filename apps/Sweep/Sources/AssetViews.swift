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

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.m3) private var m3
    @State private var image: UIImage?

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
                        .clipped()
                } else {
                    ProgressView()
                        .tint(m3.onSurfaceVariant)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task(id: id) {
            image = nil
            let stream = library.images(for: id, targetSize: targetSize, contentMode: fill ? .aspectFill : .aspectFit)
            for await next in stream {
                image = next
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
            AssetImage(id: id, targetSize: targetSize, blurredBackdrop: true)
            if let player {
                PlayerLayerView(player: player)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { details }
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
