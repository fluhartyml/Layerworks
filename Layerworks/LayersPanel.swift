//
//  LayersPanel.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI

// REM: Blueprint 029 / 036 / 037 — the right column switches Layers / History.
// Layers: the top of the list is the top of the stack. The checkbox is for Merge and Link,
// NOT for selection; click or tap the name to select. Eye: green shows, red crossed-out hides.
// Drag to reorder (iPad: the handle on the right). Right-click / long-press: Rename, Duplicate,
// Delete. No "…" menus anywhere (his rule): every action is its own button.

struct LayersAndHistory: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @AppStorage("lw.panel") private var panel = Panel.layers

    enum Panel: String, CaseIterable { case layers = "Layers", history = "History" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            switch panel {
            case .layers: LayersPanel(document: document, editor: editor)
            case .history: HistoryPanel(document: document, editor: editor)
            }
        }
    }
}

struct LayersPanel: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var renaming: Layer?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    editor.selectedLayer = document.addLayer(above: editor.selectedLayer, undoManager: undoManager)
                    editor.status = "Added a layer"
                } label: {
                    Label("Add Layer", systemImage: "plus").frame(minWidth: 44, minHeight: 44)
                }
                .help("Add a layer above the selected one")
                Spacer(minLength: 0)
                Button("Merge") {
                    if let id = document.merge(editor.checked, undoManager: undoManager) {
                        editor.status = "Merged \(editor.checked.count) layers; originals hidden"
                        editor.checked = []
                        editor.selectedLayer = id
                    }
                }
                .disabled(editor.checked.count < 2)
                .frame(minHeight: 44)
                .help("Merge the checked layers into a new layer")
                Button("Link") {
                    document.link(editor.checked, undoManager: undoManager)
                    editor.status = "Linked \(editor.checked.count) layers"
                    editor.checked = []
                }
                .disabled(editor.checked.count < 2)
                .frame(minHeight: 44)
                .help("Link the checked layers so they move together")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)

            List {
                // Shown top of stack first; the model stores bottom first.
                ForEach(document.layers.reversed()) { layer in
                    LayerRow(layer: layer, document: document, editor: editor,
                             rename: { renaming = layer; newName = layer.name })
                }
                .onMove { source, destination in
                    let count = document.layers.count
                    let from = IndexSet(source.map { count - 1 - $0 })
                    document.move(from: from, to: count - destination, undoManager: undoManager)
                    editor.status = "Moved a layer"
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
        }
        .alert("Rename Layer", isPresented: Binding(get: { renaming != nil },
                                                    set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let layer = renaming {
                    document.rename(layer.id, to: newName, undoManager: undoManager)
                    editor.status = "Renamed a layer to “\(newName)”"
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .onAppear(perform: selectDefault)
    }

    /// Something is always selected (036: select the layer first, then use the tool).
    private func selectDefault() {
        if document.layer(editor.selectedLayer) == nil {
            editor.selectedLayer = document.layers.last { $0.role == .content }?.id ?? document.layers.last?.id
        }
    }
}

struct LayerRow: View {
    let layer: Layer
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    var rename: () -> Void
    @Environment(\.undoManager) private var undoManager

    private var isSelected: Bool { editor.selectedLayer == layer.id }
    private var isChecked: Bool { editor.checked.contains(layer.id) }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isChecked { editor.checked.remove(layer.id) } else { editor.checked.insert(layer.id) }
            } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .frame(minWidth: 32, minHeight: 44)
            }
            .accessibilityLabel("Check \(layer.name) for Merge or Link")
            .accessibilityValue(isChecked ? "checked" : "not checked")

            Button {
                editor.selectedLayer = layer.id
                editor.status = "Selected “\(layer.name)”"
            } label: {
                HStack(spacing: 4) {
                    Text(layer.name).lineLimit(1)
                    if layer.linkGroup != nil {
                        Image(systemName: "link").foregroundStyle(.secondary)
                            .accessibilityLabel("linked")
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .fontWeight(isSelected ? .semibold : .regular)
            }
            .accessibilityLabel(layer.name)
            .accessibilityValue(isSelected ? "selected" : "")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                document.setVisible(layer.id, !layer.isVisible, undoManager: undoManager)
                editor.status = "\(layer.isVisible ? "Hid" : "Showed") “\(layer.name)”"
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.isVisible ? .green : .red)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(layer.isVisible ? "Hide \(layer.name)" : "Show \(layer.name)")
        }
        .buttonStyle(.borderless)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button("Rename…", action: rename)
            Button("Duplicate") {
                editor.selectedLayer = document.duplicate(layer.id, undoManager: undoManager)
                editor.status = "Duplicated “\(layer.name)”"
            }
            if layer.linkGroup != nil {
                Button("Unlink") {
                    document.unlink(layer.id, undoManager: undoManager)
                    editor.status = "Unlinked “\(layer.name)”"
                }
            }
            if !layer.role.isBackground {
                Button("Delete", role: .destructive) {
                    document.delete(layer.id, undoManager: undoManager)
                    editor.checked.remove(layer.id)
                    if isSelected { editor.selectedLayer = document.layers.last?.id }
                    editor.status = "Deleted “\(layer.name)”"
                }
            }
        }
    }
}

// MARK: - History (Blueprint 037)

struct HistoryPanel: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var confirmKeep = false
    @State private var confirmPurge = false
    @State private var confirmDelete: Int?

    /// Selecting a row looks at that step (037: looking changes nothing).
    private var showing: Binding<UUID?> {
        Binding(get: { document.history.indices.contains(document.cursor) ? document.history[document.cursor].id : nil },
                set: { id in
                    guard let id, let index = document.history.firstIndex(where: { $0.id == id }),
                          index != document.cursor else { return }
                    document.look(at: index, undoManager: undoManager)
                    editor.status = index == document.history.count - 1
                        ? "Back to the newest step" : "Looking at “\(document.history[index].title)”"
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if document.historyBytes > LayerworksDocument.historyWarningBytes {
                Label("History holds over 250 MB. Purge History keeps the picture and frees the space.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .padding(8)
            }
            // The selected row IS the step on screen: Apple's own List selection, so a click,
            // a tap or the arrow keys look at a step.
            List(selection: showing) {
                // Newest step on top.
                ForEach(Array(document.history.enumerated()).reversed(), id: \.element.id) { index, step in
                    HStack {
                        Text(step.title).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(step.date, style: .time).foregroundStyle(.secondary).font(.callout)
                    }
                    .frame(minHeight: 44)
                    .tag(step.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("History step \(step.title)")
                    .accessibilityValue(index == document.cursor ? "showing" : "")
                    .contextMenu {
                        Button("Restore from This Step") {
                            document.restore(from: index, undoManager: undoManager)
                            editor.status = "Restored “\(step.title)” as a new step"
                        }
                        if index > 0 && index != document.cursor {
                            Button("Delete This Step", role: .destructive) { confirmDelete = index }
                        }
                    }
                }
            }
            HStack {
                if document.isLookingBack {
                    Button("Keep This Step") { confirmKeep = true }
                        .help("Keep the picture as it is here and delete the newer steps")
                }
                Spacer(minLength: 0)
                Button("Purge History…") { confirmPurge = true }
                    .disabled(document.history.count < 2)
                    .help("Keep the picture and erase the steps")
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 8)
        }
        .confirmationDialog("Delete the \(document.history.count - 1 - document.cursor) newer steps?",
                            isPresented: $confirmKeep, titleVisibility: .visible) {
            Button("Keep This Step", role: .destructive) {
                document.keep(at: document.cursor, undoManager: undoManager)
                editor.status = "Kept this step; newer steps deleted"
            }
        } message: { Text("The picture stays as it is now. This can't be undone.") }
        .confirmationDialog("Purge History?", isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Purge History", role: .destructive) {
                document.purgeHistory(undoManager: undoManager)
                editor.status = "History purged; the picture is kept"
            }
        } message: { Text("The picture is kept. Every History step is erased. This can't be undone.") }
        .confirmationDialog("Delete this step?", isPresented: Binding(get: { confirmDelete != nil },
                                                                      set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete This Step", role: .destructive) {
                if let i = confirmDelete { document.deleteStep(at: i, undoManager: undoManager) }
                editor.status = "Deleted a History step"
                confirmDelete = nil
            }
        }
    }
}
