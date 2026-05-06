import SwiftUI

enum AppRoute {
    case menu, record, results
}

struct ContentView: View {
    @State private var route: AppRoute = .menu
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
                    wrongMovements: SessionStore.shared.wrongMovements,
                    videoURL: SessionStore.shared.videoURL,
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
            SessionRecorder.shared.deleteSessionFile()
        }
    }
}

#Preview {
    ContentView()
}
