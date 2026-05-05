import AVFoundation
import Vision
import Foundation

// MARK: - Supporting Type

// One prediction produced by the 60-frame sliding window.
// label must match a Move.id value from Models.swift (e.g. "lj", "rj").
struct WindowPrediction: Equatable {
    let label: String
    let confidence: Float   // 0.0–1.0
    let startTime: Double   // seconds from video start (first frame of window)
    let endTime: Double     // seconds from video start (last frame of window)
}

// MARK: - Post Session Analyzer

final class PostSessionAnalyzer {

    static let shared = PostSessionAnalyzer()
    private init() {}

    // MARK: - Constants

    let clipPaddingSeconds: Double = 0.5
    let windowSize = 60     // frames — must match Create ML training config
    let strideSize  = 15    // frames to advance after each prediction

    // MARK: - Main Entry Point

    func analyze(videoURL: URL) async -> [SessionEvent] {
        // TODO: Implement full pipeline when CoreML .mlmodel is available
        // Step 1: Extract frames via AVAssetReader
        // Step 2: Vision pose detection per frame (VNDetectHumanBodyPoseRequest)
        // Step 3: Buffer windowSize frames → run MLInferenceEngine → [WindowPrediction]
        // Step 4: Filter confidence ≤ 0.20 (undetected) and > 0.80 (correct)
        // Steps 5–8: Use helpers below — they are ready now
        return []
    }

    // MARK: - Step 5: Group consecutive same-label windows

    // Two predictions belong to the same group when they share the same label
    // AND the gap between them (prediction.startTime - last.endTime) is < 0.5s.
    // A new group starts when the label changes or the gap exceeds 0.5s.
    func groupWindows(_ predictions: [WindowPrediction]) -> [[WindowPrediction]] {
        var groups: [[WindowPrediction]] = []
        var current: [WindowPrediction] = []

        for prediction in predictions {
            if current.isEmpty {
                current.append(prediction)
            } else if let last = current.last,
                      last.label == prediction.label,
                      (prediction.startTime - last.endTime) < 0.5 {
                current.append(prediction)
            } else {
                groups.append(current)
                current = [prediction]
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // MARK: - Step 6: Select highest-confidence window per group

    func selectRepresentative(from group: [WindowPrediction]) -> WindowPrediction {
        group.max(by: { $0.confidence < $1.confidence })!
    }

    // MARK: - Step 7: Build SessionEvent from representative window

    // Confidence tiers (per SHADOWBOX_APP_REQUIREMENTS.md):
    //   ≤ 0.20  → filtered before reaching here (Step 4)
    //   0.21–0.50 → .wrong   (Red)
    //   0.51–0.80 → .unclear (Yellow)
    //   > 0.80  → .correct  (Green) — clipURL is nil, nothing to show
    func buildEvent(from window: WindowPrediction,
                    videoDuration: Double,
                    sessionURL: URL) -> SessionEvent {
        let isGreen = window.confidence > 0.80

        let status: SessionEvent.EventStatus
        if window.confidence > 0.80 {
            status = .correct
        } else if window.confidence <= 0.50 {
            status = .wrong
        } else {
            status = .unclear
        }

        return SessionEvent(
            id:         UUID().uuidString,
            time:       Int(window.startTime),
            move:       findMove(window.label) ?? allMoves[0],
            status:     status,
            confidence: Double(window.confidence),
            detectedAs: nil,
            note:       PerformanceFeedback.suggestion(for: window.label),
            clipURL:    isGreen ? nil : sessionURL
        )
    }

    // MARK: - Background clip extraction

    /// Trims a 3-second clip for each wrong/unclear event and updates SessionStore as each completes.
    /// Processes events serially to avoid AVAssetExportSession throttling.
    func extractClips(videoURL: URL, events: [SessionEvent]) async {
        let asset = AVAsset(url: videoURL)

        let videoDuration: Double
        do {
            let cmDuration = try await asset.load(.duration)
            videoDuration = CMTimeGetSeconds(cmDuration)
        } catch {
            return
        }

        for event in events where event.status != .correct {
            let startSec = max(0, Double(event.time) - 0.5)
            let endSec   = min(videoDuration, Double(event.time) + 2.5)
            guard endSec > startSec else { continue }

            let timeRange = CMTimeRange(
                start:    CMTime(seconds: startSec, preferredTimescale: 600),
                duration: CMTime(seconds: endSec - startSec, preferredTimescale: 600)
            )

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")

            guard let session = AVAssetExportSession(asset: asset,
                                                     presetName: AVAssetExportPresetPassthrough) else { continue }
            session.outputURL      = outputURL
            session.outputFileType = .mov
            session.timeRange      = timeRange

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { cont.resume() }
            }

            guard session.status == .completed else { continue }

            let eventId = event.id
            let clipURL = outputURL
            await MainActor.run {
                SessionStore.shared.updateClip(eventId: eventId, url: clipURL)
            }
        }
    }
}
