//
//  ContentRender.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import SceneKit
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// REM: Build step 4c — text (053), symbols (054) and imported pictures (055) all become a layer
// picture plus a frame. Text and symbol layers also keep their words / symbol name, so changing
// the style, color or words redraws the picture: they stay editable, never flattened.

nonisolated enum ContentRender {
    /// Draws text with Core Text. Returns the picture, trimmed to the words plus a margin.
    static func text(_ t: TextContent) -> CGImage? {
        if let depth = t.depth, depth > 0, let solid = text3D(t, depth: depth) { return solid }
        var font = CTFontCreateWithName(t.fontName as CFString, CGFloat(t.size), nil)
        var traits: CTFontSymbolicTraits = []
        if t.bold { traits.insert(.traitBold) }
        if t.italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(font, 0, nil, traits, traits) {
            font = styled
        }
        let color = Compositor.cgColor(hex: t.colorHex) ?? CGColor(gray: 0, alpha: 1)
        func line(stroke: CGColor?) -> CTLine {
            var attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
            if t.underline { attrs[kCTUnderlineStyleAttributeName] = CTUnderlineStyle.single.rawValue }
            if let stroke {
                attrs[kCTStrokeColorAttributeName] = stroke
                // Positive width = edge only, in percent of the font size.
                attrs[kCTStrokeWidthAttributeName] = t.outlineWidth / max(t.size, 1) * 100 * 2
            }
            let s = CFAttributedStringCreate(nil, t.string as CFString, attrs as CFDictionary)!
            return CTLineCreateWithAttributedString(s)
        }
        let fill = line(stroke: nil)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(fill, &ascent, &descent, &leading)
        let pad = CGFloat(t.outlineHex == nil ? 2 : t.outlineWidth + 2)
        let w = Int(ceil(width + pad * 2)), h = Int(ceil(ascent + descent + pad * 2))
        guard w > 0, h > 0, let ctx = context(w, h) else { return nil }
        ctx.textPosition = CGPoint(x: pad, y: pad + descent)
        if let hex = t.outlineHex, let edge = Compositor.cgColor(hex: hex) {
            CTLineDraw(line(stroke: edge), ctx)
            ctx.textPosition = CGPoint(x: pad, y: pad + descent)
        }
        CTLineDraw(fill, ctx)
        return ctx.makeImage()
    }

    /// 3D text (053): SceneKit extrudes the font into a solid and an offscreen renderer draws it,
    /// lit, at the chosen turn and tilt. The words stay live text; 3D off gives the flat letters back.
    static func text3D(_ t: TextContent, depth: Double) -> CGImage? {
        let solid = SCNText(string: t.string, extrusionDepth: CGFloat(depth))
        #if canImport(AppKit)
        solid.font = NSFont(name: t.fontName, size: CGFloat(t.size)) ?? NSFont.systemFont(ofSize: CGFloat(t.size))
        let color = NSColor(cgColor: Compositor.cgColor(hex: t.colorHex) ?? CGColor(gray: 0, alpha: 1)) ?? .black
        #else
        solid.font = UIFont(name: t.fontName, size: CGFloat(t.size)) ?? UIFont.systemFont(ofSize: CGFloat(t.size))
        let color = UIColor(cgColor: Compositor.cgColor(hex: t.colorHex) ?? CGColor(gray: 0, alpha: 1))
        #endif
        solid.flatness = 0.2
        solid.chamferRadius = CGFloat(min(depth / 6, 6))
        solid.firstMaterial?.diffuse.contents = color
        solid.firstMaterial?.lightingModel = .physicallyBased
        let node = SCNNode(geometry: solid)
        let (lo, hi) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        node.eulerAngles = SCNVector3(Float(t.tilt * .pi / 180), Float(t.turn * .pi / 180), 0)
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)
        let w = CGFloat(hi.x - lo.x), h = CGFloat(hi.y - lo.y)
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max(w, h) * 0.75)
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, Float(max(w, h) * 3))
        scene.rootNode.addChildNode(cameraNode)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .directional
        light.eulerAngles = SCNVector3(-0.6, 0.5, 0)
        scene.rootNode.addChildNode(light)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        scene.rootNode.addChildNode(ambient)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        let side = max(w, h) * 1.5
        let snap = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
        #if canImport(AppKit)
        var r = CGRect(origin: .zero, size: snap.size)
        return snap.cgImage(forProposedRect: &r, context: nil, hints: nil)
        #else
        return snap.cgImage
        #endif
    }

    /// An SF Symbol drawn in one color at `points` tall.
    static func symbol(_ s: SymbolContent, points: CGFloat) -> CGImage? {
        let color = Compositor.cgColor(hex: s.colorHex) ?? CGColor(gray: 0, alpha: 1)
        #if canImport(AppKit)
        let config = NSImage.SymbolConfiguration(pointSize: points, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(cgColor: color) ?? .black]))
        guard let image = NSImage(systemSymbolName: s.name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        let config = UIImage.SymbolConfiguration(pointSize: points)
        guard let image = UIImage(systemName: s.name, withConfiguration: config)?
            .withTintColor(UIColor(cgColor: color), renderingMode: .alwaysOriginal) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }.cgImage
        #endif
    }

    static func symbolExists(_ name: String) -> Bool {
        #if canImport(AppKit)
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        UIImage(systemName: name) != nil
        #endif
    }

    /// A picture file (PNG, JPEG, HEIC, TIFF, GIF, BMP, PSD on Mac) or the first page of a PDF.
    static func picture(at url: URL) -> CGImage? {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            return pdfPage(url)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func picture(data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// A PDF's first page at 300 dpi (055: New from Import… includes PDF).
    static func pdfPage(_ url: URL) -> CGImage? {
        guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 300.0 / 72.0
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard let ctx = context(w, h) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

extension LayerworksDocument {
    /// A frame for a picture of this size: its own size, centered; scaled down to fit if it is
    /// bigger than the canvas (place and size it with Move).
    func centeredFrame(_ w: Int, _ h: Int, keeping old: PixelRect? = nil) -> PixelRect {
        if let old {   // Apply to Selected Layer keeps the size and place (054)
            let s = min(Double(old.width) / Double(max(w, 1)), Double(old.height) / Double(max(h, 1)))
            let nw = Int(Double(w) * s), nh = Int(Double(h) * s)
            return PixelRect(x: old.x + (old.width - nw) / 2, y: old.y + (old.height - nh) / 2, width: nw, height: nh)
        }
        let cw = manifest.canvasWidth, ch = manifest.canvasHeight
        let s = min(1, min(Double(cw) / Double(max(w, 1)), Double(ch) / Double(max(h, 1))))
        let nw = max(1, Int(Double(w) * s)), nh = max(1, Int(Double(h) * s))
        return PixelRect(x: (cw - nw) / 2, y: (ch - nh) / 2, width: nw, height: nh)
    }

    /// New Text Layer (053): named after its words, above the selected layer.
    func addText(_ t: TextContent, above id: UUID?, undoManager: UndoManager?) -> UUID? {
        guard let image = ContentRender.text(t), let png = Compositor.pngData(image) else { return nil }
        var layer = Layer(name: Self.name(forText: t.string), role: .content, image: store(png))
        layer.frame = centeredFrame(image.width, image.height)
        layer.text = t
        return insert(layer, above: id, title: "Text", undoManager: undoManager)
    }

    /// Restyle or reword a text layer in place (live style, 053). Keeps its center.
    func updateText(_ id: UUID, _ t: TextContent, undoManager: UndoManager?) {
        guard let old = layer(id), old.text != nil, old.text != t,
              let image = ContentRender.text(t), let png = Compositor.pngData(image) else { return }
        let key = store(png)
        let f = old.frame ?? centeredFrame(image.width, image.height)
        let frame = PixelRect(x: f.x + (f.width - image.width) / 2, y: f.y + (f.height - image.height) / 2,
                              width: image.width, height: image.height)
        let renames = old.text.map { !Self.isEmoji($0.string) && old.name == Self.name(forText: $0.string) } ?? false
        commit("Text", undoManager: undoManager) { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].text = t; list[i].image = key; list[i].frame = frame
            if renames { list[i].name = Self.name(forText: t.string) }
        }
    }

    /// Symbol (054): Create New Layer, or apply to the selected layer keeping its size and place.
    func addSymbol(_ s: SymbolContent, above id: UUID?, replacing: Bool, undoManager: UndoManager?) -> UUID? {
        let points = CGFloat(min(manifest.canvasWidth, manifest.canvasHeight)) * 0.4
        guard let image = ContentRender.symbol(s, points: points), let png = Compositor.pngData(image) else { return nil }
        let key = store(png)
        if replacing, let id, let i = layers.firstIndex(where: { $0.id == id }), layers[i].symbol != nil {
            let frame = centeredFrame(image.width, image.height, keeping: layers[i].frame)
            commit("Symbol", undoManager: undoManager) { list in
                list[i].symbol = s; list[i].image = key; list[i].frame = frame
            }
            return id
        }
        var layer = Layer(name: s.name, role: .content, image: key)
        layer.frame = centeredFrame(image.width, image.height)
        layer.symbol = s
        return insert(layer, above: id, title: "Symbol", undoManager: undoManager)
    }

    /// Image (055): Import Image to New Layer… (named for the file) or to the selected layer,
    /// which goes on a new layer above it with the original hidden.
    func addPicture(_ image: CGImage, name: String, above id: UUID?, replacing: Bool,
                    undoManager: UndoManager?) -> UUID? {
        guard let png = Compositor.pngData(image) else { return nil }
        var layer = Layer(name: name, role: .content, image: store(png))
        layer.frame = centeredFrame(image.width, image.height)
        let hide = replacing ? id : nil
        return insert(layer, above: id, hiding: hide, title: "Import Image", undoManager: undoManager)
    }

    private func insert(_ layer: Layer, above id: UUID?, hiding: UUID? = nil, title: String,
                        undoManager: UndoManager?) -> UUID {
        commit(title, undoManager: undoManager) { list in
            if let h = hiding, let i = list.firstIndex(where: { $0.id == h }), !list[i].role.isBackground {
                list[i].isVisible = false
            }
            let at = list.firstIndex { $0.id == id }.map { $0 + 1 } ?? list.count
            list.insert(layer, at: at)
        }
        return layer.id
    }

    static func name(forText s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Text" : String(t.prefix(40))
    }

    static func isEmoji(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C }
    }
}
