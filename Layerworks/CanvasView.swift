//
//  CanvasView.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import UniformTypeIdentifiers

// REM: Blueprint 029 — the canvas. It scrolls both ways (drag to pan on iPhone and iPad, scroll
// on the Mac), pinches to zoom, and on the Mac Option-double-click zooms out and
// Shift-Option-double-click returns to 100%. A canvas smaller than the window sits centered.
// Until the layer model lands (step 3) the picture is the canvas's white ground.

struct CanvasView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var pinchBase: CGFloat?
    @State private var didFirstFit = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                CanvasPicture(document: document)
                    .frame(width: pixelWidth * editor.zoom, height: pixelHeight * editor.zoom)
                    .accessibilityIdentifier("Canvas picture")
                    .overlay { OnionSkin(document: document) }
                    .overlay { CanvasInteraction(document: document, editor: editor) }
                    .overlay { if editor.tool == .move { MoveOverlay(document: document, editor: editor) } }
                    .overlay { SelectMaskOverlay(document: document, editor: editor) }
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .padding(EditorState.margin)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                    .contentShape(Rectangle())
                    #if os(macOS)
                    .simultaneousGesture(optionDoubleClicks)
                    #endif
            }
            .scrollIndicators(.automatic)
            .simultaneousGesture(pinch)
            #if os(macOS)
            // 047: with the Selection tool and the canvas focused, Edit ▸ Copy / Paste / Delete act
            // on the picture; text fields keep their own Copy and Paste.
            .focusable(editor.tool == .selection)
            .onCopyCommand { editor.tool == .selection ? SelectionActions.providers(document, editor) : [] }
            .onPasteCommand(of: [.image, .png, .tiff]) { _ in
                if editor.tool == .selection { SelectionActions.paste(document, editor, undoManager) }
            }
            .onDeleteCommand { if editor.tool == .selection { SelectionActions.clear(document, editor, undoManager) } }
            #endif
            .background(Color.gray.opacity(0.15))
            .overlay { FloatingPreview(document: document) }
            .onAppear { update(viewport: proxy.size) }
            .onChange(of: proxy.size) { _, size in update(viewport: size) }
        }
        .onChange(of: document.manifest.canvasWidth) { _, _ in syncCanvasSize() }
        .onChange(of: document.manifest.canvasHeight) { _, _ in syncCanvasSize() }
    }

    private var pixelWidth: CGFloat { CGFloat(max(document.manifest.canvasWidth, 1)) }
    private var pixelHeight: CGFloat { CGFloat(max(document.manifest.canvasHeight, 1)) }

    private func syncCanvasSize() {
        editor.canvasSize = CGSize(width: pixelWidth, height: pixelHeight)
    }

    private func update(viewport: CGSize) {
        editor.viewport = viewport
        syncCanvasSize()
        // REM: the first real size fits the whole picture in view; after that the zoom is the
        // user's and a window resize never changes it.
        if !didFirstFit, viewport.width > 0, viewport.height > 0 {
            didFirstFit = true
            editor.fitWhole()
        }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBase ?? editor.zoom
                pinchBase = base
                editor.pinch(to: base * value.magnification)
            }
            .onEnded { _ in
                pinchBase = nil
                editor.pinchEnded()
            }
    }

    #if os(macOS)
    private var optionDoubleClicks: some Gesture {
        TapGesture(count: 2).modifiers([.option, .shift]).onEnded { editor.actualSize() }
            .exclusively(before: TapGesture(count: 2).modifiers(.option).onEnded { editor.zoomOut() })
    }
    #endif
}

/// The picture itself: the visible layers, bottom to top, over a checkerboard where it is
/// clear (blank Light / Dark floors are clear until the paint bucket fills them).
struct CanvasPicture: View {
    @ObservedObject var document: LayerworksDocument

    var body: some View {
        ZStack {
            Checkerboard()
            if let image = document.rendered {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .onAppear { if document.rendered == nil { document.render() } }
        .accessibilityElement()
            .accessibilityLabel("Canvas")
            .accessibilityValue("\(document.manifest.canvasWidth) by \(document.manifest.canvasHeight) pixels")
    }
}

/// The standard "this part is clear" pattern, drawn at a fixed screen size.
struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 8
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)),
                             with: .color(Color(white: 0.85)))
                    x += cell * 2
                }
                y += cell; row += 1
            }
        }
    }
}

/// Blueprint 029: the floating preview — a real-size copy of the picture (scaled down only when
/// it would not fit), draggable to any corner. Its switch is in the Zoom panel; it stays where
/// it was put across launches (his rule: every setting persists).
struct FloatingPreview: View {
    @ObservedObject var document: LayerworksDocument
    @AppStorage("lw.preview.visible") private var visible = true
    @AppStorage("lw.preview.corner") private var cornerRaw = Corner.bottomTrailing.rawValue
    @State private var drag: CGSize = .zero

    enum Corner: String, CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }
        var isTop: Bool { self == .topLeading || self == .topTrailing }
    }

    /// Longest side of the preview, in points.
    private static let maxSide: CGFloat = 160

    var body: some View {
        if visible {
            GeometryReader { proxy in
                let corner = Corner(rawValue: cornerRaw) ?? .bottomTrailing
                CanvasPicture(document: document)
                    .frame(width: size.width, height: size.height)
                    .border(.separator)
                    .shadow(radius: 4)
                    .padding(12)
                    .offset(drag)
                    .gesture(
                        DragGesture()
                            .onChanged { drag = $0.translation }
                            .onEnded { value in
                                cornerRaw = nearest(to: value, from: corner, in: proxy.size).rawValue
                                drag = .zero
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Floating preview")
                    .accessibilityHint("Drag to another corner")
                    .accessibilityActions {
                        ForEach(Corner.allCases, id: \.self) { c in
                            Button("Move to \(name(c))") { cornerRaw = c.rawValue }
                        }
                    }
                    // The preview alone takes drags; the rest of the canvas stays free for tools.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            }
        }
    }

    private var size: CGSize {
        let w = CGFloat(max(document.manifest.canvasWidth, 1))
        let h = CGFloat(max(document.manifest.canvasHeight, 1))
        let scale = min(1, Self.maxSide / max(w, h))
        return CGSize(width: w * scale, height: h * scale)
    }

    /// Where the preview's center landed decides the corner it snaps to.
    private func nearest(to value: DragGesture.Value, from corner: Corner, in area: CGSize) -> Corner {
        let startX = corner.isLeading ? size.width / 2 + 12 : area.width - size.width / 2 - 12
        let startY = corner.isTop ? size.height / 2 + 12 : area.height - size.height / 2 - 12
        let x = startX + value.translation.width
        let y = startY + value.translation.height
        switch (x < area.width / 2, y < area.height / 2) {
        case (true, true): return .topLeading
        case (false, true): return .topTrailing
        case (true, false): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    private func name(_ c: Corner) -> String {
        switch c {
        case .topLeading: "top left"
        case .topTrailing: "top right"
        case .bottomLeading: "bottom left"
        case .bottomTrailing: "bottom right"
        }
    }
}
