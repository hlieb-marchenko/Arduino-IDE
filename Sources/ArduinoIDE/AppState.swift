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
        case success
        case warning
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
    @Published private(set) var boardItems: [BoardItem] = []
    @Published private(set) var portItems: [PortItem] = []
    @Published var selectedBoardFQBN = ""
    @Published var selectedPortAddress = ""
    @Published private(set) var runningAction: RunningAction?
    @Published private(set) var isRefreshingDevices = false

    enum RunningAction {
        case check
        case upload
    }

    private var savedEditorText = ""
    private let cliService = ArduinoCLIService()
    private var cliTask: Task<Void, Never>?

    var sketchFolderName: String {
        sketchFolderURL?.lastPathComponent ?? "No Sketch Open"
    }

    var hasUnsavedChanges: Bool {
        activeFileURL != nil && editorText != savedEditorText
    }

    init() {
        appendConsole("Arduino IDE ready. Open a sketch folder to get started.")
        cliTask = Task { [weak self] in
            await self?.refreshDevices()
        }
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

    func refreshDevices() async {
        guard !isRefreshingDevices else { return }
        isRefreshingDevices = true
        defer { isRefreshingDevices = false }

        let discovery = await cliService.discoverDevices()
        boardItems = discovery.boards
        portItems = discovery.ports

        if boardItems.isEmpty == false,
           boardItems.contains(where: { $0.fqbn == selectedBoardFQBN }) == false {
            selectedBoardFQBN = boardItems[0].fqbn
        }
        if portItems.isEmpty == false,
           portItems.contains(where: { $0.address == selectedPortAddress }) == false {
            selectedPortAddress = portItems[0].address
        }

        if let result = discovery.result {
            if result.succeeded {
                appendConsole("Board discovery found \(boardItems.count) board(s) and \(portItems.count) port(s).")
            } else {
                appendDiagnosticText(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
        }
    }

    func checkSketch() {
        guard runningAction == nil else { return }
        guard saveActiveFile() else { return }
        guard let sketchFolderURL else {
            appendConsole("Open an Arduino sketch folder before compiling.", level: .error)
            return
        }
        guard !selectedBoardFQBN.isEmpty else {
            appendConsole("Select a board (FQBN) before compiling.", level: .error)
            return
        }

        runningAction = .check
        appendConsole("Verifying \(sketchFolderURL.lastPathComponent)…")

        cliTask = Task { [weak self] in
            guard let self else { return }
            let result = await cliService.compile(
                sketchPath: sketchFolderURL.path,
                fqbn: selectedBoardFQBN
            ) { [weak self] text, isError in
                Task { @MainActor in
                    self?.appendStreamOutput(text, isError: isError)
                }
            }
            runningAction = nil
            if result.succeeded {
                appendMemoryUsage(from: result.stdout + "\n" + result.stderr)
                appendConsole("Verification succeeded.", level: .success)
            } else {
                appendDiagnosticText(result.stdout)
                appendDiagnosticText(result.stderr)
                appendConsole("Verification failed with exit code \(result.exitCode).", level: .error)
            }
        }
    }

    func uploadSketch() {
        guard runningAction == nil else { return }
        guard saveActiveFile() else { return }
        guard let sketchFolderURL else {
            appendConsole("Open an Arduino sketch folder before uploading.", level: .error)
            return
        }
        guard !selectedBoardFQBN.isEmpty else {
            appendConsole("Select a board (FQBN) before uploading.", level: .error)
            return
        }
        guard !selectedPortAddress.isEmpty else {
            appendConsole("Select a serial port before uploading.", level: .error)
            return
        }

        runningAction = .upload
        appendConsole("Uploading \(sketchFolderURL.lastPathComponent) to \(selectedPortAddress)…")

        cliTask = Task { [weak self] in
            guard let self else { return }
            let result = await cliService.upload(
                sketchPath: sketchFolderURL.path,
                fqbn: selectedBoardFQBN,
                port: selectedPortAddress
            ) { [weak self] text, isError in
                Task { @MainActor in
                    self?.appendStreamOutput(text, isError: isError)
                }
            }
            runningAction = nil
            if result.succeeded {
                appendConsole("Upload succeeded.", level: .success)
            } else {
                appendDiagnosticText(result.stdout)
                appendDiagnosticText(result.stderr)
                appendConsole("Upload failed with exit code \(result.exitCode).", level: .error)
            }
        }
    }

    func clearConsole() {
        consoleEntries.removeAll()
    }

    private func appendStreamOutput(_ text: String, isError: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendDiagnosticText(trimmed, forceError: isError)
    }

    private func appendDiagnosticText(_ text: String, forceError: Bool = false) {
        let lines = text.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let lowercased = line.lowercased()
            let level: ConsoleEntry.Level
            if forceError || lowercased.contains("error") || lowercased.contains("fatal") {
                level = .error
            } else if lowercased.contains("warning") {
                level = .warning
            } else if lowercased.contains("succeeded") || lowercased.contains("successfully") {
                level = .success
            } else {
                level = .info
            }
            appendConsole(line, level: level)
        }
    }

    private func appendMemoryUsage(from text: String) {
        let patterns = [
            #"Sketch uses \d+[^\n]*"#,
            #"Global variables use \d+[^\n]*"#,
            #"text data\s*bss\s*dec hex filename"#,
            #"Maximum is \d+[^\n]*"#
        ]

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..., in: text)
            for match in expression.matches(in: text, range: range) {
                if let matchRange = Range(match.range, in: text) {
                    appendConsole(String(text[matchRange]), level: .info)
                }
            }
        }
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
            Task { [weak self] in
                await self?.refreshDevices()
            }
        } catch {
            appendConsole("Could not open folder: \(error.localizedDescription)", level: .error)
        }
    }
}
