import SwiftUI

struct ContentView: View {
    @State private var store = DashStore()
    @State private var mileageTracker = MileageTrackerService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            EvaluateView(store: store, mileageTracker: mileageTracker)
                .tabItem {
                    Label("Evaluate", systemImage: "dollarsign.circle.fill")
                }

            InsightsView(store: store, mileageTracker: mileageTracker)
                .tabItem {
                    Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView(store: store)
                .tabItem {
                    Label("Rules & Car", systemImage: "slider.horizontal.3")
                }
        }
        .tint(.green)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                mileageTracker.saveDraftNow()
                store.flushSave()
            }
        }
        .alert(
            "Recovered Unsaved Shift",
            isPresented: Binding(
                get: { store.recoveredSessionMessage != nil },
                set: { if !$0 { store.recoveredSessionMessage = nil } }
            )
        ) {
            Button("OK") { store.recoveredSessionMessage = nil }
        } message: {
            Text(store.recoveredSessionMessage ?? "")
        }
    }
}
