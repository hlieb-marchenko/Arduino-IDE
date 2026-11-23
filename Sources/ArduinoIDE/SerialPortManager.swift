import Foundation
import Darwin

@MainActor
final class SerialPortManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isPaused = false
    @Published private(set) var serialOutput = ""
    @Published var baudRate = 115200

    private var fileHandle: FileHandle?
    private var descriptor: Int32 = -1

    let baudRates = [300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400]

    func connect(port: String) {
        guard !port.isEmpty else { return }
        disconnect()

        descriptor = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            serialOutput += "[Serial] Could not open \(port): \(String(cString: strerror(errno)))\n"
            return
        }

        _ = fcntl(descriptor, F_SETFL, 0)
        var settings = termios()
        guard tcgetattr(descriptor, &settings) == 0 else {
            let message = String(cString: strerror(errno))
            close(descriptor)
            descriptor = -1
            serialOutput += "[Serial] Could not read serial port settings: \(message)\n"
            return
        }

        cfmakeraw(&settings)
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        settings.c_cflag &= ~tcflag_t(CSIZE)
        settings.c_cflag |= tcflag_t(CS8)
        settings.c_cflag &= ~tcflag_t(PARENB)
        settings.c_cflag &= ~tcflag_t(CSTOPB)
        settings.c_cflag &= ~tcflag_t(CRTSCTS)

        guard let speed = speedConstant(for: baudRate) else {
            close(descriptor)
            descriptor = -1
            serialOutput += "[Serial] Unsupported baud rate: \(baudRate)\n"
            return
        }
        guard cfsetspeed(&settings, speed) == 0 else {
            let message = String(cString: strerror(errno))
            close(descriptor)
            descriptor = -1
            serialOutput += "[Serial] Could not set baud rate: \(message)\n"
            return
        }
        guard tcsetattr(descriptor, TCSANOW, &settings) == 0 else {
            let message = String(cString: strerror(errno))
            close(descriptor)
            descriptor = -1
            serialOutput += "[Serial] Could not configure serial port: \(message)\n"
            return
        }
        tcflush(descriptor, TCIFLUSH)

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        fileHandle = handle
        isPaused = false
        isConnected = true
        serialOutput += "[Serial] Connected to \(port) at \(baudRate) baud.\n"

        handle.readabilityHandler = { [weak self] (handle: FileHandle) in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    guard let self, !self.isPaused else { return }
                    self.serialOutput.append(text)
                }
            }
        }
    }

    func disconnect() {
        fileHandle?.readabilityHandler = nil
        fileHandle = nil
        if descriptor >= 0 {
            tcflush(descriptor, TCIOFLUSH)
            close(descriptor)
            descriptor = -1
        }
        if isConnected {
            serialOutput += "[Serial] Disconnected.\n"
        }
        isConnected = false
        isPaused = false
    }

    func pause() {
        guard isConnected else { return }
        fileHandle?.readabilityHandler = nil
        isPaused = true
        serialOutput += "[Serial] Paused for upload.\n"
    }

    func resume(port: String) {
        if isPaused || isConnected == false {
            connect(port: port)
        }
    }

    func send(_ text: String) {
        guard isConnected, descriptor >= 0 else { return }
        let payload = (text + "\n").data(using: .utf8) ?? Data()
        do {
            try fileHandle?.write(contentsOf: payload)
            serialOutput += "TX: \(text)\n"
        } catch {
            serialOutput += "[Serial] Send failed: \(error.localizedDescription)\n"
        }
    }

    func clear() {
        serialOutput = ""
    }

    private func speedConstant(for baud: Int) -> speed_t? {
        switch baud {
        case 300: return speed_t(B300)
        case 1200: return speed_t(B1200)
        case 2400: return speed_t(B2400)
        case 4800: return speed_t(B4800)
        case 9600: return speed_t(B9600)
        case 19200: return speed_t(B19200)
        case 38400: return speed_t(B38400)
        case 57600: return speed_t(B57600)
        case 115200: return speed_t(B115200)
        case 230400: return speed_t(B230400)
        default: return nil
        }
    }

    deinit {
        if descriptor >= 0 {
            close(descriptor)
        }
    }
}
