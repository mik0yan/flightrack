import SwiftUI

@main
struct FlightTrackApp: App {
    @StateObject private var store = FlightStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            FlightDashboardView(store: store)
                .tint(.cyan)
                .task { store.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.start()
                    } else if phase == .background {
                        store.stop()
                    }
                }
        }
    }
}
