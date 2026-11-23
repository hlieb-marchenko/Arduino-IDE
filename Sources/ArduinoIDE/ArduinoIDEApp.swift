import AppKit
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
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    (NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible))?
                        .makeKeyAndOrderFront(nil)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Sketch Folder…") {
                    appState.openSketchFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("New Sketch File…") {
                    appState.isNewFileSheetPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.sketchFolderURL == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.saveActiveFile()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("Arduino") {
                Button("Verify Sketch") {
                    appState.checkSketch()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.runningAction != nil)

                Button("Upload Sketch") {
                    appState.uploadSketch()
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(appState.runningAction != nil)
            }
        }
    }
}
