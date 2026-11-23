import Foundation

struct BoardItem: Identifiable, Hashable, Sendable {
    let fqbn: String
    let name: String

    var id: String { fqbn }
}

struct PortItem: Identifiable, Hashable, Sendable {
    let address: String
    let label: String

    var id: String { address }
}

struct CLIResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

@MainActor
final class ArduinoCLIService: ObservableObject {
    private var cliURL: URL?

    init() {
        cliURL = Self.detectCLI()
    }

    var executableDescription: String {
        cliURL?.path ?? "arduino-cli not found"
    }

    var isAvailable: Bool {
        cliURL != nil
    }

    func refreshCLIPath() {
        cliURL = Self.detectCLI()
    }

    func discoverDevices() async -> (boards: [BoardItem], ports: [PortItem], result: CLIResult?) {
        refreshCLIPath()
        guard let cliURL else {
            let error = CLIResult(
                exitCode: 127,
                stdout: "",
                stderr: "arduino-cli was not found. Install it with `brew install arduino-cli`, then refresh device discovery."
            )
            return ([], [], error)
        }

        let result = await execute(
            executableURL: cliURL,
            arguments: ["board", "list", "--format", "json"],
            onOutput: nil
        )
        guard result.succeeded else {
            return ([], [], result)
        }

        let response: BoardListResponse
        do {
            response = try JSONDecoder().decode(BoardListResponse.self, from: Data(result.stdout.utf8))
        } catch {
            return (
                [],
                [],
                CLIResult(
                    exitCode: 1,
                    stdout: result.stdout,
                    stderr: "Could not parse Arduino CLI device discovery output: \(error.localizedDescription)"
                )
            )
        }

        var boardMap: [String: BoardItem] = [:]
        var portMap: [String: PortItem] = [:]

        func addBoard(_ entry: BoardListEntry) {
            if let fqbn = entry.fqbn?.trimmingCharacters(in: .whitespacesAndNewlines),
               !fqbn.isEmpty {
                let name = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                boardMap[fqbn] = BoardItem(
                    fqbn: fqbn,
                    name: name.flatMap { $0.isEmpty ? nil : $0 } ?? fqbn
                )
            }
        }

        func addPort(_ port: BoardPort?) {
            if let address = port?.address?.trimmingCharacters(in: .whitespacesAndNewlines),
               !address.isEmpty {
                let label = port?.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                portMap[address] = PortItem(
                    address: address,
                    label: label.flatMap { $0.isEmpty ? nil : $0 } ?? address
                )
            }
        }

        for entry in response.boards {
            addBoard(entry)
            addPort(entry.port)
        }
        for detectedPort in response.detectedPorts {
            addPort(detectedPort.port)
            detectedPort.matchingBoards.forEach(addBoard)
        }

        let boards = boardMap.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let ports = portMap.values.sorted {
            $0.address.localizedStandardCompare($1.address) == .orderedAscending
        }
        return (boards, ports, result)
    }

    func compile(
        sketchPath: String,
        fqbn: String,
        onOutput: @escaping @Sendable (String, Bool) -> Void
    ) async -> CLIResult {
        refreshCLIPath()
        guard let cliURL else {
            return CLIResult(
                exitCode: 127,
                stdout: "",
                stderr: "arduino-cli was not found at /opt/homebrew/bin/arduino-cli or /usr/local/bin/arduino-cli."
            )
        }

        return await execute(
            executableURL: cliURL,
            arguments: ["compile", "--fqbn", fqbn, "--format", "json", sketchPath],
            onOutput: onOutput
        )
    }

    func upload(
        sketchPath: String,
        fqbn: String,
        port: String,
        onOutput: @escaping @Sendable (String, Bool) -> Void
    ) async -> CLIResult {
        refreshCLIPath()
        guard let cliURL else {
            return CLIResult(
                exitCode: 127,
                stdout: "",
                stderr: "arduino-cli was not found at /opt/homebrew/bin/arduino-cli or /usr/local/bin/arduino-cli."
            )
        }

        return await execute(
            executableURL: cliURL,
            arguments: ["upload", "--fqbn", fqbn, "-p", port, sketchPath],
            onOutput: onOutput
        )
    }

    private func execute(
        executableURL: URL,
        arguments: [String],
        onOutput: (@Sendable (String, Bool) -> Void)?
    ) async -> CLIResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdoutCollector = CLIOutputCollector()
            let stderrCollector = CLIOutputCollector()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                    }
                    return
                }
                stdoutCollector.append(text)
                onOutput?(text, false)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                    }
                    return
                }
                stderrCollector.append(text)
                onOutput?(text, true)
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                return CLIResult(
                    exitCode: 127,
                    stdout: "",
                    stderr: "Could not start arduino-cli: \(error.localizedDescription)"
                )
            }

            process.waitUntilExit()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if !remainingStdout.isEmpty, let text = String(data: remainingStdout, encoding: .utf8) {
                stdoutCollector.append(text)
                onOutput?(text, false)
            }
            if !remainingStderr.isEmpty, let text = String(data: remainingStderr, encoding: .utf8) {
                stderrCollector.append(text)
                onOutput?(text, true)
            }

            return CLIResult(
                exitCode: process.terminationStatus,
                stdout: stdoutCollector.text,
                stderr: stderrCollector.text
            )
        }.value
    }

    private static func detectCLI() -> URL? {
        let fixedCandidates = [
            "/opt/homebrew/bin/arduino-cli",
            "/usr/local/bin/arduino-cli"
        ]
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("arduino-cli").path }
        return (fixedCandidates + pathCandidates)
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private struct BoardListResponse: Decodable {
    let boards: [BoardListEntry]
    let detectedPorts: [DetectedPort]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boards = try container.decodeIfPresent([BoardListEntry].self, forKey: .boards) ?? []
        detectedPorts = try container.decodeIfPresent([DetectedPort].self, forKey: .detectedPorts) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case boards
        case detectedPorts = "detected_ports"
    }
}

private struct DetectedPort: Decodable {
    let port: BoardPort?
    let matchingBoards: [BoardListEntry]

    private enum CodingKeys: String, CodingKey {
        case port
        case matchingBoards = "matching_boards"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        port = try container.decodeIfPresent(BoardPort.self, forKey: .port)
        matchingBoards = try container.decodeIfPresent([BoardListEntry].self, forKey: .matchingBoards) ?? []
    }
}

private struct BoardListEntry: Decodable {
    let name: String?
    let fqbn: String?
    let port: BoardPort?
}

private struct BoardPort: Decodable {
    let address: String?
    let label: String?
}

private final class CLIOutputCollector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.arduinoide.cli-output")
    private var buffer = ""

    func append(_ text: String) {
        queue.sync {
            buffer += text
        }
    }

    var text: String {
        queue.sync {
            buffer
        }
    }
}
