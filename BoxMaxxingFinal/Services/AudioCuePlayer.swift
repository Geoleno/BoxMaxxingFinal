import AVFoundation

// MARK: - Audio Cue Player
// PLACEHOLDER — Developer to add .mp3 audio files to the Xcode project.

final class AudioCuePlayer {

    private var audioPlayer: AVAudioPlayer?

    // Keyed by Move.id ("lj", "rj", "lh", "rh", "lu", "ru")
    // TODO: Add these .mp3 files to the Xcode project bundle
    private let audioAssets: [String: String] = [
        "lj": "cue_left_jab.mp3",           // TODO: Add file
        "rj": "cue_right_jab.mp3",          // TODO: Add file
        "lh": "cue_left_hook.mp3",          // TODO: Add file
        "rh": "cue_right_hook.mp3",         // TODO: Add file
        "lu": "cue_left_uppercut.mp3",      // TODO: Add file
        "ru": "cue_right_uppercut.mp3"      // TODO: Add file
    ]

    func playAudioCue(for moveId: String) {
        guard let fileName = audioAssets[moveId] else {
            print("AudioCuePlayer: No audio asset mapped for move '\(moveId)'")
            return
        }

        // TODO: Ensure audio files are added to the Xcode project target
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            print("AudioCuePlayer: File not found in bundle — \(fileName)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("AudioCuePlayer: Playback failed — \(error)")
        }
    }
}
