//
//  DrawingTools.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// REM: Build step 4b — Paint Bucket (049), Pen / Pixels (050), Eraser (051), Eyedropper (052).
// One rule for all four (036): select the layer first, then use the tool. Every result lands on
// a new layer above the edited one, original hidden; Undo steps History back.
// Settings persist across launches (his rule), so they live in @AppStorage.

enum EraserMode: String, CaseIterable { case brush = "Brush", magic = "Magic" }
enum BrushShape: String, CaseIterable { case circle = "Circle", square = "Square" }

extension Tool {
    /// Tools that act on the picture itself (the canvas takes clicks and drags for them).
    var usesCanvas: Bool { [.bucket, .pen, .eraser, .eyedropper, .lasso].contains(self) }
}

// MARK: - Settings in the inspector

struct BucketToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.bucket.tolerance") private var tolerance = 0.1

    var body: some View {
        Section {
            ColorChip(document: document, editor: editor)
            Button("Fill Layer") {
                guard let id = editor.selectedLayer else { return }
                editor.selectedLayer = document.fillLayer(id, hex: editor.color(in: document), undoManager: undoManager) ?? id
                editor.status = "Filled the layer"
            }
            .disabled(editor.selectedLayer == nil)
            HStack {
                Text("Tolerance")
                Slider(value: $tolerance, in: 0...0.5).accessibilityLabel("Tolerance")
                Text("\(Int(tolerance * 100))%").monospacedDigit().frame(width: 44)
                InfoTip(text: "How close a color must be to the one you click for the paint to flow into it. Low stops at faint edges; high pours across them.")
            }
            Text("Click or tap the picture to pour up to the outline.").font(.callout).foregroundStyle(.secondary)
        } header: { Text("Paint Bucket") }
    }
}

struct PenToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.pen.erase") private var erase = false

    var body: some View {
        Section {
            ColorChip(document: document, editor: editor)
            Picker("Mode", selection: $erase) {
                Text("Draw").tag(false)
                Text("Erase").tag(true)
            }
            .pickerStyle(.segmented)
            if let id = editor.selectedLayer, let layer = document.layer(id) {
                HStack {
                    // One label, one line (it wrapped on the iPad mini when split in two).
                    Stepper(value: Binding(get: { editor.gridSize(for: layer, in: document) },
                                           set: { document.setGridSize(id, $0, undoManager: undoManager) }),
                            in: 1...512) {
                        Text("Square size \(editor.gridSize(for: layer, in: document)) px").monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .accessibilityLabel("Square size")
                    InfoTip(text: "Each layer keeps its own square size, like its own sheet of graph paper.")
                }
            }
            #if os(macOS)
            Text("Drag to draw squares. Right-drag erases.").font(.callout).foregroundStyle(.secondary)
            #else
            Text("Drag to draw squares.").font(.callout).foregroundStyle(.secondary)
            #endif
        } header: { Text("Pen (Pixels)") }
    }
}

struct EraserToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.eraser.mode") private var mode = EraserMode.brush
    @AppStorage("lw.eraser.shape") private var shape = BrushShape.circle
    @AppStorage("lw.eraser.size") private var size = 24.0
    @AppStorage("lw.eraser.tolerance") private var tolerance = 0.1

    var body: some View {
        Section {
            Picker("Eraser", selection: $mode) {
                ForEach(EraserMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch mode {
            case .brush:
                Picker("Shape", selection: $shape) {
                    ForEach(BrushShape.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("Size")
                    Slider(value: $size, in: 2...256).accessibilityLabel("Eraser size")
                    Text("\(Int(size)) px").monospacedDigit().frame(width: 60)
                }
                Text("Drag over the picture to erase by hand.").font(.callout).foregroundStyle(.secondary)
            case .magic:
                if let hex = editor.magicColor {
                    LabeledContent("Color to erase") {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(cgColor: Compositor.cgColor(hex: hex) ?? CGColor(gray: 0, alpha: 1)))
                            .frame(width: 44, height: 28)
                            .accessibilityLabel(hex)
                    }
                } else {
                    Text("Click or tap the background to pick the color to erase.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Tolerance")
                    Slider(value: $tolerance, in: 0...0.5).accessibilityLabel("Tolerance")
                    Text("\(Int(tolerance * 100))%").monospacedDigit().frame(width: 44)
                    InfoTip(text: "Raise it until the whole background shows magenta, then erase. Tip: fill a black layer behind the picture first so leftover bits show.")
                }
                Button("Erase Color → Transparent") {
                    guard let id = editor.selectedLayer, let hex = editor.magicColor,
                          let target = RGBA(hex: hex), var b = document.bitmap(of: id) else { return }
                    b.clear(b.colorMatch(target, tolerance: tolerance))
                    if let new = document.fork(id, into: b, label: "Erase", title: "Eraser", undoManager: undoManager) {
                        editor.selectedLayer = new
                        editor.status = "Erased \(hex)"
                    }
                }
                .disabled(editor.magicColor == nil || document.layer(editor.selectedLayer)?.image == nil)
            }
            if document.layer(editor.selectedLayer)?.image == nil {
                Text("Select a layer with a picture to erase.").font(.callout).foregroundStyle(.secondary)
            }
        } header: { Text("Eraser") }
    }
}

struct EyedropperToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @AppStorage("lw.eyedropper.sample") private var sample = 1

    var body: some View {
        Section {
            ColorChip(document: document, editor: editor)
            Picker("Sample size", selection: $sample) {
                Text("1 pixel").tag(1)
                Text("3 × 3").tag(3)
                Text("5 × 5").tag(5)
                Text("11 × 11").tag(11)
            }
            .accessibilityLabel("Sample size")
            InfoTip(text: "A larger sample averages the area around the click, for a steadier color on a soft background.")
            Text("Click or tap the picture to pick up its color into the palette.")
                .font(.callout).foregroundStyle(.secondary)
        } header: { Text("Eyedropper") }
    }
}

/// The color in use, shown wherever a tool paints.
struct ColorChip: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    var body: some View {
        LabeledContent("Color") {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(cgColor: Compositor.cgColor(hex: editor.color(in: document)) ?? CGColor(gray: 0, alpha: 1)))
                .frame(width: 44, height: 28)
                .accessibilityLabel(editor.color(in: document))
        }
        .accessibilityIdentifier("Color in use")
    }
}

extension EditorState {
    func color(in document: LayerworksDocument) -> String {
        let p = document.manifest.palette
        return p[min(colorIndex, p.count - 1)]
    }

    func gridSize(for layer: Layer, in document: LayerworksDocument) -> Int {
        layer.gridSize ?? max(1, document.manifest.canvasWidth / 32)
    }
}

// MARK: - The canvas side: clicks, drags, hover

struct CanvasInteraction: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.bucket.tolerance") private var bucketTolerance = 0.1
    @AppStorage("lw.pen.erase") private var penErase = false
    @AppStorage("lw.eraser.mode") private var eraserMode = EraserMode.brush
    @AppStorage("lw.eraser.shape") private var shape = BrushShape.circle
    @AppStorage("lw.eraser.size") private var eraserSize = 24.0
    @AppStorage("lw.eraser.tolerance") private var magicTolerance = 0.1
    @AppStorage("lw.eyedropper.sample") private var sample = 1
    @AppStorage("lw.lasso.tolerance") private var lassoTolerance = 0.1
    @AppStorage("lw.adj.liquify") private var liquifyMode = LiquifyMode.bulge
    @AppStorage("lw.adj.lqRadius") private var liquifyRadius = 120.0
    @AppStorage("lw.adj.lqStrength") private var liquifyStrength = 0.5

    @State private var points: [CGPoint] = []
    @State private var strokeErases = false
    @State private var preview: CGImage?
    @State private var hoverPixel: (Int, Int)?

    var body: some View {
        ZStack {
            if let preview {
                Image(decorative: preview, scale: 1).resizable().interpolation(.none)
                    .opacity(0.55).allowsHitTesting(false)
            }
            Canvas { ctx, _ in drawLiveStroke(ctx) }.allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .gesture(drag)
                #if os(macOS)
                .onContinuousHover { phase in hover(phase) }
                #endif
        }
        .allowsHitTesting(editor.tool.usesCanvas || (editor.tool == .adjust && editor.adjustment == .liquify))
        .onChange(of: editor.tool) { _, _ in preview = nil; editor.lassoLayer = nil; refreshMagicPreview() }
        .onChange(of: editor.magicColor) { _, _ in refreshMagicPreview() }
        .onChange(of: magicTolerance) { _, _ in refreshMagicPreview() }
        .onChange(of: eraserMode) { _, _ in preview = nil; refreshMagicPreview() }
        .onChange(of: editor.selectedLayer) { _, _ in refreshMagicPreview() }
    }

    private func pixel(_ p: CGPoint) -> (Int, Int) {
        (Int((p.x / editor.zoom).rounded(.down)), Int((p.y / editor.zoom).rounded(.down)))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if points.isEmpty {
                    editor.status = "\(editor.tool.title)…"
                    #if os(macOS)
                    strokeErases = NSEvent.pressedMouseButtons & 0x2 != 0
                    #endif
                }
                points.append(value.location)
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) > 3
                finish(at: value.location, moved: moved)
                points = []
                strokeErases = false
            }
    }

    private func finish(at location: CGPoint, moved: Bool) {
        guard let id = editor.selectedLayer, document.layer(id) != nil else {
            editor.status = "Select a layer first"; return
        }
        let (x, y) = pixel(location)
        switch editor.tool {
        case .bucket:
            guard var b = document.bitmap(of: id), b.contains(x, y),
                  let c = RGBA(hex: editor.color(in: document)) else { return }
            b.fill(b.region(from: x, y, tolerance: bucketTolerance), with: c)
            select(document.fork(id, into: b, label: "Fill", title: "Paint Bucket", undoManager: undoManager),
                   "Poured \(c.hex)")
            preview = nil
        case .pen:
            guard let layer = document.layer(id), var b = document.bitmap(of: id) else { return }
            let erase = penErase || strokeErases
            let cells = penCells(grid: editor.gridSize(for: layer, in: document))
            let c = RGBA(hex: editor.color(in: document)) ?? RGBA(r: 0, g: 0, b: 0)
            b.draw { ctx, rect in
                for cell in cells {
                    let r = CGRect(x: cell.minX, y: rect.height - cell.maxY, width: cell.width, height: cell.height)
                    if erase { ctx.clear(r) } else {
                        ctx.setFillColor(CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                                                 blue: CGFloat(c.b) / 255, alpha: 1))
                        ctx.fill(r)
                    }
                }
            }
            select(document.fork(id, into: b, label: "Pixel", title: "Pen / Pixels", undoManager: undoManager),
                   "\(erase ? "Erased" : "Drew") \(cells.count) square\(cells.count == 1 ? "" : "s")")
        case .eraser:
            if eraserMode == .magic {
                guard let b = document.bitmap(of: id), b.contains(x, y) else { return }
                let p = b.rgba(x, y)
                editor.magicColor = RGBA(r: UInt8(p.r), g: UInt8(p.g), b: UInt8(p.b)).hex
                editor.status = "Color to erase: \(editor.magicColor ?? "")"
                return
            }
            guard document.layer(id)?.image != nil, var b = document.bitmap(of: id) else {
                editor.status = "Select a layer with a picture to erase"; return
            }
            let path = brushPath(points + [location])
            b.draw { ctx, rect in
                ctx.translateBy(x: 0, y: rect.height); ctx.scaleBy(x: 1, y: -1)
                ctx.addPath(path); ctx.setBlendMode(.clear); ctx.fillPath()
            }
            select(document.fork(id, into: b, label: "Erase", title: "Eraser", undoManager: undoManager), "Erased")
        case .eyedropper:
            pickColor(x, y)
        case .adjust where editor.adjustment == .liquify:
            // 059 Liquify: each touch bends the picture there, its own History step, all on one
            // new layer (original hidden) — the same run rule as the Magic Lasso.
            guard let b = document.bitmap(of: id), b.contains(x, y),
                  let out = Adjust.liquify(b, at: CGPoint(x: x, y: y), mode: liquifyMode,
                                           radius: liquifyRadius, strength: liquifyStrength) else { return }
            if editor.lassoLayer == id {
                document.replacePicture(id, with: out, title: "Liquify", undoManager: undoManager)
                editor.status = "Liquified again"
            } else if let new = document.fork(id, into: out, label: "Liquify", title: "Liquify", undoManager: undoManager) {
                editor.lassoLayer = new
                select(new, "Liquified")
            }
        case .lasso:
            // 056: the first clear starts one new layer (original hidden); later clears in the
            // same run land on it, each its own History step.
            guard let before = document.bitmap(of: id), before.contains(x, y) else { return }
            var b = before
            b.clear(b.region(from: x, y, tolerance: lassoTolerance))
            if b.pixels == before.pixels {
                editor.status = "Nothing left to clear there"
            } else if editor.lassoLayer == id {
                document.replacePicture(id, with: b, title: "Magic Lasso", undoManager: undoManager)
                editor.status = "Cleared another area"
            } else if let new = document.fork(id, into: b, label: "Lasso", title: "Magic Lasso", undoManager: undoManager) {
                editor.lassoLayer = new
                select(new, "Cleared an area")
            }
            preview = nil
            hoverPixel = nil
        default: break
        }
    }

    private func select(_ id: UUID?, _ message: String) {
        if let id { editor.selectedLayer = id; editor.status = message }
    }

    /// Squares the pen stroke crossed, in canvas pixels.
    private func penCells(grid: Int) -> [CGRect] {
        var seen = Set<Int>(), out: [CGRect] = []
        let g = CGFloat(grid)
        let w = document.manifest.canvasWidth
        for p in densify(points) {
            let (px, py) = pixel(p)
            let cx = px / grid, cy = py / grid
            guard px >= 0, py >= 0, px < w, py < document.manifest.canvasHeight else { continue }
            if seen.insert(cy * (w / grid + 2) + cx).inserted {
                out.append(CGRect(x: CGFloat(cx) * g, y: CGFloat(cy) * g, width: g, height: g))
            }
        }
        return out
    }

    /// Fills gaps between drag samples so a fast stroke stays continuous.
    private func densify(_ pts: [CGPoint]) -> [CGPoint] {
        guard var last = pts.first else { return [] }
        var out = [last]
        let step = max(editor.zoom, 1)
        for p in pts.dropFirst() {
            let d = hypot(p.x - last.x, p.y - last.y)
            let n = Int(d / step)
            if n > 1 { for k in 1..<n { out.append(CGPoint(x: last.x + (p.x - last.x) * CGFloat(k) / CGFloat(n),
                                                           y: last.y + (p.y - last.y) * CGFloat(k) / CGFloat(n))) } }
            out.append(p); last = p
        }
        return out
    }

    /// The eraser brush along the drag, in canvas pixels (top-left origin).
    private func brushPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let s = CGFloat(eraserSize)
        for p in densify(pts) {
            let c = CGPoint(x: p.x / editor.zoom, y: p.y / editor.zoom)
            let r = CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
            if shape == .circle { path.addEllipse(in: r) } else { path.addRect(r) }
        }
        return path
    }

    private func drawLiveStroke(_ ctx: GraphicsContext) {
        guard !points.isEmpty else { return }
        switch editor.tool {
        case .pen:
            guard let id = editor.selectedLayer, let layer = document.layer(id) else { return }
            let erase = penErase || strokeErases
            let color: Color = erase ? .red.opacity(0.4)
                : Color(cgColor: Compositor.cgColor(hex: editor.color(in: document)) ?? CGColor(gray: 0, alpha: 1))
            for cell in penCells(grid: editor.gridSize(for: layer, in: document)) {
                let r = CGRect(x: cell.minX * editor.zoom, y: cell.minY * editor.zoom,
                               width: cell.width * editor.zoom, height: cell.height * editor.zoom)
                ctx.fill(Path(r), with: .color(color))
            }
        case .eraser where eraserMode == .brush:
            var t = CGAffineTransform(scaleX: editor.zoom, y: editor.zoom)
            if let scaled = brushPath(points).copy(using: &t) {
                ctx.fill(Path(scaled), with: .color(.red.opacity(0.35)))
            }
        default: break
        }
    }

    private func pickColor(_ x: Int, _ y: Int) {
        let w = document.manifest.canvasWidth, h = document.manifest.canvasHeight
        guard let image = Compositor.image(layers: document.layers, blobs: document.blobs, width: w, height: h),
              let c = Bitmap(image: image, width: w, height: h).average(x, y, size: sample) else { return }
        guard c.a >= 128 else { editor.status = "That spot is clear — no color to pick"; return }
        let hex = RGBA(r: c.r, g: c.g, b: c.b).hex
        var palette = document.manifest.palette
        if let i = palette.firstIndex(of: hex) {
            editor.colorIndex = i
        } else if palette.count < Palette.maximum {
            palette.append(hex)
            document.setPalette(palette, undoManager: undoManager)
            editor.colorIndex = palette.count - 1
        } else {
            palette[min(editor.colorIndex, palette.count - 1)] = hex
            document.setPalette(palette, undoManager: undoManager)
        }
        editor.magicColor = hex
        editor.status = "Picked \(hex)"
    }

    #if os(macOS)
    /// Bucket: hover shows where the paint would go (049).
    private func hover(_ phase: HoverPhase) {
        guard editor.tool == .bucket || editor.tool == .lasso, let id = editor.selectedLayer else { return }
        switch phase {
        case .active(let loc):
            let p = pixel(loc)
            if let h = hoverPixel, h == p { return }
            hoverPixel = p
            let lasso = editor.tool == .lasso
            guard let b = document.bitmap(of: id), b.contains(p.0, p.1),
                  let c = lasso ? RGBA(r: 255, g: 0, b: 0) : RGBA(hex: editor.color(in: document)) else { preview = nil; return }
            preview = maskImage(b.region(from: p.0, p.1, tolerance: lasso ? lassoTolerance : bucketTolerance),
                                width: b.width, height: b.height, color: c)
        case .ended:
            hoverPixel = nil
            preview = nil
        }
    }
    #endif

    /// Magic Eraser: everything that would be erased shows magenta (051).
    private func refreshMagicPreview() {
        guard editor.tool == .eraser, eraserMode == .magic, let hex = editor.magicColor,
              let target = RGBA(hex: hex), let id = editor.selectedLayer,
              let b = document.bitmap(of: id) else {
            if editor.tool == .eraser { preview = nil }
            return
        }
        preview = maskImage(b.colorMatch(target, tolerance: magicTolerance), width: b.width, height: b.height,
                            color: RGBA(r: 255, g: 0, b: 255))
    }
}
