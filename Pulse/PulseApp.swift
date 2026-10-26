import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(.orange)
        }
    }
}
