import AVFoundation
import Foundation

final class SessionRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {

    static let shared = SessionRecorder()
    private override init() {}

    // Added to CameraView's AVCaptureSession in RecordingView.swift
    let movieFileOutput = AVCaptureMovieFileOutput()

    // Set to a bundle URL to skip live recording and test the analysis pipeline directly.
    // Set to nil for production.
    var debugVideoOverride: URL? = nil

    // Set to true to allow app to continue even if camera is unavailable
    var allowRecordingWithoutCamera = false

    private(set) var lastRecordedURL: URL?
    private var recordingContinuation: CheckedContinuation<URL, Error>?
    private var isRecordingActive = false

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Recording Control

    func startRecording() {
        let filename = "session_\(Int(Date().timeIntervalSince1970)).mov"
        let outputURL = documentsDirectory.appendingPathComponent(filename)

        let hasActiveConnections = movieFileOutput.connections.contains { $0.isActive && $0.isEnabled }

        if hasActiveConnections {
            movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
            isRecordingActive = true
        } else if allowRecordingWithoutCamera {
            // Camera unavailable but override is enabled — skip actual recording
            isRecordingActive = false
            lastRecordedURL = outputURL
        }
    }

    // Suspends until AVFoundation calls the delegate, then returns the file URL.
    // Throws if the recording file failed to write (e.g. disk full).
    func stopRecording() async throws -> URL {
        // If recording was never actually started (camera unavailable), return the stub URL
        if !isRecordingActive, let url = lastRecordedURL {
            return url
        }

        return try await withCheckedThrowingContinuation { continuation in
            recordingContinuation = continuation
            movieFileOutput.stopRecording()
        }
    }

    // MARK: - Cleanup

    func deleteSessionFile() {
        guard let url = lastRecordedURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordedURL = nil
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error = error {
            recordingContinuation?.resume(throwing: error)
        } else {
            lastRecordedURL = outputFileURL
            recordingContinuation?.resume(returning: outputFileURL)
        }
        recordingContinuation = nil
    }
}
