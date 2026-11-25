//
//  ContentView.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI

// REM: Build step 2 (Blueprint 028–035) — the editor window on Apple's standard pieces from day
// one (028/008): the canvas is the document, and a standard .inspector holds the details.
// On a wide window the inspector is a column; on a compact width (iPhone 16e, closed Duo)
// SwiftUI presents the same inspector as a sheet — one adaptive layout, not four (007).
//
// REM: His rule — no placeholders, no dead buttons. Only what works today is on screen: zoom,
// canvas focus, floating preview, the status line and the canvas details. The two-row tool box
// arrives with the tools (step 4) and Layers / History with the layer model (step 3).
//
// REM: Blueprint 030 — no About button on the toolbar: macOS already puts About Layerworks in
// the app menu, and it shows the build number. Export and Share join the bar in step 6.

struct ContentView: View {
    @ObservedObject var document: LayerworksDocument
    @StateObject private var editor = EditorState()
    @Environment(\.undoManager) private var undoManager
    // Every setting and pane state persists across launches (his rule).
    @AppStorage("lw.inspector.visible") private var showInspector = true

    var body: some View {
        VStack(spacing: 0) {
            CanvasView(document: document, editor: editor)
                .overlay(alignment: .topLeading) {
                    // Focus mode keeps one way back on screen (iPhone has no menu bar).
                    if editor.focusMode {
                        Button { editor.toggleFocusMode() } label: {
                            Label("Exit Canvas Focus", systemImage: "arrow.down.right.and.arrow.up.left")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .background(.regularMaterial, in: Circle())
                        .help("Exit Canvas Focus")
                        .padding(12)
                    }
                }
            if !editor.focusMode {
                Divider()
                ToolBox(editor: editor)
                Divider()
                ZoomPanel(editor: editor)
                Divider()
                StatusLine(editor: editor)
            }
        }
        .inspector(isPresented: inspectorBinding) {
            VStack(spacing: 0) {
                ToolInspector(document: document, editor: editor)
                    .frame(maxHeight: .infinity)
                Divider()
                LayersAndHistory(document: document, editor: editor)
                    .frame(minHeight: 280)
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label(showInspector ? "Hide Inspector" : "Show Inspector",
                          systemImage: "sidebar.trailing")
                }
                .help(showInspector ? "Hide Inspector" : "Show Inspector")
                .disabled(editor.focusMode)
            }
        }
        .focusedSceneObject(editor)
        .focusedSceneObject(document)
        // Undo / History can remove the selected layer; something is always selected (036).
        .onChange(of: document.manifest.layers) { _, layers in
            if !layers.contains(where: { $0.id == editor.selectedLayer }) {
                editor.selectedLayer = layers.last { $0.role == .content && $0.isVisible }?.id ?? layers.last?.id
            }
        }
        .confirmationDialog("Purge History?", isPresented: $editor.askPurge, titleVisibility: .visible) {
            Button("Purge History", role: .destructive) {
                document.purgeHistory(undoManager: undoManager)
                editor.status = "History purged; the picture is kept"
            }
        } message: { Text("The picture is kept. Every History step is erased. This can't be undone.") }
        .onAppear { editor.status = "Opened a \(document.manifest.canvasWidth) × \(document.manifest.canvasHeight) canvas" }
    }

    /// Focus mode hides the inspector without forgetting whether it was open.
    private var inspectorBinding: Binding<Bool> {
        Binding(get: { showInspector && !editor.focusMode },
                set: { if !editor.focusMode { showInspector = $0 } })
    }
}

/// Blueprint 029: the Zoom panel — zoom out, the tappable zoom level (back to 100%), zoom in,
/// fit width, canvas focus, and the floating-preview switch.
struct ZoomPanel: View {
    @ObservedObject var editor: EditorState
    @AppStorage("lw.preview.visible") private var previewVisible = true

    var body: some View {
        HStack(spacing: 4) {
            panelButton("Zoom Out", "minus.magnifyingglass") { editor.zoomOut() }
            Button(editor.zoomText) { editor.actualSize() }
                .buttonStyle(.borderless)
                .monospacedDigit()
                .frame(minWidth: 64, minHeight: 44)
                .contentShape(Rectangle())
                .help("Back to 100%")
                .accessibilityLabel("Zoom level")
                .accessibilityValue(editor.zoomText)
                .accessibilityHint("Returns to 100%")
            panelButton("Zoom In", "plus.magnifyingglass") { editor.zoomIn() }
            panelButton("Fit Width", "arrow.left.and.right") { editor.fitWidth() }
            Spacer(minLength: 0)
            Toggle(isOn: $previewVisible) {
                Label("Preview", systemImage: "pip")
            }
            .toggleStyle(.button)
            .frame(minHeight: 44)
            .help("Floating preview")
            .accessibilityLabel("Floating preview")
            .onChange(of: previewVisible) { _, on in
                editor.status = on ? "Floating preview on" : "Floating preview off"
            }
            panelButton("Canvas Focus", "arrow.up.left.and.arrow.down.right") { editor.toggleFocusMode() }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 8)
    }

    private func panelButton(_ title: String, _ symbol: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

/// Blueprint 029: the status line along the bottom reports every action. The build line sits
/// at its right end (his standing order: every build shows its commit number).
struct StatusLine: View {
    @ObservedObject var editor: EditorState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                message
                Spacer(minLength: 12)
                Text(BuildStamp.line).foregroundStyle(.secondary)
            }
            message.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var message: some View {
        Text(editor.status)
            .accessibilityIdentifier("Status")
            .accessibilityLabel("Status")
            .accessibilityValue(editor.status)
    }
}

#Preview {
    ContentView(document: LayerworksDocument())
}
