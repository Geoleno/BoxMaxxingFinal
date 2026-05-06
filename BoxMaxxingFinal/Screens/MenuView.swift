import SwiftUI

struct MenuView: View {
    @Binding var state: SessionState
    let onStart: () -> Void
    var onTestVideo: ((URL) -> Void)? = nil

    var body: some View {

        VStack(spacing: 0) {
            titleSection
            comboSection
            movesSection
            startButton
        }
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea()
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Pick Your Combo!")
                .font(.system(size: 30, weight: .bold))
                .tracking(0.5)
                .foregroundColor(Color(UIColor.systemRed))
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .bold()
                    .foregroundColor(Color(UIColor.label))
                Text("Session duration is 2 minutes")
                    .font(.system(size: 13))
                    .bold()
                    .foregroundColor(Color(UIColor.label))
                    .tracking(-0.08)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 10)
    }

    // MARK: - Combo List

    private var comboSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Suggested Combos")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .tracking(-0.08)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(allCombos.enumerated()), id: \.element.id) { index, combo in
                    ComboRow(
                        combo: combo,
                        isActive: state.selectedComboId == combo.id,
                        showSeparator: index > 0
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if state.selectedComboId == combo.id {
                                state.selectedComboId = nil
                                state.selectedMoveIds = []
                            } else {
                                state.selectedComboId = combo.id
                                state.selectedMoveIds = combo.moveIds
                            }
                        }
                    }
                }
            }
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)

        }
        .padding(.top, 6)
    }

    // MARK: - Move Grid

    private var movesSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Moves")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .tracking(-0.08)
                Spacer()
                if !state.selectedMoveIds.isEmpty {
                    Text("\(state.selectedMoveIds.count) in combo")
                        .font(.system(size: 12))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .tracking(-0.08)
                }
            }
            .padding(.horizontal, 20)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 2),
                spacing: 10
            ) {
                ForEach(allMoves) { move in
                    MoveCard(move: move, selectedMoveIds: state.selectedMoveIds)
                }.frame(height: 86)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 10)
    }

    // MARK: - Start CTA

    private var startButton: some View {
        let enabled = state.selectedComboId != nil
        return VStack(spacing: 12) {
            Button(action: onStart) {
                Text("Start Session")
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundColor(enabled ? .white : Color(UIColor.tertiaryLabel))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(enabled
                                  ? Color(UIColor.systemRed)
                                  : Color(UIColor.secondarySystemFill))
                    )
            }
            .disabled(!enabled)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 25)
    }
}

// MARK: - Combo Row

private struct ComboRow: View {
    let combo: Combo
    let isActive: Bool
    let showSeparator: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(combo.name)
                    .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? Color(UIColor.systemRed) : Color(UIColor.label))
                    .tracking(-0.3)

                // Sequence badges
                HStack(spacing: 4) {
                    ForEach(Array(combo.moveIds.enumerated()), id: \.offset) { idx, moveId in
                        if idx > 0 {
                            Text("›")
                                .font(.system(size: 11))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                        HStack(spacing: 3) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle()
                                        .fill(isActive ? Color(UIColor.systemRed) : Color(UIColor.tertiaryLabel))
                                )
                            if let move = findMove(moveId) {
                                Text(move.short)
                                    .font(.system(size: 13, weight: isActive ? .medium : .regular, design: .monospaced))
                                    .foregroundColor(isActive ? Color(UIColor.label) : Color(UIColor.secondaryLabel))
                                    .tracking(0.1)
                            }
                        }
                    }
                }
            }
            Spacer()

            // Radio indicator
            ZStack {
                Circle()
                    .stroke(isActive ? Color(UIColor.systemRed) : Color(UIColor.tertiaryLabel), lineWidth: 2)
                    .frame(width: 20, height: 20)
                if isActive {
                    Circle()
                        .fill(Color(UIColor.systemRed))
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(isActive ? Color(UIColor.systemRed).opacity(0.07) : Color.clear)
        .overlay(alignment: .top) {
            if showSeparator {
                Color(UIColor.separator).frame(height: 0.5)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

// MARK: - Move Card

private struct MoveCard: View {
    let move: Move
    let selectedMoveIds: [String]

    private var sequenceNumbers: [Int] {
        selectedMoveIds.enumerated().compactMap { idx, id in id == move.id ? idx + 1 : nil }
    }
    private var inCombo: Bool { !sequenceNumbers.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                MoveGlyphView(
                    kind: move.kind,
                    side: move.side,
                    color: inCombo ? Color(UIColor.systemRed) : Color(UIColor.tertiaryLabel),
                    size: 24
                )
                Spacer()
                if inCombo {
                    HStack(spacing: 3) {
                        ForEach(sequenceNumbers, id: \.self) { n in
                            Text("\(n)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Color(UIColor.systemRed)))
                        }
                    }
                }
            }
            Spacer()
            Text(move.name)
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.2)
                .foregroundColor(inCombo ? Color(UIColor.label) : Color(UIColor.secondaryLabel))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(inCombo ? Color(UIColor.systemRed).opacity(0.12) : Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(inCombo ? Color(UIColor.systemRed) : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: inCombo)
    }
}
#Preview {
    ContentView()
}
