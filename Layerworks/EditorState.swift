//
//  EditorState.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import Combine

// REM: Blueprint 029 (build step 2) — one window's view state: zoom, focus mode and the status
// line. It is NOT document data: zooming never dirties the file and never enters History.
// The menu commands reach the front window's copy through .focusedSceneObject.

final class EditorState: ObservableObject {
    /// 1.0 = 100%: one canvas pixel per point.
    @Published var zoom: CGFloat = 1
    /// Canvas focus mode (Blueprint 029 "full-screen canvas"): hides the zoom panel, status
    /// line and inspector so the canvas gets the whole window.
    @Published var focusMode = false
    /// Status line along the bottom reports every action (Blueprint 029).
    @Published var status = "Ready"
    /// The selected layer (036: select the layer first, then use the tool).
    @Published var selectedLayer: UUID?
    /// Layers checked for Merge / Link — never the selection.
    @Published var checked: Set<UUID> = []
    /// The chosen tool. Every picture opens on the Canvas tool (043).
    @Published var tool: Tool = .canvas
    /// The palette swatch in use (044).
    @Published var colorIndex = 0
    /// The Magic Eraser's color, picked from the picture (051 / 052).
    @Published var magicColor: String?
    /// Purge History asks first, from the History tab or File ▸ Purge History….
    @Published var askPurge = false
    /// Move / Crop in progress (045); committed when the tool is left.
    @Published var moveDraft: MoveDraft?
    /// The selection (047), in canvas pixels. nil = nothing selected.
    @Published var selection: PixelRect?
    /// The layer this run of Magic Lasso clears is collecting on (056).
    var lassoLayer: UUID?
    /// The adjustment the Adjust panel shows (059); the Image and Filter menus set it.
    @Published var adjustment: Adjustment = .levels
    /// The Lightbox is playing (058).
    @Published var playing = false

    func optimize(_ document: LayerworksDocument, undoManager: UndoManager?) {
        let freed = document.optimizeHistory(undoManager: undoManager)
        status = freed > 0
            ? "Optimized History: freed \(ByteCountFormatter.string(fromByteCount: Int64(freed), countStyle: .file)), every step kept"
            : "History is already as small as it can be"
    }
    /// Size of the visible canvas area, kept current by the canvas view; Fit uses it.
    var viewport: CGSize = .zero
    /// Canvas size in pixels, kept current by the editor.
    var canvasSize: CGSize = CGSize(width: 1024, height: 1024)

    static let minZoom: CGFloat = 1.0 / 16
    static let maxZoom: CGFloat = 32
    /// Even steps both ways from 100% (his rule: rest value at center, even steps).
    static let steps: [CGFloat] = [1.0 / 16, 1.0 / 8, 1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3,
                                   1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32]

    /// The zoom level as people read it: "100%", "33%", "1600%".
    var zoomText: String { "\(Int((zoom * 100).rounded()))%" }

    func zoomIn() {
        set(Self.steps.first { $0 > zoom + 0.0001 } ?? Self.maxZoom, verb: "Zoomed in")
    }

    func zoomOut() {
        set(Self.steps.last { $0 < zoom - 0.0001 } ?? Self.minZoom, verb: "Zoomed out")
    }

    func actualSize() { set(1, verb: "Zoomed") }

    /// Blueprint 029 "fit width": the canvas width fills the visible area.
    func fitWidth() {
        guard viewport.width > 0, canvasSize.width > 0 else { return }
        set((viewport.width - 2 * Self.margin) / canvasSize.width, verb: "Fit width")
    }

    /// Whole canvas in view; used when a picture first opens.
    func fitWhole() {
        guard viewport.width > 0, viewport.height > 0,
              canvasSize.width > 0, canvasSize.height > 0 else { return }
        let fit = min((viewport.width - 2 * Self.margin) / canvasSize.width,
                      (viewport.height - 2 * Self.margin) / canvasSize.height)
        // REM: a picture that already fits opens at 100%, never blown up past its real size.
        zoom = clamp(min(1, fit))
    }

    /// Pinch (iPad, trackpad) sets the zoom directly; the status line reports where it ended.
    func pinch(to value: CGFloat) { zoom = clamp(value) }
    func pinchEnded() { status = "Zoomed to \(zoomText)" }

    func toggleFocusMode() {
        focusMode.toggle()
        status = focusMode ? "Canvas focus on" : "Canvas focus off"
    }

    /// Space left around the canvas inside the scroll area.
    static let margin: CGFloat = 16

    private func set(_ value: CGFloat, verb: String) {
        zoom = clamp(value)
        status = "\(verb) to \(zoomText)"
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(Self.maxZoom, max(Self.minZoom, value))
    }
}
