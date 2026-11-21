import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct SketchFile: Identifiable, Hashable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }
}

struct ConsoleEntry: Identifiable {
    enum Level {
        case info
        case error
    }

    let id = UUID()
    let timestamp: Date
    let message: String
    let level: Level
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var sketchFolderURL: URL?
    @Published private(set) var sketchFiles: [SketchFile] = []
    @Published var activeFileURL: URL?
    @Published var editorText = ""
    @Published private(set) var consoleEntries: [ConsoleEntry] = []

    private var savedEditorText = ""

    var sketchFolderName: String {
        sketchFolderURL?.lastPathComponent ?? "No Sketch Open"
    }

    var hasUnsavedChanges: Bool {
        activeFileURL != nil && editorText != savedEditorText
    }

    init() {
        appendConsole("Arduino IDE ready. Open a sketch folder to get started.")
    }

    func openSketchFolder() {
        let panel = NSOpenPanel()
        panel.title = "Open Arduino Sketch Folder"
        panel.message = "Choose a folder containing your Arduino sketch."
        panel.prompt = "Open"
        panel.allowedContentTypes = [.folder]
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadSketchFolder(at: url)
    }

    func selectFile(_ file: SketchFile) {
        guard activeFileURL != file.url else { return }
        guard saveActiveFile() else { return }

        do {
            editorText = try String(contentsOf: file.url, encoding: .utf8)
            activeFileURL = file.url
            savedEditorText = editorText
        } catch {
            appendConsole("Could not read \(file.name): \(error.localizedDescription)", level: .error)
        }
    }

    @discardableResult
    func saveActiveFile() -> Bool {
        guard let activeFileURL, hasUnsavedChanges else { return true }

        do {
            try Data(editorText.utf8).write(to: activeFileURL, options: .atomic)
            savedEditorText = editorText
            appendConsole("Saved \(activeFileURL.lastPathComponent).")
            return true
        } catch {
            appendConsole(
                "Could not save \(activeFileURL.lastPathComponent): \(error.localizedDescription)",
                level: .error
            )
            return false
        }
    }

    func appendConsole(_ message: String, level: ConsoleEntry.Level = .info) {
        consoleEntries.append(
            ConsoleEntry(timestamp: Date(), message: message, level: level)
        )
    }

    func clearConsole() {
        consoleEntries.removeAll()
    }

    private func loadSketchFolder(at url: URL) {
        guard saveActiveFile() else { return }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            let supportedExtensions: Set<String> = ["ino", "cpp", "h"]
            let files = try contents
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
                .map(SketchFile.init(url:))
                .sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }

            sketchFolderURL = url
            sketchFiles = files
            activeFileURL = nil
            editorText = ""
            savedEditorText = ""
            appendConsole("Opened \(url.lastPathComponent) (\(files.count) supported files).")

            if let firstFile = files.first {
                selectFile(firstFile)
            }
        } catch {
            appendConsole("Could not open folder: \(error.localizedDescription)", level: .error)
        }
    }
}
