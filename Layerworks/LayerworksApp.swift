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
        // REM: a usable first window on the MacBook Air (1440 × 932): room for the canvas and a
        // Layers / History list you can work in. The user can resize; the system remembers it.
        .defaultSize(width: 1200, height: 780)
        .commands {
            #if os(macOS)
            SaveCommands()
            #endif
            ZoomCommands()
            HistoryCommands()
            #if os(macOS)
            NewFromImportCommand()
            #endif
            InspectorCommands()
        }
    }
}

/// Blueprint 029 — zoom and canvas focus in Apple's View menu, with the usual shortcuts
/// (⌘= / ⌘− / ⌘0 like Preview and Safari; ⌘9 fits the width). On iPad they work from a
/// hardware keyboard. Each acts on the front window only.
struct ZoomCommands: Commands {
    @FocusedObject private var editor: EditorState?

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { editor?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { editor?.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { editor?.actualSize() }
                .keyboardShortcut("0")
            Button("Fit Width") { editor?.fitWidth() }
                .keyboardShortcut("9")
            Button(editor?.focusMode == true ? "Exit Canvas Focus" : "Canvas Focus") {
                editor?.toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
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

/// File ▸ Optimize History and Purge History… (his lock 2026-11-25 13:11: "History's ⋯ menu
/// becomes separate Optimize and Purge buttons (and File menu items)").
struct HistoryCommands: Commands {
    @FocusedObject private var editor: EditorState?
    @FocusedObject private var document: LayerworksDocument?

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Optimize History") {
                if let editor, let document { editor.optimize(document, undoManager: nil) }
            }
            .disabled(document == nil)
            Button("Purge History…") { editor?.askPurge = true }
                .disabled(document == nil || (document?.history.count ?? 0) < 2)
        }
    }
}
