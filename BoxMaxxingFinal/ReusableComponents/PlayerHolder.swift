import AVFoundation
import CoreMedia
import Combine

// MARK: - PlayerHolder

final class PlayerHolder: ObservableObject {
    @Published var player = AVPlayer()
    @Published var aspectRatio: CGFloat = 9 / 16  // updated once the track loads

    func load(url: URL, seekTo time: CMTime) {
        let asset = AVAsset(url: url)
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))

        Task {
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            let naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 9, height: 16)
            let transform   = (try? await track.load(.preferredTransform)) ?? .identity
            let displayed   = naturalSize.applying(transform)
            let w = abs(displayed.width)
            let h = abs(displayed.height)
            await MainActor.run {
                if w > 0 && h > 0 { self.aspectRatio = w / h }
            }
        }

        let offset   = CMTime(seconds: 0.5, preferredTimescale: 600)
        let seekTime = CMTimeMaximum(CMTimeSubtract(time, offset), .zero)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished, let self else { return }
            self.player.play()
        }
    }
}
