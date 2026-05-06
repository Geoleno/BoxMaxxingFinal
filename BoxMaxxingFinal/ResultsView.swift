import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import Combine

struct ResultsView: View {
    let state: SessionState
    let wrongMovements: [WrongMovement]
    let videoURL: URL?
    let onBack: () -> Void

    @State private var activeMovement: WrongMovement? = nil

    private var total: Int { state.sessionLength * 60 }
    private var wrongTechniqueCount: Int { wrongMovements.filter { $0.isWrongTechnique }.count }
    private var badExecutionCount: Int   { wrongMovements.filter { !$0.isWrongTechnique }.count }
    private var avgConf: Int {
        guard !wrongMovements.isEmpty else { return 0 }
        let sum = wrongMovements.reduce(0.0) { $0 + Double($1.confidence) }
        return Int(sum / Double(wrongMovements.count) * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Review")
                            .font(.system(size: 34, weight: .bold))
                            .tracking(0.37)
                        Text("\(formatTime(total)) · \(state.selectedMoveIds.count) moves")
                            .font(.system(size: 15, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .tracking(-0.24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    HStack(spacing: 8) {
                        StatCard(label: "Wrong Technique", value: "\(wrongTechniqueCount)", color: Color(UIColor.systemRed))
                        StatCard(label: "Bad Execution",  value: "\(badExecutionCount)",   color: Color(UIColor.systemYellow))
                        StatCard(label: "Score",      value: "\(avgConf)%",          color: Color(UIColor.label))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    HStack {
                        Text("Timeline")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .tracking(-0.08)
                        Spacer()
                        HStack(spacing: 12) {
                            LegendDot(color: Color(UIColor.systemRed),    label: "Wrong technique")
                            LegendDot(color: Color(UIColor.systemYellow), label: "Bad execution")
                        }
                        .font(.system(size: 13))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)

                    WrongMovementTimelineView(
                        movements: wrongMovements,
                        total: total,
                        onOpenMovement: { activeMovement = $0 }
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 30)
            }
        }
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .sheet(item: $activeMovement) { movement in
            DetailSheetView(movement: movement, videoURL: videoURL)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var navBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Menu")
                        .font(.system(size: 17, weight: .regular))
                        .tracking(-0.4)
                }
                .foregroundColor(Color(UIColor.systemRed))
            }
            .padding(8)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(minHeight: 44)
    }
}

// MARK: - Timeline

private struct WrongMovementTimelineView: View {
    let movements: [WrongMovement]
    let total: Int
    let onOpenMovement: (WrongMovement) -> Void

    private let dotCenter: CGFloat = 14
    private let dotSize: CGFloat   = 14
    private let rowSpacing: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(width: 2)
                .padding(.leading, dotCenter - 1)
                .padding(.top, dotSize / 2)
                .padding(.bottom, dotSize / 2)

            VStack(alignment: .leading, spacing: 0) {
                endpointRow(time: "00:00", label: "Start")

                ForEach(movements) { movement in
                    movementRow(movement)
                        .padding(.vertical, rowSpacing)
                }

                endpointRow(time: formatTime(total), label: "End")
                    .padding(.top, 4)
            }
        }
    }

    private func endpointRow(time: String, label: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .stroke(Color(UIColor.tertiaryLabel), lineWidth: 2)
                .frame(width: dotSize, height: dotSize)
                .background(Circle().fill(Color(UIColor.systemBackground)))
                .padding(.leading, dotCenter - dotSize / 2)
            HStack(spacing: 0) {
                Text(time)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .tracking(-0.08)
                Text(" · \(label)")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.08)
            }
            .foregroundColor(Color(UIColor.secondaryLabel))
        }
    }

    private func movementRow(_ movement: WrongMovement) -> some View {
        let accent: Color = movement.isWrongTechnique ? Color(UIColor.systemRed) : Color(UIColor.systemYellow)
        let statusLabel   = movement.isWrongTechnique ? "Wrong technique" : "Bad execution"
        let secs          = Int(CMTimeGetSeconds(movement.timestamp))

        return HStack(spacing: 7) {
            Circle()
                .stroke(accent, lineWidth: 3)
                .frame(width: dotSize, height: dotSize)
                .background(Circle().fill(Color(UIColor.systemBackground)))
                .padding(.leading, dotCenter - dotSize / 2)

            Button(action: { onOpenMovement(movement) }) {
                HStack(spacing: 12) {
                    MoveGlyphView(kind: movement.expectedMove.kind,
                                  side: movement.expectedMove.side,
                                  color: Color(UIColor.label), size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movement.expectedMove.name)
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.32)
                            .foregroundColor(Color(UIColor.label))
                        HStack(spacing: 0) {
                            Text(statusLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(accent)
                            Text(" · \(Int(movement.confidence * 100))%")
                                .font(.system(size: 13))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }
                        .tracking(-0.08)
                    }
                    Spacer(minLength: 0)
                    Text(formatTime(secs))
                        .font(.system(size: 15, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .tracking(-0.08)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .tracking(-0.08)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
                .foregroundColor(color)
                .tracking(0.34)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Legend Dot

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}

// MARK: - Detail Sheet

struct DetailSheetView: View {
    let movement: WrongMovement
    let videoURL: URL?
    @StateObject private var clipHolder    = PlayerHolder()
    @StateObject private var exampleHolder = PlayerHolder()

    // Example videos — add these files to Xcode (drag into project, check "Add to target").
    // Files live in BoxMaxxingFinal/Video/ on disk; Xcode copies them into the bundle.
    private var exampleVideoURL: URL? {
        let name: String
        switch movement.expectedMove.id {
        case "lj": name = "Result_Jab_Video"
        case "rj": name = "Result_Straight_Video"
        default:   return nil
        }
        return Bundle.main.url(forResource: name, withExtension: "mp4")
    }

    private var accent: Color {
        Color.performanceColor(for: movement.confidence)
    }

    private var statusLabel: String {
        movement.isWrongTechnique ? "Wrong technique" : Color.performanceLabel(for: movement.confidence)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                VStack(spacing: 2) {
                    Text("Movement Detail")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(UIColor.label))
                    Text("at \(formatTime(Int(CMTimeGetSeconds(movement.timestamp))))")
                        .font(.system(size: 13, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 20)

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(accent.opacity(0.12))
                            .frame(width: 64, height: 64)
                        MoveGlyphView(kind: movement.expectedMove.kind,
                                      side: movement.expectedMove.side,
                                      color: accent, size: 34)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(movement.expectedMove.name)
                            .font(.system(size: 24, weight: .bold))
                            .tracking(0.2)
                        HStack(spacing: 6) {
                            moveBadge(movement.expectedMove.side == .left ? "Left" : "Right")
                            moveBadge(kindLabel(movement.expectedMove.kind))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(accent).frame(width: 8, height: 8)
                            Text(statusLabel)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(accent)
                        }
                        Spacer()
                        Text("\(Int(movement.confidence * 100))% confidence")
                            .font(.system(size: 15, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(UIColor.secondarySystemFill))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(accent)
                                .frame(width: geo.size.width * CGFloat(movement.confidence))
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text("0%"); Spacer(); Text("50%"); Spacer(); Text("100%")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 16)

                if movement.isWrongTechnique,
                   let detectedName = findMove(movement.detectedMoveId)?.name {
                    detectionMismatchBlock(expected: movement.expectedMove.name, detected: detectedName)
                        .padding(.bottom, 16)
                }

                let clipSource = movement.clipURL ?? videoURL
                if let url = clipSource {
                    SectionLabel("Your clip")
                    VideoPlayer(player: clipHolder.player)
                        .aspectRatio(clipHolder.aspectRatio, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 20)
                        .onAppear {
                            // Dedicated clip: play from start. Session video: seek to timestamp.
                            let seekTo = movement.clipURL != nil ? .zero : movement.timestamp
                            clipHolder.load(url: url, seekTo: seekTo)
                        }
                }

                if let url = exampleVideoURL {
                    SectionLabel("Good example")
                    VideoPlayer(player: exampleHolder.player)
                        .aspectRatio(exampleHolder.aspectRatio, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 20)
                        .onAppear {
                            exampleHolder.load(url: url, seekTo: .zero)
                        }
                }

                SectionLabel("Coach note")
                Text(PerformanceFeedback.suggestion(for: movement.expectedMove.id))
                    .font(.system(size: 15))
                    .foregroundColor(Color(UIColor.label))
                    .tracking(-0.24)
                    .lineSpacing(4)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 20)

                SectionLabel("Form checklist")
                formChecklist(for: movement.expectedMove.kind)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .onDisappear {
            clipHolder.player.pause()
            exampleHolder.player.pause()
        }
    }

    private func moveBadge(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(Color(UIColor.secondaryLabel))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(UIColor.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func detectionMismatchBlock(expected: String, detected: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detection mismatch")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expected").font(.system(size: 11)).foregroundColor(Color(UIColor.tertiaryLabel))
                    Text(expected).font(.system(size: 15, weight: .semibold)).foregroundColor(Color(UIColor.label))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected as").font(.system(size: 11)).foregroundColor(Color(UIColor.tertiaryLabel))
                    Text(detected).font(.system(size: 15, weight: .semibold)).foregroundColor(Color(UIColor.systemRed))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(UIColor.systemRed).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func formChecklist(for kind: Move.MoveKind) -> some View {
        let cues = formCues(for: kind)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(cues.enumerated()), id: \.offset) { i, cue in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(accent)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cue.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(UIColor.label))
                        Text(cue.detail)
                            .font(.system(size: 13))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                if i < cues.count - 1 {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func kindLabel(_ kind: Move.MoveKind) -> String {
        switch kind {
        case .jab: return "Jab"
        case .hook: return "Hook"
        case .uppercut: return "Uppercut"
        }
    }

    private struct FormCue { let title: String; let detail: String }

    private func formCues(for kind: Move.MoveKind) -> [FormCue] {
        switch kind {
        case .jab:
            return [
                FormCue(title: "Full extension",  detail: "Extend your arm completely and snap the wrist on impact — a half-extended jab loses both speed and power."),
                FormCue(title: "Chin down",        detail: "Keep your chin tucked behind your lead shoulder throughout the punch to protect your jaw."),
                FormCue(title: "Quick retraction", detail: "Pull the fist back along the exact same line it traveled out — this resets your guard and sets up the next punch."),
            ]
        case .hook:
            return [
                FormCue(title: "Pivot the lead foot", detail: "Rotate on the ball of your foot as you throw — hip rotation is the main power source for the hook."),
                FormCue(title: "Elbow parallel",      detail: "Keep the elbow at shoulder height and parallel to the floor. High or low elbows telegraph the punch and reduce power."),
                FormCue(title: "Rear hand stays up",  detail: "Keep the rear glove high on your cheek while the lead arm swings — don't leave your head exposed."),
            ]
        case .uppercut:
            return [
                FormCue(title: "Dip the shoulder first", detail: "Lower your same-side shoulder slightly before driving up — this loads the punch and hides the tell."),
                FormCue(title: "Drive with the legs",    detail: "Push through the floor and extend the knees. Power comes from the ground up, not from the arm alone."),
                FormCue(title: "Tight elbow path",       detail: "Keep the elbow close to your body as the fist rises — a wide elbow wastes energy and exposes your ribs."),
            ]
        }
    }
}

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

// MARK: - Helpers

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(Color(UIColor.secondaryLabel))
            .tracking(-0.08)
            .padding(.bottom, 8)
    }
}

#Preview {
    ContentView()
}
