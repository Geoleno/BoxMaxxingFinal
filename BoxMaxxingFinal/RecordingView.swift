import SwiftUI
import AVFoundation

// MARK: - Recording Phase

enum RecordingPhase: Equatable {
    case hint, countdown, recording, done
}

// MARK: - Recording View

struct RecordingView: View {
    let state: SessionState
    let onFinish: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var sessionManager: SessionManager

    @State private var phase: RecordingPhase = .hint
    @State private var countdownValue: Int = 3
    @State private var countdownTimer: Timer?

    private var total: Int { state.sessionLength * 60 }
    private var progress: Double { Double(sessionManager.elapsedSeconds) / Double(total) }

    var body: some View {
        ZStack {
            CameraPreviewView(onFrame: { [sessionManager] buffer in
                sessionManager.processFrame(buffer)
            })
            .ignoresSafeArea()

            if phase == .recording {
                SkeletonOverlayView(
                    skeleton: sessionManager.currentSkeleton,
                    bufferSize: sessionManager.videoBufferSize
                )
                .ignoresSafeArea()
            }

            // Vignette overlay
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.15), location: 0.3),
                    .init(color: .black.opacity(0.15), location: 0.7),
                    .init(color: .black.opacity(0.7),  location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            switch phase {
            case .hint:
                SetupHintOverlay(
                    onContinue: { phase = .countdown; startCountdown() },
                    onCancel: onCancel
                )
            case .countdown:
                CountdownOverlay(value: countdownValue)
            case .recording:
                RecordingHUD(
                    elapsed: sessionManager.elapsedSeconds,
                    total: total,
                    progress: progress,
                    livePunches: sessionManager.livePunches,
                    currentTargetMove: sessionManager.currentTargetMove,
                    lastWindowResult: sessionManager.lastWindowResult,
                    onStop: { sessionManager.requestStop() },
                    onCancel: onCancel
                )
            case .done:
                ReviewingOverlay()
            }
        }
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
        .onDisappear { cleanup() }
        // Switch to ReviewingOverlay as soon as recording stops
        .onChange(of: sessionManager.isRecording) { _, newValue in
            if !newValue && phase == .recording {
                phase = .done
            }
        }
        // Navigate to Results only once PostSessionAnalyzer finishes (may take 5–15s)
        .onChange(of: sessionManager.isAnalyzing) { _, analyzing in
            if !analyzing && phase == .done {
                onFinish()
            }
        }
        // Stop confirmation dialog — timer keeps running in background while open
        .alert("Stop Session?", isPresented: $sessionManager.showStopConfirmation) {
            Button("Stop", role: .destructive) { sessionManager.confirmStop() }
            Button("Continue", role: .cancel) { sessionManager.cancelStop() }
        } message: {
            Text("Your current progress will be saved and taken to the results page.")
        }
    }

    // MARK: - Timer Control

    private func startCountdown() {
        countdownValue = 3
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { t in
            if countdownValue > 0 {
                countdownValue -= 1
            } else {
                t.invalidate()
                countdownTimer = nil
                phase = .recording
                startRecording()
            }
        }
    }

    private func startRecording() {
        sessionManager.startSession()
    }

    private func cleanup() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    var onFrame: ((CVPixelBuffer) -> Void)?

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
    var onFrame: ((CVPixelBuffer) -> Void)?

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
        onFrame?(pixelBuffer)
    }

    deinit {
        if session.isRunning { session.stopRunning() }
    }
}

// MARK: - Setup Hint Overlay

private struct SetupHintOverlay: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .blur(radius: 8)

            VStack(alignment: .leading, spacing: 0) {
                // Grabber
                HStack { Spacer()
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 36, height: 5)
                    Spacer()
                }
                .padding(.bottom, 14)

                Text("Set up your camera")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(0.35)
                    .padding(.bottom, 4)

                Text("For best detection, follow these tips before starting.")
                    .font(.system(size: 15))
                    .foregroundColor(Color.white.opacity(0.65))
                    .tracking(-0.24)
                    .lineSpacing(4)
                    .padding(.bottom, 18)

                HintRow(icon: "arrow.left.and.right", title: "Stand 2–3 m away",
                        sub: "Your full body should fit in the frame.", last: false)
                HintRow(icon: "rotate.3d", title: "Angle ~30° to the side",
                        sub: "Face the camera at a slight angle so both arms are visible.", last: false)
                HintRow(icon: "sun.max", title: "Even, front-facing light",
                        sub: "Avoid backlight — shadows reduce detection accuracy.", last: true)

                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .medium))
                            .tracking(-0.4)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.15)))
                    }
                    Button(action: onContinue) {
                        Text("I'm Ready")
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(UIColor.systemRed)))
                    }
                }
                .padding(.top, 18)
            }
            .foregroundColor(.white)
            .padding(20)
            .padding(.bottom, 4)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(UIColor.systemBackground).opacity(0.15))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .ignoresSafeArea()
    }
}

private struct HintRow: View {
    let icon: String
    let title: String
    let sub: String
    let last: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(UIColor.systemRed))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.systemRed).opacity(0.2)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.32)
                    Text(sub)
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.6))
                        .tracking(-0.15)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, last ? 0 : 14)

            if !last {
                Divider().background(Color.white.opacity(0.15)).padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Countdown Overlay

private struct CountdownOverlay: View {
    let value: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("Get ready")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .tracking(-0.4)

            Text(value == 0 ? "Go" : "\(value)")
                .font(.system(size: 160, weight: .bold, design: .default))
                .monospacedDigit()
                .foregroundColor(.white)
                .tracking(-8)
                .frame(minWidth: 200)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: value)
        }
    }
}

// MARK: - Recording HUD

private struct RecordingHUD: View {
    let elapsed: Int
    let total: Int
    let progress: Double
    let livePunches: [LivePunch]
    let currentTargetMove: Move?
    let lastWindowResult: WindowResult?
    let onStop: () -> Void
    let onCancel: () -> Void

    @State private var recPulse = false

    var body: some View {
        VStack {
            // Top bar
            HStack {
                Button(action: onCancel) {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.4))
                            .frame(width: 32, height: 32)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .background(.ultraThinMaterial.opacity(0), in: Circle())

                Spacer()

                // REC indicator
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(UIColor.systemRed))
                        .frame(width: 8, height: 8)
                        .opacity(recPulse ? 0.5 : 1.0)
                        .scaleEffect(recPulse ? 0.85 : 1.0)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: recPulse)
                    Text(formatTime(elapsed))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .tracking(-0.24)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)

            Spacer()

            // Live detection chips
            VStack(spacing: 6) {
                ForEach(Array(livePunches.prefix(2).enumerated()), id: \.element.id) { idx, punch in
                    LivePunchChip(punch: punch, faded: idx > 0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .animation(.easeOut(duration: 0.3), value: livePunches.map(\.id))
            .padding(.bottom, 10)

            // Current combo target card
            CurrentMoveCard(targetMove: currentTargetMove, result: lastWindowResult)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.18))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(UIColor.systemRed))
                        .frame(width: geo.size.width * CGFloat(progress))
                        .animation(.linear(duration: 1.0), value: progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 16)

            // Stop button
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 64, height: 64)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(UIColor.systemRed))
                        .frame(width: 26, height: 26)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .onAppear { recPulse = true }
    }
}

private struct LivePunchChip: View {
    let punch: LivePunch
    let faded: Bool

    private var accentColor: Color {
        if punch.confidence > 0.85 { return Color(UIColor.systemGreen) }
        if punch.confidence > 0.7  { return Color(UIColor.systemOrange) }
        return Color(UIColor.systemBlue)
    }

    var body: some View {
        HStack(spacing: 10) {
            MoveGlyphView(kind: punch.move.kind, side: punch.move.side, color: .white, size: 20)
            Text(punch.move.name)
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.24)
                .foregroundColor(.white)
            Spacer()
            Text("\(Int(punch.confidence * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .tracking(-0.08)
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(faded ? 0.6 : 1.0)
    }
}

private struct CurrentMoveCard: View {
    let targetMove: Move?
    let result: WindowResult?

    var body: some View {
        Group {
            if let result {
                HStack(spacing: 10) {
                    Image(systemName: result.matched ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.matched ? Color(UIColor.systemGreen) : Color(UIColor.systemRed))
                        .font(.system(size: 18, weight: .semibold))
                    Text(result.matched ? "Nice!" : "Missed")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(result.confidence * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(result.matched
                              ? Color(UIColor.systemGreen).opacity(0.25)
                              : Color(UIColor.systemRed).opacity(0.20))
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if let move = targetMove {
                HStack(spacing: 10) {
                    MoveGlyphView(kind: move.kind, side: move.side, color: .white, size: 18)
                    Text(move.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text("NOW")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .animation(.easeOut(duration: 0.3), value: result?.matched)
        .animation(.easeOut(duration: 0.3), value: targetMove?.id)
    }
}

// MARK: - Reviewing Overlay

private struct ReviewingOverlay: View {
    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .blur(radius: 20)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 32, height: 32)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                }

                Text("Reviewing your tape…")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)

                Text("Analyzing form and detection")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(-0.24)
            }
        }
        .onAppear { spin = true }
    }
}
