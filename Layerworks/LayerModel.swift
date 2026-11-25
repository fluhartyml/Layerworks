//
//  LayerModel.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

// REM: Blueprint 004 / 036 — the layer model. An ordered stack (index 0 = bottom), never
// flattened until export. Light and Dark are the bottom two layers and become the two
// appearances of an Icon Set export; they start blank and take a solid fill from the paint
// bucket (Image Producer's 2026-06-10 ruling: the opaque floor is what keeps an icon from being
// clear). Content layers are transparent.
//
// REM: Blueprint 006 — pictures are real PNG files inside the package, never base64 in JSON.
// Each picture is stored ONCE under its content hash (Images/<hash>.png), so every History step
// that shows the same pixels shares one file. That is the "lossless shrink" Optimize History
// used to do by hand, done on every Save.

nonisolated enum LayerRole: String, Codable, Equatable, Sendable {
    case light, dark, content
    var isBackground: Bool { self != .content }
}

nonisolated struct Layer: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var role: LayerRole
    var isVisible = true
    var opacity: Double = 1
    /// Layers sharing a link group move and resize together; each stays editable (036).
    var linkGroup: UUID?
    /// Solid fill as "#RRGGBB" — the backgrounds' floor color. nil = clear.
    var fillHex: String?
    /// Content hash of this layer's picture in the package's Images folder. nil = empty.
    var image: String?
    /// Where the picture sits, in canvas pixels from the top left. nil = the whole canvas.
    /// A canvas resize keeps each picture its own size, centered (never stretched).
    var frame: PixelRect?
    /// Pen (Pixels) square size for this layer, in canvas pixels (050: each layer has its own).
    var gridSize: Int?
    /// Turn in degrees around the frame's center (045: Rotation slider). nil = upright.
    var rotation: Double?
    /// Blend with the layers below (039 Blend): a Core Graphics blend mode name; nil = normal.
    var blendMode: String?
    /// A text layer's words and style (053). Its picture is drawn from this, so it stays editable.
    var text: TextContent?
    /// A symbol layer's SF Symbol and color (054).
    var symbol: SymbolContent?

    static func newPicture() -> [Layer] {
        [Layer(name: "Light", role: .light),
         Layer(name: "Dark", role: .dark),
         Layer(name: "Layer 1", role: .content)]
    }
}

nonisolated struct TextContent: Codable, Equatable, Sendable {
    var string: String
    var fontName: String = "Helvetica"
    /// In canvas pixels.
    var size: Double = 96
    var colorHex: String = "#000000"
    var bold = false
    var italic = false
    var underline = false
    /// Outline edge in a palette color (053); nil = none.
    var outlineHex: String?
    var outlineWidth: Double = 4
}

nonisolated struct SymbolContent: Codable, Equatable, Sendable {
    var name: String
    var colorHex: String
}

/// A rectangle in canvas pixels, top-left origin.
nonisolated struct PixelRect: Codable, Equatable, Sendable {
    var x: Int, y: Int, width: Int, height: Int
}

/// The eight starting colors (044) — Image Producer's crayon box, so palettes match.
nonisolated enum Palette {
    static let starting = ["#000000", "#FFFFFF", "#FF3B30", "#FF9500",
                           "#FFCC00", "#34C759", "#007AFF", "#AF52DE"]
    static let minimum = 8
    static let maximum = 24

    /// Keeps valid #RRGGBB colors, pads to 8 with the starting set, caps at 24.
    static func normalized(_ colors: [String]) -> [String] {
        var out = colors.map { $0.uppercased() }.filter { Compositor.cgColor(hex: $0) != nil && $0.count == 7 }
        if out.count < minimum { out += starting.dropFirst(out.count).prefix(minimum - out.count) }
        return Array(out.prefix(maximum))
    }
}

/// A `.iconpalette` file — Image Producer's format, so palettes move between both apps.
nonisolated struct PaletteFile: Codable, Sendable {
    var schemaVersion = 1
    var name: String
    var colors: [String]
}

/// One step of History (037): a full, restorable layer stack. Pictures are shared by hash,
/// so a step costs only its JSON plus any picture no other step has.
nonisolated struct HistoryStep: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var date = Date()
    var layers: [Layer]
    var canvasWidth: Int
    var canvasHeight: Int
}

/// What is written to `manifest.json`.
nonisolated struct ProjectManifest: Codable, Equatable, Sendable {
    /// 1 = step-1 files (canvas only). 2 = layers + History.
    var layerworksFormat: Int = 2
    var canvasWidth: Int
    var canvasHeight: Int
    /// Print resolution. Blueprint 003: 300 dpi by default.
    var ppi: Int = 300
    var layers: [Layer] = []
    var history: [HistoryStep] = []
    /// The step the picture is showing. Always the last step unless the user is looking back.
    var historyCursor: Int = 0
    /// The document palette (044): every color in the app comes from it.
    var palette: [String] = Palette.starting
    /// The mask (048): what exports keep. nil = the whole canvas.
    var mask: MaskSpec?

    init(canvasWidth: Int, canvasHeight: Int, ppi: Int = 300, layers: [Layer] = Layer.newPicture()) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.ppi = ppi
        self.layers = layers
        self.history = [HistoryStep(title: "Original", layers: layers,
                                    canvasWidth: canvasWidth, canvasHeight: canvasHeight)]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layerworksFormat = try c.decode(Int.self, forKey: .layerworksFormat)
        canvasWidth = try c.decode(Int.self, forKey: .canvasWidth)
        canvasHeight = try c.decode(Int.self, forKey: .canvasHeight)
        ppi = try c.decodeIfPresent(Int.self, forKey: .ppi) ?? 300
        // A step-1 file has no layers: it opens as a new picture of its size.
        layers = try c.decodeIfPresent([Layer].self, forKey: .layers) ?? Layer.newPicture()
        history = try c.decodeIfPresent([HistoryStep].self, forKey: .history) ?? []
        if history.isEmpty {
            history = [HistoryStep(title: "Original", layers: layers,
                                   canvasWidth: canvasWidth, canvasHeight: canvasHeight)]
        }
        palette = Palette.normalized(try c.decodeIfPresent([String].self, forKey: .palette) ?? Palette.starting)
        mask = try c.decodeIfPresent(MaskSpec.self, forKey: .mask)
        historyCursor = min(max(try c.decodeIfPresent(Int.self, forKey: .historyCursor) ?? history.count - 1, 0),
                            history.count - 1)
    }
}

// MARK: - Image Producer files (Walk Q3: old files still open)

/// Reads an Image Producer manifest. REM: this is a READER of its saved format, not a copy of
/// its code. Layer names, order, roles, background fills, visibility, opacity and links come
/// across now. Each layer's drawn contents (text, shapes, pixel art, photos) are Image
/// Producer "elements"; they come across as the matching tool is built (step 4).
nonisolated enum ImageProducerImport {
    struct Manifest: Decodable {
        var canvasSize: Int?
        var canvasWidth: Int?
        var canvasHeight: Int?
        var ppi: Double?
        var layers: [OldLayer]?
        var palette: [String]?
    }

    struct OldLayer: Decodable {
        var id: UUID?
        var name: String
        var isVisible: Bool?
        var opacity: Double?
        var linkGroup: UUID?
        var role: OldRole
    }

    /// Swift's coding of `case background(_ role: BackgroundRole, fillHex: String?)` / `case content`.
    struct OldRole: Decodable {
        var role: LayerRole
        var fillHex: String?
        private enum Keys: String, CodingKey { case background, content }
        private enum BackgroundKeys: String, CodingKey { case _0, fillHex }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if c.contains(.background) {
                let b = try c.nestedContainer(keyedBy: BackgroundKeys.self, forKey: .background)
                role = (try b.decodeIfPresent(String.self, forKey: ._0)) == "dark" ? .dark : .light
                fillHex = try b.decodeIfPresent(String.self, forKey: .fillHex)
            } else {
                role = .content
            }
        }
    }

    static func manifest(from data: Data) throws -> ProjectManifest {
        let old = try JSONDecoder().decode(Manifest.self, from: data)
        let width = old.canvasWidth ?? old.canvasSize ?? 1024
        let height = old.canvasHeight ?? old.canvasSize ?? 1024
        let layers = (old.layers ?? []).map { o in
            Layer(id: o.id ?? UUID(), name: o.name, role: o.role.role,
                  isVisible: o.isVisible ?? true, opacity: o.opacity ?? 1,
                  linkGroup: o.linkGroup, fillHex: o.role.fillHex, image: nil)
        }
        var manifest = ProjectManifest(canvasWidth: width, canvasHeight: height,
                                       ppi: Int((old.ppi ?? 72).rounded()),
                                       layers: layers.isEmpty ? Layer.newPicture() : layers)
        manifest.palette = Palette.normalized(old.palette ?? Palette.starting)
        return manifest
    }
}

// MARK: - Package layout

/// The package's folder layout, kept in one place so reader and writer cannot drift.
nonisolated enum PackageLayout {
    static let manifestName = "manifest.json"
    static let imagesFolder = "Images"
    /// Blueprint 023a: Finder, Files, Spotlight and Open panels read a package's
    /// QuickLook/Thumbnail.png, so the file icon shows the picture.
    static let quickLookFolder = "QuickLook"
    static let thumbnail = "Thumbnail.png"

    /// Reads a package: a Layerworks manifest, or an Image Producer one.
    static func read(_ wrapper: FileWrapper) throws -> (ProjectManifest, [String: Data]) {
        guard wrapper.isDirectory,
              let data = wrapper.fileWrappers?[manifestName]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manifest: ProjectManifest
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["layerworksFormat"] != nil {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(ProjectManifest.self, from: data)
        } else {
            manifest = try ImageProducerImport.manifest(from: data)
        }
        var blobs: [String: Data] = [:]
        for (name, file) in wrapper.fileWrappers?[imagesFolder]?.fileWrappers ?? [:] {
            if let bytes = file.regularFileContents {
                blobs[(name as NSString).deletingPathExtension] = bytes
            }
        }
        return (manifest, blobs)
    }

    static func wrapper(for manifest: ProjectManifest, blobs: [String: Data]) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestFile = FileWrapper(regularFileWithContents: try encoder.encode(manifest))
        manifestFile.preferredFilename = manifestName
        var children: [String: FileWrapper] = [manifestName: manifestFile]

        // Only pictures some layer or step still uses are written.
        var images: [String: FileWrapper] = [:]
        for key in referencedImages(manifest) {
            guard let bytes = blobs[key] else { continue }
            let file = FileWrapper(regularFileWithContents: bytes)
            file.preferredFilename = key + ".png"
            images[key + ".png"] = file
        }
        let imagesDir = FileWrapper(directoryWithFileWrappers: images)
        imagesDir.preferredFilename = imagesFolder
        children[imagesFolder] = imagesDir

        if let png = Compositor.png(layers: manifest.layers, blobs: blobs,
                                    width: manifest.canvasWidth, height: manifest.canvasHeight,
                                    maxSide: 512) {
            let thumb = FileWrapper(regularFileWithContents: png)
            thumb.preferredFilename = thumbnail
            let folder = FileWrapper(directoryWithFileWrappers: [thumbnail: thumb])
            folder.preferredFilename = quickLookFolder
            children[quickLookFolder] = folder
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    static func referencedImages(_ manifest: ProjectManifest) -> Set<String> {
        var keys = Set(manifest.layers.compactMap(\.image))
        for step in manifest.history { keys.formUnion(step.layers.compactMap(\.image)) }
        return keys
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Compositing

/// Draws a layer stack bottom to top. Used by the file icon, Merge and (later) export.
nonisolated enum Compositor {
    static func image(layers: [Layer], blobs: [String: Data], width: Int, height: Int,
                      maxSide: Int? = nil, onlyVisible: Bool = true) -> CGImage? {
        var w = max(width, 1), h = max(height, 1)
        if let maxSide, max(w, h) > maxSide {
            let s = Double(maxSide) / Double(max(w, h))
            w = max(1, Int(Double(w) * s)); h = max(1, Int(Double(h) * s))
        }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        for layer in layers where layer.isVisible || !onlyVisible {
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            if let mode = layer.blendMode.flatMap(LayerBlend.init(rawValue:)) { ctx.setBlendMode(mode.cgMode) }
            if let hex = layer.fillHex, let color = cgColor(hex: hex) {
                ctx.setFillColor(color)
                ctx.fill(rect)
            }
            if let key = layer.image, let data = blobs[key], let picture = decode(data) {
                drawPicture(picture, layer: layer, canvasWidth: width, canvasHeight: height, in: ctx, rect: rect)
            }
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    static func png(layers: [Layer], blobs: [String: Data], width: Int, height: Int,
                    maxSide: Int? = nil, onlyVisible: Bool = true) -> Data? {
        guard let image = image(layers: layers, blobs: blobs, width: width, height: height,
                                maxSide: maxSide, onlyVisible: onlyVisible) else { return nil }
        return pngData(image)
    }

    /// Draws a layer's picture in its frame, turned by its rotation.
    static func drawPicture(_ picture: CGImage, layer: Layer, canvasWidth: Int, canvasHeight: Int,
                            in ctx: CGContext, rect: CGRect) {
        let r = drawRect(layer.frame, canvasWidth: canvasWidth, canvasHeight: canvasHeight, into: rect)
        guard let deg = layer.rotation, deg != 0 else { ctx.draw(picture, in: r); return }
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.midY)
        ctx.rotate(by: -deg * .pi / 180)   // clockwise on screen (y is up in the context)
        ctx.draw(picture, in: CGRect(x: -r.width / 2, y: -r.height / 2, width: r.width, height: r.height))
        ctx.restoreGState()
    }

    /// A layer frame (canvas pixels, top-left origin) in a context of `rect` (bottom-left origin).
    static func drawRect(_ frame: PixelRect?, canvasWidth: Int, canvasHeight: Int, into rect: CGRect) -> CGRect {
        guard let f = frame else { return rect }
        let sx = rect.width / CGFloat(max(canvasWidth, 1)), sy = rect.height / CGFloat(max(canvasHeight, 1))
        return CGRect(x: CGFloat(f.x) * sx, y: rect.height - CGFloat(f.y + f.height) * sy,
                      width: CGFloat(f.width) * sx, height: CGFloat(f.height) * sy)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func cgColor(hex: String) -> CGColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let rgba = s.count == 6 ? (v << 8) | 0xFF : v
        return CGColor(srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255, green: CGFloat((rgba >> 16) & 0xFF) / 255,
                       blue: CGFloat((rgba >> 8) & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }
}
