//
//  SelectMaskLasso.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import CoreText
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// REM: Build step 4d2 — Selection (047), Mask (048), Magic Lasso (056).
// 047: marching ants; Delete clears inside; ⌘C copies the selection; ⌘V pastes as a layer — on the
//      system pasteboard. On the Mac the canvas answers Copy / Paste / Delete when it has focus, so
//      text fields keep their own; the tool panel has the same three as buttons.
// 048: the mask marks what to keep; outside goes dim; it never changes the artwork; exports keep
//      only what is inside (export = step 6). Shapes: rectangle, oval, polygon, star, a typed
//      character, or a symbol.
// 056: hover outlines the region in red; each click clears the connected area; all clears go on ONE
//      new layer, and History steps back through them one at a time. Original hidden.

nonisolated enum MaskShape: String, Codable, CaseIterable, Sendable {
    case rectangle = "Rectangle", oval = "Oval", polygon = "Polygon", star = "Star"
    case character = "Character", symbol = "Symbol"
}

nonisolated struct MaskSpec: Codable, Equatable, Sendable {
    var shape: MaskShape
    var rect: PixelRect
    /// The typed character, or the SF Symbol name.
    var text: String?
}

extension LayerworksDocument {
    /// The mask is a document setting, not a picture: Undo takes it back without a History step.
    func setMask(_ mask: MaskSpec?, undoManager: UndoManager?) {
        let old = manifest.mask
        guard old != mask else { return }
        manifest.mask = mask
        undoManager?.registerUndo(withTarget: self) { $0.setMask(old, undoManager: undoManager) }
        undoManager?.setActionName(mask == nil ? "Remove Mask" : "Mask")
    }

    /// Replaces a layer's picture in place as one History step (056: the Magic Lasso's later clears).
    func replacePicture(_ id: UUID, with bitmap: Bitmap, title: String, undoManager: UndoManager?) {
        guard let png = bitmap.png() else { return }
        let key = store(png)
        commit(title, undoManager: undoManager) { list in
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].image = key; list[i].frame = nil }
        }
    }
}

/// Shape outlines in a unit square, for the mask overlay.
enum MaskPath {
    static func path(_ shape: MaskShape, in r: CGRect) -> Path {
        switch shape {
        case .rectangle, .character, .symbol: return Path(r)
        case .oval: return Path(ellipseIn: r)
        case .polygon: return polygon(sides: 6, in: r, inner: nil)
        case .star: return polygon(sides: 5, in: r, inner: 0.45)
        }
    }

    private static func polygon(sides: Int, in r: CGRect, inner: CGFloat?) -> Path {
        var p = Path()
        let n = inner == nil ? sides : sides * 2
        for k in 0..<n {
            let a = CGFloat(k) / CGFloat(n) * 2 * .pi - .pi / 2
            let f: CGFloat = (inner != nil && k % 2 == 1) ? inner! : 1
            let pt = CGPoint(x: r.midX + cos(a) * r.width / 2 * f, y: r.midY + sin(a) * r.height / 2 * f)
            k == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Inspector panels

struct SelectionToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Section {
            Text("Drag on the picture to select.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Select All") {
                    editor.selection = PixelRect(x: 0, y: 0, width: document.manifest.canvasWidth,
                                                 height: document.manifest.canvasHeight)
                    editor.status = "Selected all"
                }
                Spacer()
                Button("Deselect") { editor.selection = nil; editor.status = "Deselected" }
                    .disabled(editor.selection == nil)
            }
            .buttonStyle(.borderless)
            HStack {
                Button("Copy") { SelectionActions.copy(document, editor) }
                Spacer()
                Button("Paste") { SelectionActions.paste(document, editor, undoManager) }
                Spacer()
                Button("Clear") { SelectionActions.clear(document, editor, undoManager) }
            }
            .buttonStyle(.borderless)
            #if os(macOS)
            Text("With the picture clicked, ⌘C, ⌘V and Delete work too.").font(.callout).foregroundStyle(.secondary)
            #endif
        } header: { Text("Selection") }
    }
}

enum SelectionActions {
    /// The selected part of the selected layer (or the whole layer when nothing is selected).
    static func picture(_ document: LayerworksDocument, _ editor: EditorState) -> CGImage? {
        guard let id = editor.selectedLayer, let b = document.bitmap(of: id), let full = b.cgImage() else { return nil }
        guard let s = editor.selection else { return full }
        return full.cropping(to: CGRect(x: s.x, y: s.y, width: s.width, height: s.height))
    }

    #if canImport(AppKit)
    /// For the Mac's Edit ▸ Copy when the canvas has focus.
    static func providers(_ document: LayerworksDocument, _ editor: EditorState) -> [NSItemProvider] {
        guard let image = picture(document, editor) else { return [] }
        editor.status = "Copied \(image.width) × \(image.height)"
        return [NSItemProvider(object: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))]
    }
    #endif

    static func copy(_ document: LayerworksDocument, _ editor: EditorState) {
        guard let image = picture(document, editor) else { editor.status = "Nothing to copy"; return }
        #if canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))])
        #else
        UIPasteboard.general.image = UIImage(cgImage: image)
        #endif
        editor.status = "Copied \(image.width) × \(image.height)"
    }

    static func paste(_ document: LayerworksDocument, _ editor: EditorState, _ undo: UndoManager?) {
        #if canImport(AppKit)
        let image = (NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first
            .flatMap { img -> CGImage? in var r = CGRect(origin: .zero, size: img.size); return img.cgImage(forProposedRect: &r, context: nil, hints: nil) }
        #else
        let image = UIPasteboard.general.image?.cgImage
        #endif
        guard let image else { editor.status = "There's no picture to paste"; return }
        if let id = document.addPicture(image, name: "Pasted", above: editor.selectedLayer, replacing: false, undoManager: undo) {
            editor.selectedLayer = id
            editor.status = "Pasted as a new layer"
        }
    }

    /// Delete clears inside the selection (on a new layer, original hidden).
    static func clear(_ document: LayerworksDocument, _ editor: EditorState, _ undo: UndoManager?) {
        guard let id = editor.selectedLayer, let s = editor.selection, var b = document.bitmap(of: id) else {
            editor.status = "Select an area first"; return
        }
        b.draw { ctx, rect in
            ctx.clear(CGRect(x: s.x, y: Int(rect.height) - s.y - s.height, width: s.width, height: s.height))
        }
        if let new = document.fork(id, into: b, label: "Clear", title: "Clear Selection", undoManager: undo) {
            editor.selectedLayer = new
            editor.status = "Cleared the selection"
        }
    }
}

struct MaskToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.mask.shape") private var shape = MaskShape.rectangle
    @AppStorage("lw.mask.text") private var text = "A"

    var body: some View {
        Section {
            Picker("Shape", selection: $shape) {
                ForEach(MaskShape.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if shape == .character || shape == .symbol {
                TextField(shape == .character ? "Character" : "Symbol name", text: $text)
                    .accessibilityLabel(shape == .character ? "Character" : "Symbol name")
            }
            if let m = document.manifest.mask {
                Button("Use This Shape") {
                    document.setMask(MaskSpec(shape: shape, rect: m.rect, text: text), undoManager: undoManager)
                    editor.status = "Mask is a \(shape.rawValue.lowercased())"
                }
                MaskRectFields(document: document)
                Button("Remove Mask", role: .destructive) {
                    document.setMask(nil, undoManager: undoManager)
                    editor.status = "Mask removed"
                }
            } else {
                Button("Add Mask") {
                    let w = document.manifest.canvasWidth, h = document.manifest.canvasHeight
                    let r = PixelRect(x: w / 8, y: h / 8, width: w * 3 / 4, height: h * 3 / 4)
                    document.setMask(MaskSpec(shape: shape, rect: r, text: text), undoManager: undoManager)
                    editor.status = "Mask added"
                }
            }
            Text("The mask marks what to keep; outside goes dim. It never changes the artwork, and exports keep only what is inside.")
                .font(.callout).foregroundStyle(.secondary)
        } header: { Text("Mask") }
    }
}

struct MaskRectFields: View {
    @ObservedObject var document: LayerworksDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let m = document.manifest.mask {
            Grid(alignment: .leading) {
                GridRow { field("X", m.rect.x) { $0.x = $1 }; field("Y", m.rect.y) { $0.y = $1 } }
                GridRow { field("W", m.rect.width) { $0.width = max(1, $1) }; field("H", m.rect.height) { $0.height = max(1, $1) } }
            }
        }
    }

    private func field(_ name: String, _ value: Int, set: @escaping (inout PixelRect, Int) -> Void) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            TextField(name, value: Binding(get: { value }, set: { v in
                guard var m = document.manifest.mask else { return }
                set(&m.rect, v)
                document.setMask(m, undoManager: undoManager)
            }), format: .number)
            .accessibilityLabel("Mask " + (name == "W" ? "width" : name == "H" ? "height" : name))
        }
    }
}

struct LassoToolView: View {
    @AppStorage("lw.lasso.tolerance") private var tolerance = 0.1

    var body: some View {
        Section {
            HStack {
                Text("Tolerance")
                Slider(value: $tolerance, in: 0...0.5).accessibilityLabel("Tolerance")
                Text("\(Int(tolerance * 100))%").monospacedDigit().frame(width: 44)
            }
            Text("Point at an area to see it outlined in red; click or tap to clear it — sky, then water, then rock. All clears go on one new layer, and Undo steps back one clear at a time.")
                .font(.callout).foregroundStyle(.secondary)
        } header: { Text("Magic Lasso") }
    }
}

// MARK: - Canvas overlays

/// Marching ants for the selection, the dimmed outside of the mask, and the drag that draws a
/// selection or moves / resizes the mask.
struct SelectMaskOverlay: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var maskStart: (PixelRect, Int?)?

    var body: some View {
        let z = editor.zoom
        ZStack(alignment: .topLeading) {
            if let m = document.manifest.mask {
                let r = CGRect(x: CGFloat(m.rect.x) * z, y: CGFloat(m.rect.y) * z,
                               width: CGFloat(m.rect.width) * z, height: CGFloat(m.rect.height) * z)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.45)
                    keepShape(m, r).blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)
                if editor.tool == .mask {
                    ForEach(0..<4, id: \.self) { c in
                        Circle().fill(Color.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                            .frame(width: 14, height: 14)
                            .offset(x: (c % 2 == 0 ? r.minX : r.maxX) - 7, y: (c < 2 ? r.minY : r.maxY) - 7)
                            .allowsHitTesting(false)
                    }
                }
            }
            if let s = editor.selection {
                TimelineView(.animation(minimumInterval: 0.1)) { t in
                    let phase = CGFloat(t.date.timeIntervalSinceReferenceDate * 20).truncatingRemainder(dividingBy: 12)
                    Path(CGRect(x: CGFloat(s.x) * z, y: CGFloat(s.y) * z, width: CGFloat(s.width) * z, height: CGFloat(s.height) * z))
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6], dashPhase: phase))
                        .foregroundStyle(Color.primary)
                }
                .allowsHitTesting(false)
            }
            if editor.tool == .selection || editor.tool == .mask {
                Color.clear.contentShape(Rectangle()).gesture(drag)
            }
        }
    }

    @ViewBuilder private func keepShape(_ m: MaskSpec, _ r: CGRect) -> some View {
        switch m.shape {
        case .character:
            Text(m.text?.first.map(String.init) ?? "A")
                .font(.system(size: max(r.height, 1) * 0.9, weight: .bold))
                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        case .symbol:
            Image(systemName: ContentRender.symbolExists(m.text ?? "") ? (m.text ?? "star.fill") : "star.fill")
                .resizable().scaledToFit()
                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        default:
            MaskPath.path(m.shape, in: r).fill(Color.black)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let z = editor.zoom
                let a = CGPoint(x: v.startLocation.x / z, y: v.startLocation.y / z)
                let b = CGPoint(x: v.location.x / z, y: v.location.y / z)
                if editor.tool == .selection {
                    editor.selection = PixelRect(x: Int(min(a.x, b.x)), y: Int(min(a.y, b.y)),
                                                 width: max(1, Int(abs(b.x - a.x))), height: max(1, Int(abs(b.y - a.y))))
                } else if var m = document.manifest.mask {
                    if maskStart == nil {
                        let r = m.rect
                        let corners = [(r.x, r.y), (r.x + r.width, r.y), (r.x, r.y + r.height), (r.x + r.width, r.y + r.height)]
                        maskStart = (r, corners.firstIndex { hypot(CGFloat($0.0) - a.x, CGFloat($0.1) - a.y) * z < 14 })
                    }
                    guard let (s, corner) = maskStart else { return }
                    let dx = Int(b.x - a.x), dy = Int(b.y - a.y)
                    var n = s
                    switch corner {
                    case nil: n.x += dx; n.y += dy
                    case 0: n.x += dx; n.y += dy; n.width -= dx; n.height -= dy
                    case 1: n.y += dy; n.width += dx; n.height -= dy
                    case 2: n.x += dx; n.width -= dx; n.height += dy
                    default: n.width += dx; n.height += dy
                    }
                    n.width = max(1, n.width); n.height = max(1, n.height)
                    m.rect = n
                    document.manifest.mask = m   // live; one Undo step is recorded at the end
                }
            }
            .onEnded { _ in
                if editor.tool == .selection, let s = editor.selection {
                    editor.status = "Selected \(s.width) × \(s.height)"
                } else if let (start, _) = maskStart, var m = document.manifest.mask {
                    let end = m.rect
                    m.rect = start
                    document.manifest.mask = m
                    m.rect = end
                    document.setMask(m, undoManager: undoManager)
                    editor.status = "Mask moved"
                }
                maskStart = nil
            }
    }
}
