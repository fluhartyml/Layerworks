//
//  MoveTool.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI

// REM: Build step 4d1 — Move / Transform and Crop (045) with centerlines (046).
// 045: "Drag inside the dashed box to move; drag a corner to resize. Scale and Rotation sliders.
// Fit and Fill. Leaving the tool commits; the original is kept underneath, hidden. Crop lives
// here: choose a shape, adjust the box, Apply Crop." Typed X / Y / W / H and nudge buttons do the
// same by keyboard (his rule: every app is drivable by keyboard and VoiceOver).
// 045 also says: do not fake an on-canvas rotate handle — rotation is the slider.
// 046 (his words 2026-10-31: "it would be nice if there we centerlines that appeared to help you
// manually ilign the center"): canvas centerlines show only while moving or cropping.

enum CropShape: String, CaseIterable { case rectangle = "Rectangle", oval = "Oval" }

/// The unsaved move or crop for the selected layer.
struct MoveDraft: Equatable {
    var layer: UUID
    var frame: PixelRect
    var rotation: Double
    var cropping = false
    var crop: PixelRect
}

extension LayerworksDocument {
    /// Where a layer sits: its frame, or the whole canvas.
    func frame(of layer: Layer) -> PixelRect {
        layer.frame ?? PixelRect(x: 0, y: 0, width: manifest.canvasWidth, height: manifest.canvasHeight)
    }

    /// Move / Transform result (045): a new layer with the new place, size and turn above the
    /// original, which is hidden. Linked layers (036) move and resize with it.
    func transform(_ id: UUID, to frame: PixelRect, rotation: Double, undoManager: UndoManager?) -> UUID? {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return nil }
        let old = self.frame(of: layers[i])
        let sx = Double(frame.width) / Double(max(old.width, 1)), sy = Double(frame.height) / Double(max(old.height, 1))
        func moved(_ f: PixelRect) -> PixelRect {
            PixelRect(x: frame.x + Int(Double(f.x - old.x) * sx), y: frame.y + Int(Double(f.y - old.y) * sy),
                      width: max(1, Int(Double(f.width) * sx)), height: max(1, Int(Double(f.height) * sy)))
        }
        let group = layers[i].linkGroup
        var newID: UUID?
        commit("Move", undoManager: undoManager) { list in
            // Walk top to bottom so inserting above each layer keeps the indexes ahead valid.
            for j in list.indices.reversed() where list[j].id == id || (group != nil && list[j].linkGroup == group) {
                var copy = list[j]
                copy.id = UUID()
                copy.frame = list[j].id == id ? frame : moved(self.frame(of: list[j]))
                copy.rotation = list[j].id == id ? (rotation == 0 ? nil : rotation) : list[j].rotation
                copy.role = .content
                if list[j].id == id { newID = copy.id }
                if !list[j].role.isBackground { list[j].isVisible = false }
                list.insert(copy, at: j + 1)
            }
        }
        return newID
    }

    /// Apply Crop (045): the picture inside the box (rectangle or oval) on a new layer, original
    /// hidden.
    func crop(_ id: UUID, to box: PixelRect, shape: CropShape, undoManager: UndoManager?) -> UUID? {
        guard let source = bitmap(of: id) else { return nil }
        var b = Bitmap(width: source.width, height: source.height)
        guard let picture = source.cgImage() else { return nil }
        b.draw { ctx, rect in
            let clip = CGRect(x: CGFloat(box.x), y: rect.height - CGFloat(box.y + box.height),
                              width: CGFloat(box.width), height: CGFloat(box.height))
            if shape == .oval { ctx.addEllipse(in: clip) } else { ctx.addRect(clip) }
            ctx.clip()
            ctx.draw(picture, in: rect)
        }
        return fork(id, into: b, label: "Crop", title: "Crop", undoManager: undoManager)
    }
}

extension EditorState {
    /// Starts (or keeps) a draft for the selected layer.
    func draft(for document: LayerworksDocument) -> MoveDraft? {
        guard let id = selectedLayer, let layer = document.layer(id) else { return nil }
        if let d = moveDraft, d.layer == id { return d }
        let f = document.frame(of: layer)
        return MoveDraft(layer: id, frame: f, rotation: layer.rotation ?? 0, crop: f)
    }

    /// Leaving the tool commits (045). Returns true when something changed.
    @discardableResult
    func commitMove(_ document: LayerworksDocument, undoManager: UndoManager?) -> Bool {
        guard let d = moveDraft, let layer = document.layer(d.layer) else { moveDraft = nil; return false }
        moveDraft = nil
        guard d.frame != document.frame(of: layer) || d.rotation != (layer.rotation ?? 0) else { return false }
        if let id = document.transform(d.layer, to: d.frame, rotation: d.rotation, undoManager: undoManager) {
            selectedLayer = id
            status = "Moved “\(layer.name)” to \(d.frame.x), \(d.frame.y) · \(d.frame.width) × \(d.frame.height)"
        }
        return true
    }
}

struct MoveToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.crop.shape") private var shape = CropShape.rectangle
    @State private var scale = 1.0

    var body: some View {
        if let d = editor.draft(for: document) {
            Section {
                Picker("Mode", selection: Binding(get: { d.cropping }, set: { c in update { $0.cropping = c } })) {
                    Text("Move").tag(false)
                    Text("Crop").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Move or Crop")
                rectFields(d.cropping ? d.crop : d.frame) { r in update { if $0.cropping { $0.crop = r } else { $0.frame = r } } }
                HStack(spacing: 4) {
                    nudge("Left", "arrow.left", dx: -1, dy: 0)
                    nudge("Right", "arrow.right", dx: 1, dy: 0)
                    nudge("Up", "arrow.up", dx: 0, dy: -1)
                    nudge("Down", "arrow.down", dx: 0, dy: 1)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
            } header: { Text(d.cropping ? "Crop box" : "Place and size") }

            if d.cropping {
                Section {
                    Picker("Shape", selection: $shape) {
                        ForEach(CropShape.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Button("Apply Crop") {
                        if let id = document.crop(d.layer, to: d.crop, shape: shape, undoManager: undoManager) {
                            editor.moveDraft = nil
                            editor.selectedLayer = id
                            editor.status = "Cropped to \(d.crop.width) × \(d.crop.height)"
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        Text("Scale")
                        Slider(value: $scale, in: 0.1...4) { editing in if !editing { applyScale() } }
                            .accessibilityLabel("Scale")
                        Text("\(Int(scale * 100))%").monospacedDigit().frame(width: 52)
                    }
                    HStack {
                        Text("Rotation")
                        Slider(value: Binding(get: { d.rotation }, set: { r in update { $0.rotation = r.rounded() } }),
                               in: -180...180)
                            .accessibilityLabel("Rotation")
                        Text("\(Int(d.rotation))°").monospacedDigit().frame(width: 52)
                    }
                    HStack {
                        Button("Fit") { fit(cover: false) }.help("Fit inside the canvas")
                        Button("Fill") { fit(cover: true) }.help("Cover the canvas")
                        Spacer()
                        Button("Done") { editor.commitMove(document, undoManager: undoManager) }
                            .keyboardShortcut(.defaultAction)
                            .disabled(editor.moveDraft == nil)
                    }
                    // Several buttons in one Form row need their own style, or the row takes the click.
                    .buttonStyle(.borderless)
                    Text("Drag inside the box to move, a corner to resize. Leaving the tool keeps the change; the original stays underneath, hidden.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        } else {
            Section { Text("Select a layer to move.").foregroundStyle(.secondary) }
        }
    }

    private func update(_ change: (inout MoveDraft) -> Void) {
        guard var d = editor.draft(for: document) else { return }
        change(&d)
        editor.moveDraft = d
    }

    private func rectFields(_ r: PixelRect, set: @escaping (PixelRect) -> Void) -> some View {
        Grid(alignment: .leading) {
            GridRow {
                field("X", r.x) { var n = r; n.x = $0; set(n) }
                field("Y", r.y) { var n = r; n.y = $0; set(n) }
            }
            GridRow {
                field("W", r.width) { var n = r; n.width = max(1, $0); set(n) }
                field("H", r.height) { var n = r; n.height = max(1, $0); set(n) }
            }
        }
    }

    private func field(_ name: String, _ value: Int, set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            TextField(name, value: Binding(get: { value }, set: set), format: .number)
                .accessibilityLabel(name == "W" ? "Width" : name == "H" ? "Height" : name)
        }
    }

    private func nudge(_ name: String, _ symbol: String, dx: Int, dy: Int) -> some View {
        Button { update { d in
            if d.cropping { d.crop.x += dx; d.crop.y += dy } else { d.frame.x += dx; d.frame.y += dy }
        } } label: { Label("Nudge \(name)", systemImage: symbol).frame(minWidth: 32, minHeight: 32) }
    }

    private func applyScale() {
        guard let d = editor.draft(for: document), let layer = document.layer(d.layer) else { return }
        let base = document.frame(of: layer)
        let w = max(1, Int(Double(base.width) * scale)), h = max(1, Int(Double(base.height) * scale))
        update { $0.frame = PixelRect(x: base.x + (base.width - w) / 2, y: base.y + (base.height - h) / 2, width: w, height: h) }
    }

    private func fit(cover: Bool) {
        guard let d = editor.draft(for: document) else { return }
        let cw = Double(document.manifest.canvasWidth), ch = Double(document.manifest.canvasHeight)
        let sx = cw / Double(max(d.frame.width, 1)), sy = ch / Double(max(d.frame.height, 1))
        let s = cover ? max(sx, sy) : min(sx, sy)
        let w = Int(Double(d.frame.width) * s), h = Int(Double(d.frame.height) * s)
        update { $0.frame = PixelRect(x: (Int(cw) - w) / 2, y: (Int(ch) - h) / 2, width: w, height: h) }
    }
}

/// The dashed box, corner grabbers and (while dragging) the centerlines, over the canvas.
struct MoveOverlay: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var start: (frame: PixelRect, corner: Int?)?
    @State private var dragging = false

    var body: some View {
        let z = editor.zoom
        ZStack(alignment: .topLeading) {
            if let d = editor.draft(for: document) {
                let r = d.cropping ? d.crop : d.frame
                let box = CGRect(x: CGFloat(r.x) * z, y: CGFloat(r.y) * z, width: CGFloat(r.width) * z, height: CGFloat(r.height) * z)
                if dragging {
                    Path { p in
                        let cx = CGFloat(document.manifest.canvasWidth) * z / 2, cy = CGFloat(document.manifest.canvasHeight) * z / 2
                        p.move(to: CGPoint(x: cx, y: 0)); p.addLine(to: CGPoint(x: cx, y: CGFloat(document.manifest.canvasHeight) * z))
                        p.move(to: CGPoint(x: 0, y: cy)); p.addLine(to: CGPoint(x: CGFloat(document.manifest.canvasWidth) * z, y: cy))
                    }
                    .stroke(Color.cyan, lineWidth: 1)
                }
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(d.cropping ? Color.orange : Color.accentColor)
                    .rotationEffect(.degrees(d.cropping ? 0 : d.rotation))
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                ForEach(0..<4, id: \.self) { c in
                    Rectangle().fill(Color.white).overlay(Rectangle().stroke(Color.accentColor))
                        .frame(width: 12, height: 12)
                        .offset(x: (c % 2 == 0 ? box.minX : box.maxX) - 6, y: (c < 2 ? box.minY : box.maxY) - 6)
                }
            }
            Color.clear.contentShape(Rectangle()).gesture(drag)
        }
        .onChange(of: editor.selectedLayer) { old, _ in
            if editor.moveDraft?.layer == old { editor.commitMove(document, undoManager: undoManager) }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                guard let d = editor.draft(for: document) else { return }
                let z = editor.zoom
                let r = d.cropping ? d.crop : d.frame
                if start == nil {
                    // A grab within 12 pt of a corner resizes; anywhere else moves.
                    let corners = [(r.x, r.y), (r.x + r.width, r.y), (r.x, r.y + r.height), (r.x + r.width, r.y + r.height)]
                    let hit = corners.firstIndex { hypot(CGFloat($0.0) * z - v.startLocation.x, CGFloat($0.1) * z - v.startLocation.y) < 12 }
                    start = (r, hit)
                    dragging = true
                }
                guard let s = start else { return }
                let dx = Int(v.translation.width / z), dy = Int(v.translation.height / z)
                var n = s.frame
                switch s.corner {
                case nil: n.x += dx; n.y += dy
                case 0: n.x += dx; n.y += dy; n.width -= dx; n.height -= dy
                case 1: n.y += dy; n.width += dx; n.height -= dy
                case 2: n.x += dx; n.width -= dx; n.height += dy
                default: n.width += dx; n.height += dy
                }
                n.width = max(1, n.width); n.height = max(1, n.height)
                var nd = d
                if d.cropping { nd.crop = n } else { nd.frame = n }
                editor.moveDraft = nd
            }
            .onEnded { _ in start = nil; dragging = false }
    }
}
