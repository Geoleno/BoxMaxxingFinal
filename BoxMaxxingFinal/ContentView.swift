import SwiftUI

enum AppRoute {
    case menu, record, results
}

struct ContentView: View {
    @State private var route: AppRoute = .results
    @State private var sessionState = SessionState()
    @StateObject private var sessionManager = SessionManager()

    var body: some View {
        ZStack {
            switch route {
            case .menu:
                MenuView(state: $sessionState, onStart: {
                    if let comboId = sessionState.selectedComboId,
                       let combo = allCombos.first(where: { $0.id == comboId }) {
                        sessionManager.configure(combo: combo)
                    }
                    withAnimation(.easeInOut(duration: 0.25)) { route = .record }
                }, onTestVideo: { _ in
                    let testState = SessionState(
                        selectedComboId: "c1",
                        selectedMoveIds: allMoves.map(\.id),
                        sessionLength: 2
                    )
                    sessionState = testState
                    let events = generateEvents(state: testState)
                    SessionStore.shared.save(events: events, startDate: Date(), duration: 120)
                    withAnimation(.easeInOut(duration: 0.25)) { route = .results }
                })
                .transition(.opacity)

            case .record:
                RecordingView(
                    state: sessionState,
                    onFinish: {
                        withAnimation(.easeInOut(duration: 0.25)) { route = .results }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.25)) { route = .menu }
                    }
                )
                .environmentObject(sessionManager)
                .transition(.opacity)

            case .results:
                ResultsView(
                    state: sessionState,
                    events: SessionStore.shared.currentEvents,
                    onBack: {
                        SessionRecorder.shared.deleteSessionFile()
                        SessionStore.shared.clear()
                        withAnimation(.easeInOut(duration: 0.25)) { route = .menu }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: route)
        .onAppear {
            // Startup cleanup: remove any session file left over from a previous app session
            SessionRecorder.shared.deleteSessionFile()
        }
    }
}

#Preview {
    ContentView()
}
