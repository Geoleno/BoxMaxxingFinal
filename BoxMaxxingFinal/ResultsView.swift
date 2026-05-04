import SwiftUI

struct ResultsView: View {
    let state: SessionState
    let events: [SessionEvent]
    let onBack: () -> Void

    @State private var activeEvent: SessionEvent? = nil
    @State private var density: String = "compact"
    @State private var exportFeedback: String? = nil

    private var total: Int { state.sessionLength * 60 }
    private var wrongCount: Int  { events.filter { $0.status == .wrong }.count }
    private var unclearCount: Int { events.filter { $0.status == .unclear }.count }
    private var avgConf: Int {
        guard !events.isEmpty else { return 0 }
        let sum = events.reduce(0.0) { $0 + $1.confidence }
        return Int(sum / Double(events.count) * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            navBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Large title
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

                    // Stats
                    HStack(spacing: 8) {
                        StatCard(label: "Wrong",    value: "\(wrongCount)",  color: Color(UIColor.systemRed))
                        StatCard(label: "Unclear",  value: "\(unclearCount)", color: Color(UIColor.systemOrange))
                        StatCard(label: "Avg Conf", value: "\(avgConf)%",    color: Color(UIColor.label))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    // Timeline header
                    HStack {
                        Text("Timeline")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .tracking(-0.08)
                        Spacer()
                        HStack(spacing: 12) {
                            LegendDot(color: Color(UIColor.systemRed),    label: "Wrong")
                            LegendDot(color: Color(UIColor.systemOrange), label: "Unclear")
                        }
                        .font(.system(size: 13))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)

                    // Timeline
                    TimelineView(
                        events: events,
                        total: total,
                        density: density,
                        onOpenEvent: { activeEvent = $0 }
                    )
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 30)
            }
        }
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .sheet(item: $activeEvent) { event in
            DetailSheetView(event: event)
                .presentationDetents([.large])
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

            Button(action: exportResults) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(Color(UIColor.systemRed))
            }
            .padding(8)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        
    }

    private func exportResults() {
        // ResultExporter requires a UIScrollView reference.
        // Full scrollable export is triggered via UIHostingController snapshot.
        // TODO: Pass UIScrollView reference from the SwiftUI ScrollView wrapper
        // For now, show a placeholder overlay
        exportFeedback = "Export coming soon — requires UIScrollView bridge"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exportFeedback = nil }
    }
}

// MARK: - Timeline

private struct TimelineView: View {
    let events: [SessionEvent]
    let total: Int
    let density: String
    let onOpenEvent: (SessionEvent) -> Void

    private var rowSpacing: CGFloat { density == "compact" ? 12 : 22 }
    // Dot center x = 14 (dot left=7, width=14). Spine left=13, width=2, center=14. ✓
    private let dotCenter: CGFloat = 14
    private let dotSize: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Spine — center aligns with dot centers
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(width: 2)
                .padding(.leading, dotCenter - 1)
                .padding(.top, dotSize / 2)
                .padding(.bottom, dotSize / 2)

            VStack(alignment: .leading, spacing: 0) {
                endpointRow(time: "00:00", label: "Start")

                ForEach(events) { event in
                    eventRow(event)
                        .padding(.top, rowSpacing)
                        .padding(.bottom, rowSpacing)
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

    private func eventRow(_ event: SessionEvent) -> some View {
        let accent: Color
        let statusLabel: String
        switch event.status {
        case .correct:
            accent = Color(UIColor.systemGreen)
            statusLabel = "Excellent"
        case .wrong:
            accent = Color(UIColor.systemRed)
            statusLabel = "Wrong move"
        case .unclear:
            accent = Color(UIColor.systemOrange)
            statusLabel = "Needs review"
        }

        return HStack(spacing: 7) {
            Circle()
                .stroke(accent, lineWidth: 3)
                .frame(width: dotSize, height: dotSize)
                .background(Circle().fill(Color(UIColor.systemBackground)))
                .padding(.leading, dotCenter - dotSize / 2)

            Button(action: { onOpenEvent(event) }) {
                HStack(spacing: 12) {
                    MoveGlyphView(kind: event.move.kind, side: event.move.side,
                                  color: Color(UIColor.label), size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.move.name)
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.32)
                            .foregroundColor(Color(UIColor.label))
                        HStack(spacing: 0) {
                            Text(statusLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(accent)
                            Text(" · \(Int(event.confidence * 100))% confidence")
                                .font(.system(size: 13))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }
                        .tracking(-0.08)
                    }
                    Spacer(minLength: 0)
                    Text(formatTime(event.time))
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
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .tracking(-0.08)
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
    let event: SessionEvent
    @Environment(\.dismiss) private var dismiss
    private var accent: Color {
        switch event.status {
        case .correct: return Color(UIColor.systemGreen)
        case .wrong:   return Color(UIColor.systemRed)
        case .unclear: return Color(UIColor.systemOrange)
        }
    }

    private var statusLabel: String {
        switch event.status {
        case .correct: return "Excellent"
        case .wrong:   return "Wrong move"
        case .unclear: return "Needs review"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Sheet nav row
                HStack {
                    Text(formatTime(event.time))
                        .font(.system(size: 15, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .tracking(-0.08)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(UIColor.label))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
//                        .background(Capsule().fill(Color(UIColor.systemFill)))
//                        .buttonStyle(.glass)
                        .buttonStyle(.glassProminent)
                        .tint(.gray.opacity(0.3))
                }
                .padding(.top, 24)
                .padding(.bottom, 12)

                // Status pill
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.08)
                }
                .foregroundColor(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.14)))
                .padding(.bottom, 8)

                Text(event.move.name)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(0.34)
                    .padding(.bottom, 4)

                Group {
                    Text("\(Int(event.confidence * 100))% confidence\(event.detectedAs != nil ? " · Detected as \(event.detectedAs!)" : "")")
                }
                .font(.system(size: 15))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .tracking(-0.24)

                // Confidence bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(UIColor.secondarySystemFill))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accent)
                            .frame(width: geo.size.width * CGFloat(event.confidence))
                    }
                }
                .frame(height: 8)
                .padding(.top, 16)
                .padding(.bottom, 22)

                if event.status == .correct {
                    // GREEN — no clip (was discarded); show encouragement only
                    Text("No clip — movement was rated Excellent ✅")
                        .font(.system(size: 15))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .italic()
                        .padding(.bottom, 22)
                } else {
                    // YELLOW / RED / NO SCAN / NO MOVEMENT — show user clip
                    SectionLabel("Your clip")
                    if let clipURL = event.clipURL {
                        VideoPlayerView(url: clipURL, startSeconds: event.time)
                            .aspectRatio(16/10, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.bottom, 22)
                    } else {
                        Text("Clip not available")
                            .font(.system(size: 15))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .italic()
                            .padding(.bottom, 22)
                    }
                }

                // Suggestion — from PerformanceFeedback, stored in event.note
                SectionLabel("Suggestion")
                Text(event.note)
                    .font(.system(size: 15))
                    .foregroundColor(Color(UIColor.label))
                    .tracking(-0.24)
                    .lineSpacing(4)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 22)

                // Correct form reference video — PLACEHOLDER
                // TODO: Replace with AVPlayer using correct movement video for event.move.id
                SectionLabel("Correct form")
                VideoPanel(label: "Reference · loop", playing: .constant(true), annotated: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

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

private struct VideoPanel: View {
    let label: String
    @Binding var playing: Bool
    let annotated: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Dark gradient background
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.11, blue: 0.10),
                                 Color(red: 0.03, green: 0.03, blue: 0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Silhouette
            Canvas { context, size in
                let sx = size.width / 400
                let sy = size.height / 250
                context.concatenate(CGAffineTransform(scaleX: sx, y: sy))
                context.opacity = 0.45

                let s = StrokeStyle(lineWidth: 0)
                let c = Color(red: 0.04, green: 0.03, blue: 0.03)
                let head = Path(ellipseIn: CGRect(x: 178, y: 58, width: 44, height: 44))
                context.fill(head, with: .color(c))
                var torso = Path()
                torso.move(to: .init(x: 170, y: 100)); torso.addQuadCurve(to: .init(x: 230, y: 100), control: .init(x: 200, y: 92))
                torso.addLine(to: .init(x: 240, y: 180)); torso.addQuadCurve(to: .init(x: 234, y: 250), control: .init(x: 240, y: 220))
                torso.addLine(to: .init(x: 166, y: 250)); torso.addQuadCurve(to: .init(x: 160, y: 180), control: .init(x: 160, y: 220))
                context.fill(torso, with: .color(c))
                _ = s
                var leftArm = Path()
                leftArm.move(to: .init(x: 167, y: 110)); leftArm.addQuadCurve(to: .init(x: 145, y: 180), control: .init(x: 140, y: 140))
                leftArm.addLine(to: .init(x: 165, y: 188)); leftArm.addQuadCurve(to: .init(x: 175, y: 115), control: .init(x: 172, y: 150))
                context.fill(leftArm, with: .color(c))
                var rightArm = Path()
                rightArm.move(to: .init(x: 233, y: 110)); rightArm.addQuadCurve(to: .init(x: 255, y: 180), control: .init(x: 260, y: 140))
                rightArm.addLine(to: .init(x: 235, y: 188)); rightArm.addQuadCurve(to: .init(x: 225, y: 115), control: .init(x: 228, y: 150))
                context.fill(rightArm, with: .color(c))
            }

            if annotated {
                Canvas { context, size in
                    let sx = size.width / 400
                    let sy = size.height / 250
                    context.concatenate(CGAffineTransform(scaleX: sx, y: sy))
                    let green = Color(UIColor.systemGreen)
                    var line = Path()
                    line.move(to: .init(x: 165, y: 130)); line.addLine(to: .init(x: 300, y: 110))
                    context.stroke(line, with: .color(green),
                                   style: StrokeStyle(lineWidth: 1.5 / min(sx, sy), dash: [4, 4]))
                    let ring = Path(ellipseIn: CGRect(x: 294, y: 104, width: 12, height: 12))
                    context.stroke(ring, with: .color(green),
                                   style: StrokeStyle(lineWidth: 1.5 / min(sx, sy)))
                    let dot = Path(ellipseIn: CGRect(x: 161, y: 126, width: 8, height: 8))
                    context.fill(dot, with: .color(green))
                }
                Text("Extend")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(UIColor.systemGreen))
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if !playing {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 56, height: 56)
                        .shadow(radius: 10, y: 4)
                    Triangle()
                        .fill(Color.black)
                        .frame(width: 18, height: 22)
                        .offset(x: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Label pill
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .tracking(-0.08)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
        .aspectRatio(16/10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture { playing.toggle() }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: .init(x: rect.minX, y: rect.minY))
            p.addLine(to: .init(x: rect.maxX, y: rect.midY))
            p.addLine(to: .init(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

#Preview {
    ContentView()
}
