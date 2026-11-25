//
//  LayerworksApp.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// REM: Blueprint 012 / 019 / 020 — no custom Welcome window. On the Mac, DocumentGroup's own
// Open window is the front door; on iPhone and iPad, Apple's document launch screen (018).
// Recents come from the system: File ▸ Open Recent and the Dock menu (017).

@main
struct LayerworksApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { LayerworksDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            #if os(macOS)
            SaveCommands()
            #endif
        }
    }
}

#if os(macOS)
/// Blueprint 027 (kept on his 2026-10-11 word: "save as better be just save as and not require
/// all those key combos"): Save As… sits in plain sight at ⇧⌘S and Duplicate is off the menu.
/// Rename…, Move To… and Apple's Revert To items stay (Blueprint 003: Versions, not custom
/// revert markers). Each item sends Apple's own NSDocument action, so nothing is reinvented.
struct SaveCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") { send(#selector(NSDocument.save(_:))) }
                .keyboardShortcut("s")
            Button("Save As…") { send(#selector(NSDocument.saveAs(_:))) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Rename…") { send(#selector(NSDocument.rename(_:))) }
            Button("Move To…") { send(#selector(NSDocument.move(_:))) }
            Divider()
            Menu("Revert To") {
                Button("Last Saved Version") { send(#selector(NSDocument.revertToSaved(_:))) }
                Button("Browse All Versions…") { send(#selector(NSDocument.browseVersions(_:))) }
            }
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
#endif
