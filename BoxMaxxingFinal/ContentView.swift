import SwiftUI

enum AppRoute {
    case menu, record, results
}

struct ContentView: View {
    @State private var route: AppRoute = .menu
    @State private var sessionState = SessionState()
    @State private var sessionEvents: [SessionEvent] = []

    var body: some View {
        ZStack {
            switch route {
            case .menu:
                MenuView(state: $sessionState) {
                    withAnimation(.easeInOut(duration: 0.25)) { route = .record }
                }
                .transition(.opacity)

            case .record:
                RecordingView(
                    state: sessionState,
                    onFinish: {
                        sessionEvents = generateEvents(state: sessionState)
                        withAnimation(.easeInOut(duration: 0.25)) { route = .results }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.25)) { route = .menu }
                    }
                )
                .transition(.opacity)

            case .results:
                ResultsView(
                    state: sessionState,
                    events: sessionEvents,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) { route = .menu }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: route)
    }
}

#Preview {
    ContentView()
}
