import AVFoundation
import Foundation

// MARK: - Clip Recorder

final class ClipRecorder {

    static let shared = ClipRecorder()
    private init() { prepareDirectories() }

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var tempClipURL: URL?
    private var isCapturing = false
    private var frameCount: Int64 = 0
    private let frameRate: Int32 = 30

    // MARK: - Directories

    private var tempDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadowBoxClips", isDirectory: true)
    }

    private var permanentDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SessionClips", isDirectory: true)
    }

    private func prepareDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: permanentDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Start (called at T=0s of each move window)

    func startClip(for moveId: String, windowIndex: Int) {
        let safeName = moveId.replacingOccurrences(of: " ", with: "_")
        let fileName = "temp_\(safeName)_\(windowIndex).mp4"
        let url = tempDirectory.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: url)
        tempClipURL = url

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            print("ClipRecorder: Failed to create AVAssetWriter for window \(windowIndex)")
            return
        }
        assetWriter = writer

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        videoInput = input

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil
        )

        if writer.canAdd(input) { writer.add(input) }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        frameCount = 0
        isCapturing = true
    }

    // MARK: - Append Frame (called on every camera frame during the window)

    func appendFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isCapturing,
              let input = videoInput,
              input.isReadyForMoreMediaData,
              let adaptor else { return }

        let presentationTime = CMTime(value: frameCount, timescale: frameRate)
        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        frameCount += 1
    }

    // MARK: - Stop & Evaluate (called at T=3s)

    func stopAndEvaluate(
        confidence: Float,
        predictedLabel: String,
        moveId: String,
        windowIndex: Int,
        completion: @escaping (URL?) -> Void
    ) {
        guard isCapturing else {
            completion(nil)
            return
        }

        isCapturing = false
        videoInput?.markAsFinished()

        assetWriter?.finishWriting { [weak self] in
            guard let self else { return }

            let pct = confidence * 100
            let isSpecialCase = (predictedLabel == "no_body_detected" || predictedLabel == "no_movement_detected")

            if !isSpecialCase && pct >= 85 {
                // 🟢 GREEN — discard clip immediately
                if let url = self.tempClipURL {
                    try? FileManager.default.removeItem(at: url)
                }
                completion(nil)
            } else {
                // 🟡 YELLOW / 🔴 RED / ⚠️ NO SCAN / ❌ NO MOVEMENT — keep clip
                let ratingTag: String
                if predictedLabel == "no_body_detected" { ratingTag = "noscan" }
                else if predictedLabel == "no_movement_detected" { ratingTag = "nomovement" }
                else if pct >= 50 { ratingTag = "yellow" }
                else { ratingTag = "red" }

                let safeName = moveId.replacingOccurrences(of: " ", with: "_")
                let ts = Int(Date().timeIntervalSince1970)
                let savedName = "\(ratingTag)_\(safeName)_\(windowIndex)_\(ts).mp4"
                let savedURL = self.permanentDirectory.appendingPathComponent(savedName)

                do {
                    if let tempURL = self.tempClipURL {
                        try FileManager.default.moveItem(at: tempURL, to: savedURL)
                        completion(savedURL)
                    } else {
                        completion(nil)
                    }
                } catch {
                    print("ClipRecorder: Failed to save clip — \(error)")
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Cleanup

    func deleteAllClips() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil) {
            files.forEach { try? fm.removeItem(at: $0) }
        }
        if let files = try? fm.contentsOfDirectory(at: permanentDirectory, includingPropertiesForKeys: nil) {
            files.forEach { try? fm.removeItem(at: $0) }
        }
    }
}
