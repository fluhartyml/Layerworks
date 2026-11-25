//
//  LayerworksDocument.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import CoreGraphics

// REM: Blueprint 006 / 008 / 019 / 021 — Apple's standard document model. DocumentGroup +
// ReferenceFileDocument. A new document is "Untitled" in memory; the name and place come from
// the first Save panel (his word 2026-11-25: ImageProducerNNNN is superseded). After that,
// Apple's autosave and Versions take over.
//
// REM: Blueprint 023 + Walk Q1/Q3 (approved 2026-11-25) — Layerworks is a NEW app beside Image
// Producer, so it IMPORTS Image Producer's package type instead of exporting a second claim on
// the same extensions. New files are written as .imgprd; .picprod and .iconproj stay readable.
//
// REM: Blueprint 005 / 033 / 034 / 037 — History is the undo. Every edit is a History step
// holding the whole layer stack (pictures shared by hash). Apple's standard Edit ▸ Undo / Redo
// items are back, and every action they hold only MOVES THE HISTORY CURSOR. Nothing ever
// snapshots a store through UndoManager: the 2026-06-09 Shelf-Ready crash (whole-store SwiftData
// UndoManager, crashed on layer deletes) stays impossible here because there is no store.

extension UTType {
    /// Image Producer's project package (imgprd / picprod / iconproj). Imported, not exported.
    static let layerworksProject = UTType(importedAs: "com.nightgard.Image-Producer.project",
                                         conformingTo: .package)
}

/// What Save writes: the manifest plus the pictures it refers to.
nonisolated struct ProjectSnapshot: Sendable {
    var manifest: ProjectManifest
    var blobs: [String: Data]
}

final class LayerworksDocument: ReferenceFileDocument {
    typealias Snapshot = ProjectSnapshot

    nonisolated static var readableContentTypes: [UTType] { [.layerworksProject] }
    nonisolated static var writableContentTypes: [UTType] { [.layerworksProject] }

    @Published var manifest: ProjectManifest { didSet { if manifest.layers != oldValue.layers ||
        manifest.canvasWidth != oldValue.canvasWidth || manifest.canvasHeight != oldValue.canvasHeight { render() } } }
    /// Pictures by content hash.
    @Published private(set) var blobs: [String: Data]
    /// The picture as shown, redrawn when the layers change.
    @Published private(set) var rendered: CGImage?

    /// Warn past this much History (Blueprint 037: 250 MB).
    static let historyWarningBytes = 250 * 1024 * 1024

    /// A new picture. Size is set in the Canvas tool (Blueprint 022: no name ask, size only).
    init(width: Int = 1024, height: Int = 1024) {
        manifest = ProjectManifest(canvasWidth: width, canvasHeight: height)
        blobs = [:]
        render()
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        let (manifest, blobs) = try PackageLayout.read(configuration.file)
        _manifest = Published(initialValue: manifest)
        _blobs = Published(initialValue: blobs)
        _rendered = Published(initialValue: nil)
    }

    func snapshot(contentType: UTType) throws -> ProjectSnapshot {
        ProjectSnapshot(manifest: manifest, blobs: blobs)
    }

    nonisolated func fileWrapper(snapshot: ProjectSnapshot,
                                 configuration: WriteConfiguration) throws -> FileWrapper {
        try PackageLayout.wrapper(for: snapshot.manifest, blobs: snapshot.blobs)
    }

    // MARK: Reading

    var layers: [Layer] { manifest.layers }
    var history: [HistoryStep] { manifest.history }
    var cursor: Int { manifest.historyCursor }
    var isLookingBack: Bool { cursor < history.count - 1 }

    func layer(_ id: UUID?) -> Layer? { layers.first { $0.id == id } }

    /// Bytes of every picture History keeps.
    var historyBytes: Int {
        PackageLayout.referencedImages(manifest).reduce(0) { $0 + (blobs[$1]?.count ?? 0) }
    }

    func render() {
        rendered = Compositor.image(layers: manifest.layers, blobs: blobs,
                                    width: manifest.canvasWidth, height: manifest.canvasHeight,
                                    maxSide: 2048)
    }

    /// Stores a picture once and returns its key.
    func store(_ png: Data) -> String {
        let key = PackageLayout.hash(png)
        if blobs[key] == nil { blobs[key] = png }
        return key
    }

    // MARK: History

    /// Every edit comes through here: it becomes a new History step. Looking back and then
    /// editing drops the newer steps, as Undo then a new edit does in every Apple app.
    func commit(_ title: String, undoManager: UndoManager?, _ change: (inout [Layer]) -> Void) {
        var next = manifest.layers
        change(&next)
        guard next != manifest.layers else { return }
        let old = manifest.historyCursor
        var m = manifest
        m.history.removeSubrange((old + 1)...)
        m.history.append(HistoryStep(title: title, layers: next,
                                     canvasWidth: m.canvasWidth, canvasHeight: m.canvasHeight))
        m.historyCursor = m.history.count - 1
        m.layers = next
        manifest = m
        registerMove(back: old, title: title, undoManager: undoManager)
    }

    /// Look at a step (037: looking changes nothing — the newer steps stay). Undo goes back.
    func look(at index: Int, undoManager: UndoManager?) {
        let old = manifest.historyCursor
        guard moveCursor(to: index) else { return }
        registerMove(back: old, title: "Look at \(history[index].title)", undoManager: undoManager)
    }

    /// Keep This Step: the picture stays here and the newer steps are deleted (asked first).
    func keep(at index: Int, undoManager: UndoManager?) {
        guard history.indices.contains(index) else { return }
        var m = manifest
        m.history.removeSubrange((index + 1)...)
        m.historyCursor = index
        m.layers = m.history[index].layers
        manifest = m
        markEdited(undoManager)
    }

    /// Restore from This Step: a new step that puts that step's layers back. Nothing is lost.
    func restore(from index: Int, undoManager: UndoManager?) {
        guard history.indices.contains(index) else { return }
        let target = history[index].layers
        commit("Restore “\(history[index].title)”", undoManager: undoManager) { $0 = target }
    }

    /// Delete This Step. The Original and the step on screen stay.
    func deleteStep(at index: Int, undoManager: UndoManager?) {
        guard index > 0, index != cursor, history.indices.contains(index) else { return }
        var m = manifest
        m.history.remove(at: index)
        if index < m.historyCursor { m.historyCursor -= 1 }
        manifest = m
        markEdited(undoManager)
    }

    /// Purge History: keep the picture, erase the steps (asked first).
    func purgeHistory(undoManager: UndoManager?) {
        var m = manifest
        m.history = [HistoryStep(title: "Original", layers: m.layers,
                                 canvasWidth: m.canvasWidth, canvasHeight: m.canvasHeight)]
        m.historyCursor = 0
        manifest = m
        let used = PackageLayout.referencedImages(m)
        blobs = blobs.filter { used.contains($0.key) }
        markEdited(undoManager)
    }

    @discardableResult
    private func moveCursor(to index: Int) -> Bool {
        let index = min(max(index, 0), history.count - 1)
        guard index != manifest.historyCursor else { return false }
        var m = manifest
        m.historyCursor = index
        m.layers = m.history[index].layers
        m.canvasWidth = m.history[index].canvasWidth
        m.canvasHeight = m.history[index].canvasHeight
        manifest = m
        return true
    }

    /// The only thing Undo / Redo ever do: move the History cursor and register the way back.
    private func registerMove(back index: Int, title: String, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { doc in
            let here = doc.manifest.historyCursor
            doc.moveCursor(to: index)
            doc.registerMove(back: here, title: title, undoManager: undoManager)
        }
        undoManager.setActionName(title)
    }

    /// Keep / Delete Step / Purge rewrite History itself, so older Undo actions would point at
    /// steps that are gone: clear them. The no-op registration is how a ReferenceFileDocument
    /// learns it has changes to save.
    private func markEdited(_ undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { _ in }
        undoManager?.removeAllActions()
    }

    // MARK: Canvas and palette (Blueprint 043 / 044)

    /// A new canvas size is a History step (the step keeps its size, so Undo puts it back).
    /// Every picture keeps its own pixel size and stays centered: nothing is stretched.
    func resizeCanvas(width: Int, height: Int, undoManager: UndoManager?) {
        let width = min(max(width, 1), 16_384), height = min(max(height, 1), 16_384)
        guard width != manifest.canvasWidth || height != manifest.canvasHeight else { return }
        let oldW = manifest.canvasWidth, oldH = manifest.canvasHeight
        let dx = (width - oldW) / 2, dy = (height - oldH) / 2
        var next = manifest.layers
        for i in next.indices where next[i].image != nil {
            let f = next[i].frame ?? PixelRect(x: 0, y: 0, width: oldW, height: oldH)
            next[i].frame = PixelRect(x: f.x + dx, y: f.y + dy, width: f.width, height: f.height)
        }
        let old = manifest.historyCursor
        var m = manifest
        m.history.removeSubrange((old + 1)...)
        m.canvasWidth = width
        m.canvasHeight = height
        m.history.append(HistoryStep(title: "Canvas Size", layers: next, canvasWidth: width, canvasHeight: height))
        m.historyCursor = m.history.count - 1
        m.layers = next
        manifest = m
        registerMove(back: old, title: "Canvas Size", undoManager: undoManager)
    }

    /// Resolution and the palette are document settings, not pictures, so they are not History
    /// steps; Undo still takes them back (one plain inverse, never a store snapshot).
    func setPPI(_ ppi: Int, undoManager: UndoManager?) {
        let ppi = min(max(ppi, 36), 2400)
        let old = manifest.ppi
        guard ppi != old else { return }
        manifest.ppi = ppi
        undoManager?.registerUndo(withTarget: self) { $0.setPPI(old, undoManager: undoManager) }
        undoManager?.setActionName("Resolution")
    }

    func setPalette(_ colors: [String], undoManager: UndoManager?) {
        let colors = Palette.normalized(colors)
        let old = manifest.palette
        guard colors != old else { return }
        manifest.palette = colors
        undoManager?.registerUndo(withTarget: self) { $0.setPalette(old, undoManager: undoManager) }
        undoManager?.setActionName("Palette")
    }

    // MARK: Layer edits (Blueprint 036)

    /// + adds a new, transparent layer above the selected one.
    func addLayer(above id: UUID?, undoManager: UndoManager?) -> UUID {
        let used = Set(layers.map(\.name))
        var n = layers.filter { $0.role == .content }.count + 1
        while used.contains("Layer \(n)") { n += 1 }
        let new = Layer(name: "Layer \(n)", role: .content)
        commit("Add Layer", undoManager: undoManager) { list in
            let at = list.firstIndex { $0.id == id }.map { $0 + 1 } ?? list.count
            list.insert(new, at: at)
        }
        return new.id
    }

    func rename(_ id: UUID, to name: String, undoManager: UndoManager?) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        commit("Rename Layer", undoManager: undoManager) { list in
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].name = name }
        }
    }

    func duplicate(_ id: UUID, undoManager: UndoManager?) -> UUID? {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = layers[i]
        copy.id = UUID()
        copy.name += " copy"
        // A duplicated background is ordinary content: the Light / Dark floors stay one each.
        copy.role = .content
        commit("Duplicate Layer", undoManager: undoManager) { $0.insert(copy, at: i + 1) }
        return copy.id
    }

    /// Light and Dark cannot be deleted: an Icon Set export needs both floors.
    func delete(_ id: UUID, undoManager: UndoManager?) {
        guard let l = layer(id), !l.role.isBackground else { return }
        commit("Delete Layer", undoManager: undoManager) { $0.removeAll { $0.id == id } }
    }

    func setVisible(_ id: UUID, _ visible: Bool, undoManager: UndoManager?) {
        commit(visible ? "Show Layer" : "Hide Layer", undoManager: undoManager) { list in
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].isVisible = visible }
        }
    }

    /// Reorder, in stack order (index 0 = bottom).
    func move(from source: IndexSet, to destination: Int, undoManager: UndoManager?) {
        commit("Move Layer", undoManager: undoManager) { $0.move(fromOffsets: source, toOffset: destination) }
    }

    /// Merge: the checked layers become one new layer above the top one; the originals are
    /// kept, hidden (036 — nothing is destroyed).
    func merge(_ ids: Set<UUID>, undoManager: UndoManager?) -> UUID? {
        let picked = layers.filter { ids.contains($0.id) }
        guard picked.count >= 2,
              let top = layers.lastIndex(where: { ids.contains($0.id) }),
              let png = Compositor.png(layers: picked.map { var l = $0; l.isVisible = true; return l },
                                       blobs: blobs, width: manifest.canvasWidth,
                                       height: manifest.canvasHeight) else { return nil }
        let merged = Layer(name: "Merged", role: .content, image: store(png))
        commit("Merge Layers", undoManager: undoManager) { list in
            for i in list.indices where ids.contains(list[i].id) { list[i].isVisible = false }
            list.insert(merged, at: top + 1)
        }
        return merged.id
    }

    /// Link: the checked layers move and resize together; each stays editable.
    func link(_ ids: Set<UUID>, undoManager: UndoManager?) {
        guard ids.count >= 2 else { return }
        let group = UUID()
        commit("Link Layers", undoManager: undoManager) { list in
            for i in list.indices where ids.contains(list[i].id) { list[i].linkGroup = group }
        }
    }

    func unlink(_ id: UUID, undoManager: UndoManager?) {
        commit("Unlink Layer", undoManager: undoManager) { list in
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].linkGroup = nil }
        }
    }
}
