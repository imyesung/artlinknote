// GOAL: App entry. Provide EnvironmentObject store, load on .task.
// Keep minimal Scene body. No business logic here.

import SwiftUI

@main
struct ArtlinkApp: App {
    @StateObject private var store = NotesStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task { await store.load() }
        }
    }
}
