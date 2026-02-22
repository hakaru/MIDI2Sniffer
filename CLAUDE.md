# CLAUDE.md

## Project Overview

MIDI2Sniffer is a passive MIDI 2.0 / Property Exchange sniffer for macOS. It captures and displays MIDI 2.0 UMP messages in real-time for debugging and analysis.

## Build & Run

The project uses **XCGen** (`project.yml`) to generate the Xcode project. Open `MIDI2Sniffer.xcworkspace`.

```bash
# macOS build
xcodebuild build -workspace MIDI2Sniffer.xcworkspace -scheme MIDI2Sniffer -destination 'platform=macOS'
```

**Requirements:** Xcode 16.0+, Swift 6.0+, macOS 15.0+
**Local dependency:** MIDI2Kit at `../../MIDI2Kit`

## Architecture

- **MIDI2SnifferPackage** (Swift Package) contains all logic in `MIDI2SnifferKit`
- **MIDI2Sniffer/** is the thin macOS app shell with `@main` entry point

### Key Types

| Type | Role |
|------|------|
| `MIDISnifferEngine` | MIDI device enumeration and UMP message capture via MIDI2Kit |
| `CaptureSession` | Recording session management |
| `MessageDecoder` | UMP message decoding to human-readable format |
| `SnifferState` | @Observable shared state container |
| `SnifferMainView` | Root SwiftUI view |

## Coding Conventions

- **Swift 6 strict concurrency** enabled
- **MV pattern** (Model-View, no ViewModel)
- **@Observable** macro (no ObservableObject)
- **Swift Concurrency** only (no GCD)
