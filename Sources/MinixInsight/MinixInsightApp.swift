import SwiftUI

@main
struct MinixInsightApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.status.isConnected && appState.isLogging ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}
