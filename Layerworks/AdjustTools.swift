//
//  AdjustTools.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(ImagePlayground)
import ImagePlayground
#endif

// REM: Build step 4e2a — Adjustments (059) and Image Playground (038).
// 059 (2026 NOV 25): "Keep Levels, Gaussian Blur, Liquify, Round Corners, and Flip as
// non-destructive product adjustments … do not invent a second windowing system beside Apple's."
// So they share ONE Adjust panel in the inspector, with live preview; the Image and Filter menus
// open it on the right adjustment. Apply = new layer, original hidden.
// 038: prompts are typed in Apple's Image Playground sheet, never in a box of ours. The result
// lands on a new layer (Filter Current Layer: above the selected one, original hidden).

enum Adjustment: String, CaseIterable { case levels = "Levels", blur = "Gaussian Blur", liquify = "Liquify", corners = "Round Corners", flip = "Flip" }
enum LiquifyMode: String, CaseIterable { case bulge = "Bulge", pinch = "Pinch", twirl = "Twirl" }

nonisolated enum Adjust {
    static let ci = CIContext()

    private static func run(_ b: Bitmap, _ f: (CIImage) -> CIImage?) -> Bitmap? {
        guard let src = b.cgImage() else { return nil }
        let input = CIImage(cgImage: src)
        guard let out = f(input), let cg = ci.createCGImage(out.cropped(to: input.extent), from: input.extent) else { return nil }
        return Bitmap(image: cg, width: b.width, height: b.height)
    }

    /// Levels: black point, white point, midtones (gamma), on straight color.
    static func levels(_ b: Bitmap, black: Double, white: Double, gamma: Double) -> Bitmap {
        var out = b
        let lo = black, span = max(white - black, 0.001)
        var table = [UInt8](repeating: 0, count: 256)
        for v in 0..<256 {
            let x = min(max((Double(v) / 255 - lo) / span, 0), 1)
            table[v] = UInt8((pow(x, 1 / max(gamma, 0.01)) * 255).rounded())
        }
        for y in 0..<b.height { for x in 0..<b.width {
            let p = b.rgba(x, y)
            guard p.a > 0 else { continue }
            out.set(x, y, RGBA(r: table[p.r], g: table[p.g], b: table[p.b], a: UInt8(p.a)))
        } }
        return out
    }

    static func blur(_ b: Bitmap, radius: Double) -> Bitmap? {
        run(b) { input in
            let f = CIFilter.gaussianBlur()
            f.inputImage = input.clampedToExtent()
            f.radius = Float(radius)
            return f.outputImage
        }
    }

    /// Liquify at one point (canvas pixels, top-left origin).
    static func liquify(_ b: Bitmap, at p: CGPoint, mode: LiquifyMode, radius: Double, strength: Double) -> Bitmap? {
        let center = CIVector(x: p.x, y: CGFloat(b.height) - p.y)
        return run(b) { input in
            switch mode {
            case .bulge, .pinch:
                let f = CIFilter.bumpDistortion()
                f.inputImage = input; f.center = CGPoint(x: center.x, y: center.y)
                f.radius = Float(radius); f.scale = Float(mode == .bulge ? strength : -strength)
                return f.outputImage
            case .twirl:
                let f = CIFilter.twirlDistortion()
                f.inputImage = input; f.center = CGPoint(x: center.x, y: center.y)
                f.radius = Float(radius); f.angle = Float(strength * .pi)
                return f.outputImage
            }
        }
    }

    /// Round Corners on the layer's own picture area.
    static func roundCorners(_ b: Bitmap, frame: PixelRect, radius: Double) -> Bitmap? {
        guard let src = b.cgImage() else { return nil }
        var out = Bitmap(width: b.width, height: b.height)
        out.draw { ctx, rect in
            let r = CGRect(x: CGFloat(frame.x), y: rect.height - CGFloat(frame.y + frame.height),
                           width: CGFloat(frame.width), height: CGFloat(frame.height))
            let c = min(CGFloat(radius), min(r.width, r.height) / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil))
            ctx.clip()
            ctx.draw(src, in: rect)
        }
        return out
    }

    static func flip(_ b: Bitmap, horizontal: Bool) -> Bitmap? {
        guard let src = b.cgImage() else { return nil }
        var out = Bitmap(width: b.width, height: b.height)
        out.draw { ctx, rect in
            if horizontal { ctx.translateBy(x: rect.width, y: 0); ctx.scaleBy(x: -1, y: 1) }
            else { ctx.translateBy(x: 0, y: rect.height); ctx.scaleBy(x: 1, y: -1) }
            ctx.draw(src, in: rect)
        }
        return out
    }
}

struct AdjustToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.adj.black") private var black = 0.0
    @AppStorage("lw.adj.white") private var white = 1.0
    @AppStorage("lw.adj.gamma") private var gamma = 1.0
    @AppStorage("lw.adj.blur") private var radius = 8.0
    @AppStorage("lw.adj.liquify") private var mode = LiquifyMode.bulge
    @AppStorage("lw.adj.lqRadius") private var lqRadius = 120.0
    @AppStorage("lw.adj.lqStrength") private var lqStrength = 0.5
    @AppStorage("lw.adj.corners") private var corner = 48.0
    @State private var flipped: Bool?   // nil = not flipped yet; true = horizontal

    var body: some View {
        Section {
            Picker("Adjustment", selection: $editor.adjustment) {
                ForEach(Adjustment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .accessibilityLabel("Adjustment")
            switch editor.adjustment {
            case .levels:
                slider("Black point", $black, 0...0.9)
                slider("White point", $white, 0.1...1)
                slider("Midtones", $gamma, 0.2...3, plain: true)
            case .blur:
                slider("Radius", $radius, 0...100, plain: true)
            case .liquify:
                Picker("Brush", selection: $mode) { ForEach(LiquifyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                slider("Size", $lqRadius, 10...600, plain: true)
                slider("Strength", $lqStrength, 0.05...1)
                Text("Click or tap the picture where it should bend. Each touch is its own History step.")
                    .font(.callout).foregroundStyle(.secondary)
            case .corners:
                slider("Corner radius", $corner, 0...512, plain: true)
            case .flip:
                HStack {
                    Button("Flip Horizontal") { flipped = true; refresh() }
                    Spacer()
                    Button("Flip Vertical") { flipped = false; refresh() }
                }
                .buttonStyle(.borderless)
            }
            if editor.adjustment != .liquify {
                HStack {
                    Button("Apply", action: apply).disabled(document.layer(editor.selectedLayer) == nil)
                    Spacer()
                    Button("Cancel") { document.preview = nil; flipped = nil; editor.status = "Adjustment canceled" }
                        .disabled(document.preview == nil)
                }
                .buttonStyle(.borderless)
            }
        } header: { Text("Adjust") }
        .onAppear(perform: refresh)
        .onDisappear { document.preview = nil }
        .onChange(of: [black, white, gamma, radius, corner]) { _, _ in refresh() }
        .onChange(of: editor.adjustment) { _, _ in flipped = nil; refresh() }
        .onChange(of: editor.selectedLayer) { _, _ in refresh() }
    }

    private func slider(_ name: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, plain: Bool = false) -> some View {
        HStack {
            Text(name)
            Slider(value: v, in: r).accessibilityLabel(name)
            Text(plain ? String(format: "%.1f", v.wrappedValue) : "\(Int(v.wrappedValue * 100))%")
                .monospacedDigit().frame(width: 52)
        }
    }

    private func result() -> Bitmap? {
        guard let id = editor.selectedLayer, let layer = document.layer(id), let b = document.bitmap(of: id) else { return nil }
        switch editor.adjustment {
        case .levels: return Adjust.levels(b, black: black, white: white, gamma: gamma)
        case .blur: return Adjust.blur(b, radius: radius)
        case .corners: return Adjust.roundCorners(b, frame: document.frame(of: layer), radius: corner)
        case .flip: return flipped.flatMap { Adjust.flip(b, horizontal: $0) }
        case .liquify: return nil
        }
    }

    private func refresh() {
        guard let id = editor.selectedLayer, var l = document.layer(id), let b = result() else { document.preview = nil; return }
        l.frame = nil; l.rotation = nil; l.fillHex = nil
        document.preview = (id, l, b.png())
    }

    private func apply() {
        guard let id = editor.selectedLayer, let b = result() else { return }
        document.preview = nil
        let name = editor.adjustment == .flip ? "Flip" : editor.adjustment.rawValue
        if let new = document.fork(id, into: b, label: name, title: name, undoManager: undoManager) {
            editor.selectedLayer = new
            editor.status = "Applied \(name)"
        }
        flipped = nil
    }
}

/// Image ▸ Adjustments ▸ Levels… (⌘L), Image ▸ Flip; Filter ▸ Gaussian Blur…, Liquify… (⇧⌘X),
/// Round Corners… — each opens the Adjust panel on that adjustment.
struct AdjustCommands: Commands {
    @FocusedObject private var editor: EditorState?

    var body: some Commands {
        CommandMenu("Image") {
            Menu("Adjustments") {
                Button("Levels…") { open(.levels) }.keyboardShortcut("l")
            }
            Button("Flip…") { open(.flip) }
        }
        CommandMenu("Filter") {
            Button("Gaussian Blur…") { open(.blur) }
            Button("Liquify…") { open(.liquify) }.keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Round Corners…") { open(.corners) }
        }
    }

    private func open(_ a: Adjustment) {
        guard let editor else { return }
        editor.adjustment = a
        editor.tool = .adjust
        editor.status = "\(a.rawValue)"
    }
}

// MARK: - Image Playground (038)

struct PlaygroundToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    #if canImport(ImagePlayground)
    @Environment(\.supportsImagePlayground) private var supported
    #endif
    @State private var showing = false
    @State private var filtering = false

    var body: some View {
        Section {
            #if canImport(ImagePlayground)
            if supported {
                Button("Image Playground: New Layer…") { filtering = false; showing = true }
                Button("Filter Current Layer…") { filtering = true; showing = true }
                    .disabled(document.layer(editor.selectedLayer)?.image == nil)
                Text("You type the words in Apple's Image Playground window. Done adds the picture as a new layer.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Image Playground needs Apple Intelligence turned on in System Settings.")
                    .foregroundStyle(.secondary)
            }
            #else
            Text("Image Playground isn't available on this device.").foregroundStyle(.secondary)
            #endif
        } header: { Text("Image Playground") }
        #if canImport(ImagePlayground)
        .imagePlaygroundSheet(isPresented: $showing, concepts: [], sourceImage: filtering ? source : nil) { url in
            guard let image = ContentRender.picture(at: url) else { editor.status = "That picture couldn't be read"; return }
            if let id = document.addPicture(image, name: filtering ? "Playground Filter" : "Playground",
                                            above: editor.selectedLayer, replacing: filtering, undoManager: undoManager) {
                editor.selectedLayer = id
                editor.status = filtering ? "Restyled on a new layer" : "Added an Image Playground picture"
            }
        }
        #endif
    }

    private var source: Image? {
        guard let id = editor.selectedLayer, let cg = document.bitmap(of: id)?.cgImage() else { return nil }
        return Image(decorative: cg, scale: 1)
    }
}
