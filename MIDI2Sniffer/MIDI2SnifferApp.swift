// MIDI2SnifferApp.swift — macOS app entry point

import SwiftUI
import MIDI2SnifferKit

@main
struct MIDI2SnifferApp: App {
    var body: some Scene {
        WindowGroup {
            SnifferMainView()
        }
        .defaultSize(width: 1100, height: 700)
    }
}
