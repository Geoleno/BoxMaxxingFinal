import SwiftUI
import AVFoundation

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        view.onFrame = onFrame
        return view
    }
    func updateUIView(_ uiView: CameraView, context: Context) {
        uiView.onFrame = onFrame
    }
}

final class CameraView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let frameQueue = DispatchQueue(label: "shadowbox.camera.frames", qos: .userInteractive)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.1, green: 0.09, blue: 0.085, alpha: 1)
        setupCamera()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    private func setupCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.startSession() }
        }
    }

    private func startSession() {
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.addInput(input)

        // Video output for ML inference (live punch chips in HUD)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Rotate pixel buffers to portrait so Vision receives portrait-space coordinates.
        // Without this, the sensor delivers landscape buffers and joint x/y axes are swapped.
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        // Movie file output for full-session recording (added once, used by SessionRecorder)
        let movieOutput = SessionRecorder.shared.movieFileOutput
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = sampleBuffer.presentationTimeStamp
        onFrame?(pixelBuffer, pts)
    }

    deinit {
        if session.isRunning { session.stopRunning() }
    }
}
