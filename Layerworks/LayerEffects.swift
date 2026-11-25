//
//  LayerEffects.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

// REM: Build step 4e1 — the Layer tool (039: "one tool, five reveals, one Apply") and Remove
// Background (041). Each effect shows live on the canvas (document.preview); nothing is permanent
// until Apply, and Apply puts the result on a new layer with the original hidden underneath.
// 040 (his 2026-09-06 lost idea): Gradient lives here as a reveal of the Layer tool, next to
// Translucent — not a second parent tool.
// 041: Apple's Vision subject lift, never a homemade detector.

nonisolated enum LayerBlend: String, CaseIterable, Codable, Sendable {
    case multiply = "Multiply", screen = "Screen", overlay = "Overlay", darken = "Darken",
         lighten = "Lighten", softLight = "Soft Light", difference = "Difference"
    var cgMode: CGBlendMode {
        switch self {
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .darken: .darken
        case .lighten: .lighten
        case .softLight: .softLight
        case .difference: .difference
        }
    }
    var help: String {
        switch self {
        case .multiply: "Darker: only the dark parts show through"
        case .screen: "Lighter: a black field drops out and only the light stays"
        case .overlay: "More contrast"
        case .darken: "Keeps whichever is darker"
        case .lighten: "Keeps whichever is lighter"
        case .softLight: "A gentle contrast"
        case .difference: "Inverts where the layers overlap"
        }
    }
}

enum LayerEffect: String, CaseIterable { case translucent = "Translucent", glow = "Glow", greenKey = "Green Key", gradient = "Gradient", blend = "Blend" }
enum GlowStyle: String, CaseIterable { case soft = "Soft", neon = "Neon", plasma = "Plasma" }

nonisolated enum Effects {
    static let ci = CIContext()

    /// Glow (039): a blurred, colored halo from the layer's own edges, under the picture.
    static func glow(_ b: Bitmap, colors: [RGBA], reach: Double, intensity: Double) -> Bitmap? {
        guard let src = b.cgImage() else { return nil }
        let input = CIImage(cgImage: src)
        var halo: CIImage?
        for (k, c) in colors.enumerated() {
            let tint = CIFilter.colorMatrix()
            tint.inputImage = input
            tint.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            tint.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            tint.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            tint.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity))
            tint.biasVector = CIVector(x: CGFloat(c.r) / 255, y: CGFloat(c.g) / 255, z: CGFloat(c.b) / 255, w: 0)
            guard let colored = tint.outputImage?.premultiplyingAlpha() else { continue }
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = colored.clampedToExtent()
            blur.radius = Float(reach * Double(k + 1))
            guard let blurred = blur.outputImage?.cropped(to: input.extent) else { continue }
            halo = halo.map { $0.composited(over: blurred) } ?? blurred
        }
        guard let halo, let out = ci.createCGImage(input.composited(over: halo), from: input.extent) else { return nil }
        return Bitmap(image: out, width: b.width, height: b.height)
    }

    /// Green Key (039): one color disappears. Softness feathers the edge.
    static func greenKey(_ b: Bitmap, key: RGBA, tolerance: Double, softness: Double) -> Bitmap {
        var out = b
        let lo = tolerance, hi = tolerance + max(softness, 0.0001)
        for y in 0..<b.height { for x in 0..<b.width {
            let p = b.rgba(x, y)
            guard p.a > 0 else { continue }
            let d = Double(max(abs(p.r - Int(key.r)), abs(p.g - Int(key.g)), abs(p.b - Int(key.b)))) / 255
            let keep = d <= lo ? 0 : d >= hi ? 1 : (d - lo) / (hi - lo)
            out.set(x, y, RGBA(r: UInt8(p.r), g: UInt8(p.g), b: UInt8(p.b), a: UInt8(Double(p.a) * keep)))
        } }
        return out
    }

    /// Gradient (039 / 040): on an empty layer, a two-color blend; on a picture, a fade.
    static func gradient(_ b: Bitmap, empty: Bool, from c1: RGBA, to c2: RGBA, angle: Double,
                         start: Double, end: Double) -> Bitmap? {
        var out = Bitmap(width: b.width, height: b.height)
        let w = CGFloat(b.width), h = CGFloat(b.height)
        let a = angle * .pi / 180
        let center = CGPoint(x: w / 2, y: h / 2)
        let half = (abs(cos(a)) * w + abs(sin(a)) * h) / 2
        let dir = CGPoint(x: cos(a), y: -sin(a))
        let p0 = CGPoint(x: center.x - dir.x * half, y: center.y - dir.y * half)
        let p1 = CGPoint(x: center.x + dir.x * half, y: center.y + dir.y * half)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func color(_ c: RGBA, _ alpha: CGFloat) -> CGColor {
            CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: alpha)
        }
        let colors = empty ? [color(c1, 1), color(c2, 1)] : [color(c1, 1), color(c1, 0)]
        guard let g = CGGradient(colorsSpace: space, colors: colors as CFArray,
                                 locations: [CGFloat(min(start, end)), CGFloat(max(start, end))]) else { return nil }
        if empty {
            out.draw { ctx, _ in ctx.drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]) }
            return out
        }
        // A fade: the picture's alpha follows the gradient (opaque at the start, clear at the end).
        var mask = Bitmap(width: b.width, height: b.height)
        mask.draw { ctx, _ in ctx.drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]) }
        out = b
        for i in stride(from: 0, to: out.pixels.count, by: 4) {
            let f = Double(mask.pixels[i + 3]) / 255
            for k in 0..<4 { out.pixels[i + k] = UInt8(Double(out.pixels[i + k]) * f) }
        }
        return out
    }

    /// Remove Background (041): Apple's subject lift. Returns the subjects found and a cut-out
    /// keeping the chosen ones (nil = all).
    static func liftSubjects(_ b: Bitmap, keep: Set<Int>?) -> (count: Int, cutout: Bitmap?) {
        guard let image = b.cgImage() else { return (0, nil) }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil, let result = request.results?.first else { return (0, nil) }
        let all = result.allInstances
        let chosen = keep.map { IndexSet($0.filter { all.contains($0) }) } ?? all
        guard !chosen.isEmpty,
              let buffer = try? result.generateMaskedImage(ofInstances: chosen, from: handler, croppedToInstancesExtent: false),
              let out = ci.createCGImage(CIImage(cvPixelBuffer: buffer), from: CIImage(cvPixelBuffer: buffer).extent)
        else { return (all.count, nil) }
        return (all.count, Bitmap(image: out, width: b.width, height: b.height))
    }
}

extension LayerworksDocument {
    /// A copy of the layer with changed settings (Translucent, Blend), above it; original hidden.
    func forkCopy(_ id: UUID, label: String, title: String, undoManager: UndoManager?,
                  _ change: (inout Layer) -> Void) -> UUID? {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = layers[i]
        copy.id = UUID()
        copy.role = .content
        let base = copy.name.replacingOccurrences(of: #"\s*\([^()]*\)$"#, with: "", options: .regularExpression)
        let used = Set(layers.map(\.name))
        var n = 1
        while used.contains("\(base) (\(label) \(n))") { n += 1 }
        copy.name = "\(base) (\(label) \(n))"
        change(&copy)
        commit(title, undoManager: undoManager) { list in
            if !list[i].role.isBackground { list[i].isVisible = false }
            list.insert(copy, at: i + 1)
        }
        return copy.id
    }
}

struct LayerToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.fx.effect") private var effect = LayerEffect.translucent
    @AppStorage("lw.fx.opacity") private var opacity = 0.5
    @AppStorage("lw.fx.glow") private var glowStyle = GlowStyle.neon
    @AppStorage("lw.fx.reach") private var reach = 16.0
    @AppStorage("lw.fx.intensity") private var intensity = 1.0
    @AppStorage("lw.fx.tolerance") private var tolerance = 0.25
    @AppStorage("lw.fx.softness") private var softness = 0.1
    @AppStorage("lw.fx.angle") private var angle = 0.0
    @AppStorage("lw.fx.start") private var start = 0.0
    @AppStorage("lw.fx.end") private var end = 1.0
    @AppStorage("lw.fx.blend") private var blend = LayerBlend.screen
    @AppStorage("lw.fx.strength") private var strength = 1.0

    private var layer: Layer? { document.layer(editor.selectedLayer) }
    private var palette: [String] { document.manifest.palette }

    var body: some View {
        Section {
            Picker("Effect", selection: $effect) {
                ForEach(LayerEffect.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .accessibilityLabel("Effect")
            switch effect {
            case .translucent:
                slider("See-through", $opacity, 0...1, percent: true)
            case .glow:
                Picker("Glow", selection: $glowStyle) {
                    ForEach(GlowStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("Reach", $reach, 1...128, unit: "px")
                slider("Intensity", $intensity, 0.1...1, percent: true)
                Text(glowStyle == .plasma ? "Plasma uses the color in use and palette color 1." : "Glow uses the color in use.")
                    .font(.callout).foregroundStyle(.secondary)
                if layer?.image == nil {
                    Text("Glow needs an edge: use it on a picture, not a full Light or Dark fill.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case .greenKey:
                LabeledContent("Color that disappears", value: editor.magicColor ?? "#00FF00")
                slider("Tolerance", $tolerance, 0...0.6, percent: true)
                slider("Softness", $softness, 0...0.5, percent: true)
                Text("Pick the color with the Eyedropper. Too much Softness fades the subject.")
                    .font(.callout).foregroundStyle(.secondary)
            case .gradient:
                slider("Direction", $angle, 0...360, unit: "°")
                slider("Blend starts", $start, 0...1, percent: true)
                slider("Blend ends", $end, 0...1, percent: true)
                Text(isEmpty ? "An empty layer gets a blend from the color in use to palette color 1." : "A picture fades out along the direction.")
                    .font(.callout).foregroundStyle(.secondary)
            case .blend:
                Picker("Blend", selection: $blend) {
                    ForEach(LayerBlend.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Text(blend.help).font(.callout).foregroundStyle(.secondary)
                slider("Strength", $strength, 0...1, percent: true)
            }
            HStack {
                Button("Apply", action: apply).disabled(layer == nil)
                Spacer()
                Button("Cancel") { document.preview = nil; editor.status = "Effect canceled" }
                    .disabled(document.preview == nil)
            }
            .buttonStyle(.borderless)
        } header: { Text("Layer") }
        .onAppear(perform: refresh)
        .onDisappear { document.preview = nil }
        .onChange(of: [opacity, reach, intensity, tolerance, softness, angle, start, end, strength]) { _, _ in refresh() }
        .onChange(of: effect) { _, _ in refresh() }
        .onChange(of: glowStyle) { _, _ in refresh() }
        .onChange(of: blend) { _, _ in refresh() }
        .onChange(of: editor.selectedLayer) { _, _ in refresh() }
    }

    private var isEmpty: Bool { layer.map { $0.image == nil && $0.fillHex == nil } ?? true }

    private func slider(_ name: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        percent: Bool = false, unit: String = "") -> some View {
        HStack {
            Text(name)
            Slider(value: value, in: range).accessibilityLabel(name)
            Text(percent ? "\(Int(value.wrappedValue * 100))%" : "\(Int(value.wrappedValue)) \(unit)")
                .monospacedDigit().frame(width: 56)
        }
    }

    /// The effect as a (layer, picture) pair, without touching the document.
    private func result() -> (Layer, Data?)? {
        guard let layer, let id = editor.selectedLayer else { return nil }
        let color = RGBA(hex: editor.color(in: document)) ?? RGBA(r: 0, g: 0, b: 0)
        let second = RGBA(hex: palette[0]) ?? RGBA(r: 0, g: 0, b: 0)
        switch effect {
        case .translucent:
            var l = layer; l.opacity = opacity; return (l, nil)
        case .blend:
            var l = layer; l.blendMode = blend.rawValue; l.opacity = strength; return (l, nil)
        case .glow:
            guard let b = document.bitmap(of: id) else { return nil }
            let colors = glowStyle == .plasma ? [color, second] : [color]
            let r = glowStyle == .soft ? reach * 2 : reach
            guard let out = Effects.glow(b, colors: colors, reach: r, intensity: intensity) else { return nil }
            var l = layer; l.frame = nil; l.rotation = nil; l.fillHex = nil; return (l, out.png())
        case .greenKey:
            guard let b = document.bitmap(of: id) else { return nil }
            let key = editor.magicColor.flatMap(RGBA.init(hex:)) ?? RGBA(r: 0, g: 255, b: 0)
            var l = layer; l.frame = nil; l.rotation = nil; l.fillHex = nil
            return (l, Effects.greenKey(b, key: key, tolerance: tolerance, softness: softness).png())
        case .gradient:
            guard let b = document.bitmap(of: id),
                  let out = Effects.gradient(b, empty: isEmpty, from: color, to: second, angle: angle, start: start, end: end)
            else { return nil }
            var l = layer; l.frame = nil; l.rotation = nil; l.fillHex = nil; return (l, out.png())
        }
    }

    private func refresh() {
        guard let id = editor.selectedLayer, let (l, png) = result() else { document.preview = nil; return }
        document.preview = (id, l, png)
    }

    private func apply() {
        guard let id = editor.selectedLayer, let (l, png) = result() else { return }
        document.preview = nil
        let new: UUID?
        if let png {
            let key = document.store(png)
            new = document.forkCopy(id, label: effect.rawValue, title: effect.rawValue, undoManager: undoManager) { c in
                c.image = key; c.frame = l.frame; c.rotation = l.rotation; c.fillHex = l.fillHex
            }
        } else {
            new = document.forkCopy(id, label: effect.rawValue, title: effect.rawValue, undoManager: undoManager) { c in
                c.opacity = l.opacity; c.blendMode = l.blendMode
            }
        }
        if let new { editor.selectedLayer = new; editor.status = "Applied \(effect.rawValue)" }
    }
}

struct RemoveBackgroundView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var subjects = 0
    @State private var keep: Set<Int> = []

    var body: some View {
        Button("Remove Background") { run(keep: nil) }
            .disabled(document.layer(editor.selectedLayer)?.image == nil)
        if subjects > 1 {
            Text("Found \(subjects) subjects. Choose which to keep:").font(.callout)
            ForEach(1...subjects, id: \.self) { i in
                Toggle("Subject \(i)", isOn: Binding(get: { keep.contains(i) },
                                                    set: { if $0 { keep.insert(i) } else { keep.remove(i) } }))
                    .accessibilityLabel("Subject \(i)")
            }
            Button("Keep Chosen Subjects") { run(keep: keep) }.disabled(keep.isEmpty)
        }
        Text("Apple's subject lift. Not perfect — finish with the Eraser. A soft glow on black goes with the background; keep it with Blend ▸ Screen instead.")
            .font(.callout).foregroundStyle(.secondary)
    }

    private func run(keep: Set<Int>?) {
        guard let id = editor.selectedLayer, let b = document.bitmap(of: id) else { return }
        editor.status = "Finding the subject…"
        let (count, cutout) = Effects.liftSubjects(b, keep: keep)
        subjects = count
        if keep == nil { self.keep = Set(1...max(count, 1)) }
        guard let cutout else { editor.status = "No subject found in this layer"; return }
        if let new = document.fork(id, into: cutout, label: "Cutout", title: "Remove Background", undoManager: undoManager) {
            editor.selectedLayer = new
            editor.status = count > 1 ? "Kept \(keep?.count ?? count) of \(count) subjects" : "Background removed"
        }
    }
}
