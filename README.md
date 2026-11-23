# Arduino IDE for macOS

A native, dark-themed Arduino development environment for macOS, built with Swift, SwiftUI, and Arduino CLI.

The project uses Swift Package Manager and is designed to run directly from VS Code or the terminal without Xcode project or storyboard files.

## Screenshots

<img src="./img/Screenshot 2026-11-23 at 18.31.35.png"/>
<img src="./img/Screenshot 2026-11-23 at 18.41.17.png"/>
<img src="./img/Screenshot 2026-11-23 at 18.41.24.png"/>

## Features

- Native macOS interface in a VS Code-inspired dark theme
- Project explorer for `.ino`, `.cpp`, and `.h` sketch files
- Create new `.ino`, `.cpp`, and `.h` files from the explorer or with `Command + N`
- Native `NSTextView` editor with line numbers, syntax highlighting, and tab indentation
- Dirty-file indicator and manual save with `Command + S`
- Automatic save before Check and Upload
- Board and serial-port discovery through `arduino-cli board list`
- Sketch verification with `Command + R`
- Sketch upload with `Command + U`
- Real-time compiler and upload output
- Clickable compiler diagnostics that open the source file at the reported line
- Built-in serial monitor with selectable baud rates
- Automatic serial-port handoff when uploading
- Resizable output and serial-monitor panel

## Requirements

- macOS 13 or later
- Apple Silicon or Intel mac
- Swift 5.9 or later
- Arduino CLI

## Install Arduino CLI

With Homebrew:

```bash
brew update
brew install arduino-cli
arduino-cli version
```

## Build and Run

Open the project in VS Code or a terminal:

```bash
swift run
```

To build without launching:

```bash
swift build
```