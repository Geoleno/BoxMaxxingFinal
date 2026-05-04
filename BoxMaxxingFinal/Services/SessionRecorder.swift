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

    private(set) var lastRecordedURL: URL?
    private var recordingContinuation: CheckedContinuation<URL, Error>?

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Recording Control

    func startRecording() {
        let filename = "session_\(Int(Date().timeIntervalSince1970)).mov"
        let outputURL = documentsDirectory.appendingPathComponent(filename)
        movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    // Suspends until AVFoundation calls the delegate, then returns the file URL.
    // Throws if the recording file failed to write (e.g. disk full).
    func stopRecording() async throws -> URL {
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
