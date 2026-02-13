// GOAL: App entry. Provide EnvironmentObject store, load on .task.
// Keep minimal Scene body. No business logic here.

import SwiftUI

@main
struct ArtlinkApp: App {
    @StateObject private var store = NotesStore()
    
    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    // Skip optional/slow startup work during UI tests to avoid watchdog kills.
                    if !isUITesting {
                        await store.load()
                    }
                }
        }
    }
}
