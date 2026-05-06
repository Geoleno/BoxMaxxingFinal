import SwiftUI

//camelCase  -> variable, constant -> non object func / var / let / guard let abc = asda
//PascalCase -> struct/class/enum -> object

enum BoxingType {
    case upperCut, jab, cross
}

struct ContentView: View {
    enum AppRoute {
        case menu, record, results
    }
    
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
                    // Load demo data for presentation: The 1-2 combo (left jab + right jab), 2-minute session
                    sessionState = SessionState(selectedComboId: "c1",
                                               selectedMoveIds: ["lj", "rj"],
                                               sessionLength: 2)
                    SessionStore.shared.save(movements: generateDemoWrongMovements(),
                                            videoURL: nil,
                                            startDate: Date(),
                                            duration: 120)
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
