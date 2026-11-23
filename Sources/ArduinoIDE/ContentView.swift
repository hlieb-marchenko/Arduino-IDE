import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ActionToolbar()
            HSplitView {
                ProjectExplorer()
                    .frame(minWidth: 190, idealWidth: 230, maxWidth: 320)

                VSplitView {
                    CodeEditorPane()
                        .frame(minWidth: 420, minHeight: 260)

                    ConsolePane()
                        .frame(minHeight: 120, idealHeight: 180)
                }
                .frame(minWidth: 420)
            }
            StatusBar()
        }
        .background(IDEColor.editor)
        .foregroundStyle(IDEColor.primaryText)
        .sheet(isPresented: $appState.isNewFileSheetPresented) {
            NewSketchFileSheet()
                .environmentObject(appState)
        }
    }
}

private struct ActionToolbar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Button {
                appState.openSketchFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .help("Open an Arduino sketch folder")

            Divider()
                .frame(height: 22)

            Button {
                appState.checkSketch()
            } label: {
                if appState.runningAction == .check {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16)
                } else {
                    Label("Check", systemImage: "checkmark")
                }
            }
            .buttonStyle(IDEActionButtonStyle(tint: IDEColor.blue))
            .disabled(appState.runningAction != nil)
            .help("Verify with Arduino CLI (⌘R)")

            Button {
                appState.uploadSketch()
            } label: {
                if appState.runningAction == .upload {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16)
                } else {
                    Label("Upload", systemImage: "arrow.right")
                }
            }
            .buttonStyle(IDEActionButtonStyle(tint: IDEColor.green))
            .disabled(appState.runningAction != nil)
            .help("Upload with Arduino CLI (⌘U)")

            Spacer(minLength: 16)

            Picker("Board", selection: $appState.selectedBoardFQBN) {
                Text("No board selected").tag("")
                ForEach(appState.boardItems) { board in
                    Text(board.name).tag(board.fqbn)
                }
            }
            .frame(width: 190)
            .help("Board FQBN")

            Picker("Port", selection: $appState.selectedPortAddress) {
                Text("No port selected").tag("")
                ForEach(appState.portItems) { port in
                    Text(port.address).tag(port.address)
                }
            }
            .frame(width: 170)
            .help("Serial port")

            Button {
                Task {
                    await appState.refreshDevices()
                }
            } label: {
                if appState.isRefreshingDevices {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(appState.isRefreshingDevices)
            .help("Refresh boards and ports")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(IDEColor.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(IDEColor.border)
                .frame(height: 1)
        }
    }
}

private struct ProjectExplorer: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EXPLORER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(IDEColor.secondaryText)
                Spacer()
                Button {
                    appState.isNewFileSheetPresented = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .buttonStyle(.plain)
                .disabled(appState.sketchFolderURL == nil)
                .help("Create a new sketch file (⌘N)")
                Button {
                    appState.openSketchFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .help("Open sketch folder")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Text(appState.sketchFolderName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(IDEColor.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            if appState.sketchFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.sketchFolderURL == nil ? "No folder is open." : "No .ino, .cpp, or .h files found.")
                        .foregroundStyle(IDEColor.secondaryText)
                    Button("Open Folder…") {
                        appState.openSketchFolder()
                    }
                    .buttonStyle(.link)
                    if appState.sketchFolderURL != nil {
                        Button("New File…") {
                            appState.isNewFileSheetPresented = true
                        }
                        .buttonStyle(.link)
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(appState.sketchFiles) { file in
                            FileRow(
                                file: file,
                                isSelected: appState.activeFileURL == file.url
                            ) {
                                appState.selectFile(file)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .background(IDEColor.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(IDEColor.border)
                .frame(width: 1)
        }
    }
}

private struct NewSketchFileSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool
    @State private var fileName = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Sketch File")
                .font(.headline)

            Text("Add an .ino, .cpp, or .h file to \(appState.sketchFolderName).")
                .font(.system(size: 12))
                .foregroundStyle(IDEColor.secondaryText)

            TextField("Example: helpers.cpp", text: $fileName)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)
                .onSubmit(createFile)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(IDEColor.error)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Create") {
                    createFile()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            isNameFieldFocused = true
        }
    }

    private func createFile() {
        if let message = appState.createSketchFile(named: fileName) {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}

private struct FileRow: View {
    let file: SketchFile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 14)
                Text(file.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(isSelected ? IDEColor.selection : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        file.fileExtension == "ino" ? "number" : "curlybraces"
    }

    private var iconColor: Color {
        file.fileExtension == "ino" ? IDEColor.orange : IDEColor.blue
    }
}

private struct CodeEditorPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if appState.activeFileURL != nil {
                    Image(systemName: "curlybraces")
                        .foregroundStyle(IDEColor.blue)
                    Text("\(appState.activeFileURL?.lastPathComponent ?? "")\(appState.hasUnsavedChanges ? " •" : "")")
                        .foregroundStyle(IDEColor.primaryText)
                } else {
                    Text("No file selected")
                        .foregroundStyle(IDEColor.secondaryText)
                }
                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(IDEColor.panel)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(IDEColor.border)
                    .frame(height: 1)
            }

            if appState.activeFileURL == nil {
                VStack(spacing: 10) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 28))
                        .foregroundStyle(IDEColor.secondaryText)
                    Text("Open a sketch folder and select a source file to edit.")
                        .font(.system(size: 15, weight: .medium))
                    Button("Open Sketch Folder…") {
                        appState.openSketchFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(IDEColor.blue)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CodeEditorView(
                    text: $appState.editorText,
                    requestedLine: $appState.requestedEditorLine
                )
                .id(appState.activeFileURL)
            }
        }
        .background(IDEColor.editor)
    }
}

private struct ConsolePane: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = BottomTab.output
    @State private var serialInput = ""
    @State private var baudRate = 115200

    private enum BottomTab: String, CaseIterable, Identifiable {
        case output = "OUTPUT"
        case serial = "SERIAL MONITOR"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(BottomTab.allCases) { tab in
                    Button(tab.rawValue) {
                        selectedTab = tab
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? IDEColor.primaryText : IDEColor.secondaryText)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) {
                        if selectedTab == tab {
                            Rectangle().fill(IDEColor.blue).frame(height: 2)
                        }
                    }
                }
                Spacer()
                Button {
                    if selectedTab == .output {
                        appState.clearConsole()
                    } else {
                        appState.serialPortManager.clear()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help(selectedTab == .output ? "Clear output" : "Clear serial monitor")
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(IDEColor.panel)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(IDEColor.border)
                    .frame(height: 1)
            }

            if !appState.compilerDiagnostics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.compilerDiagnostics) { diagnostic in
                            Button {
                                appState.jumpToDiagnostic(diagnostic)
                                selectedTab = .output
                            } label: {
                                Label(
                                    "\(diagnostic.file):\(diagnostic.line)\(diagnostic.column.map { ":\($0)" } ?? "") — \(diagnostic.message)",
                                    systemImage: diagnostic.level == .warning ? "exclamationmark.triangle" : "xmark.octagon"
                                )
                                .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(diagnostic.level == .warning ? IDEColor.orange : IDEColor.error)
                        }
                    }
                    .padding(10)
                }
                .background(IDEColor.panel)
            }

            if selectedTab == .output {
                outputView
            } else {
                serialView
            }
        }
    }

    private var outputView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(appState.consoleEntries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .foregroundStyle(IDEColor.secondaryText)
                            Text(entry.message)
                                .foregroundStyle(consoleColor(for: entry.level))
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(entry.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: appState.consoleEntries.count) { _ in
                guard let lastEntry = appState.consoleEntries.last else { return }
                proxy.scrollTo(lastEntry.id, anchor: .bottom)
            }
        }
        .background(IDEColor.editor)
    }

    private var serialView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Baud", selection: $baudRate) {
                    ForEach(appState.serialPortManager.baudRates, id: \.self) { baud in
                        Text("\(baud)").tag(baud)
                    }
                }
                .frame(width: 110)

                if appState.serialPortManager.isConnected {
                    Button("Disconnect") {
                        appState.serialPortManager.disconnect()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        appState.serialPortManager.baudRate = baudRate
                        appState.serialPortManager.connect(port: appState.selectedPortAddress)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(IDEColor.green)
                    .disabled(appState.selectedPortAddress.isEmpty || appState.runningAction != nil)
                }
                Spacer()
                Circle()
                    .fill(appState.serialPortManager.isConnected ? IDEColor.green : IDEColor.secondaryText)
                    .frame(width: 7, height: 7)
            }
            .padding(8)
            .background(IDEColor.panel)

            ScrollView {
                Text(appState.serialPortManager.serialOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(IDEColor.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: .infinity)
            .background(IDEColor.editor)

            HStack(spacing: 8) {
                TextField("Send serial command", text: $serialInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendSerialCommand)
                Button("Send") {
                    sendSerialCommand()
                }
                .disabled(!appState.serialPortManager.isConnected || serialInput.isEmpty)
            }
            .padding(8)
            .background(IDEColor.panel)
        }
    }

    private func sendSerialCommand() {
        guard !serialInput.isEmpty else { return }
        appState.serialPortManager.send(serialInput)
        serialInput = ""
    }

    private func consoleColor(for level: ConsoleEntry.Level) -> Color {
        switch level {
        case .error:
            return IDEColor.error
        case .warning:
            return IDEColor.orange
        case .success:
            return IDEColor.green
        case .info:
            return IDEColor.primaryText
        }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 14) {
            Label(appState.sketchFolderURL == nil ? "No Sketch" : "Arduino Sketch", systemImage: "circuitboard")
            Spacer()
            Text(appState.activeFileURL?.lastPathComponent ?? "Ready")
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(IDEColor.statusBar)
    }
}

private struct IDEActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(configuration.isPressed ? 0.55 : 0.8))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private enum IDEColor {
    static let editor = Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255)
    static let sidebar = Color(red: 0x25 / 255, green: 0x25 / 255, blue: 0x26 / 255)
    static let panel = Color(red: 0x2D / 255, green: 0x2D / 255, blue: 0x30 / 255)
    static let statusBar = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
    static let border = Color.white.opacity(0.08)
    static let selection = Color(red: 0x09 / 255, green: 0x43 / 255, blue: 0x6A / 255)
    static let blue = Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0xCC / 255)
    static let green = Color(red: 0x16 / 255, green: 0x8B / 255, blue: 0x56 / 255)
    static let orange = Color(red: 0xCE / 255, green: 0x91 / 255, blue: 0x4B / 255)
    static let error = Color(red: 0xF4 / 255, green: 0x87 / 255, blue: 0x71 / 255)
    static let primaryText = Color(red: 0xD4 / 255, green: 0xD4 / 255, blue: 0xD4 / 255)
    static let secondaryText = Color(red: 0x9D / 255, green: 0x9D / 255, blue: 0x9D / 255)
}
