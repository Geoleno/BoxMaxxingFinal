import SwiftUI
import AVFoundation

// A reusable SwiftUI view that plays a video from a URL, seeking to a specific
// timestamp before starting. Used in DetailSheetView to show the user's clip
// starting exactly at the moment a flagged punch occurred.
struct VideoPlayerView: UIViewRepresentable {
    let url: URL
    let startSeconds: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let player = AVPlayer(url: url)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)

        // toleranceBefore/After .zero = frame-accurate seek.
        // Default tolerance snaps to the nearest keyframe (~1s off), which is
        // too imprecise when events are only 3 seconds apart.
        let seekTime = CMTime(seconds: Double(startSeconds), preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
        }

        context.coordinator.player      = player
        context.coordinator.playerLayer = playerLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Keep the AVPlayerLayer filling the view when its size changes (e.g. rotation)
        context.coordinator.playerLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        // Pause automatically when the detail sheet is dismissed and this view is destroyed
        deinit { player?.pause() }
    }
}
