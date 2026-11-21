import SwiftUI

@main
@MainActor
struct ArduinoIDEApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Sketch Folder…") {
                    appState.openSketchFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.saveActiveFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.hasUnsavedChanges)
            }
        }
    }
}
