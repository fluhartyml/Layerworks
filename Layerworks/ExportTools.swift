//
//  ExportTools.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import CoreText
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// REM: Build step 6a — Export (061), Share / Save to Photos (062 / 066), print setup (043).
// 061: one File ▸ Export… (⌘E) sheet through Apple's save panel. "The saved picture is the size of
// the canvas." Formats: PNG, JPEG, TIFF, HEIC, GIF, BMP, PDF, a PDF with one page per layer, an
// animated GIF from the Camera frames, and (Mac) an Icon Set — light and dark 1024 PNGs from the
// Light and Dark layers (by role, never by eye state). The Canvas tool's old extras (Print PDF, a web
// folder of PNGs, every app-icon size) live HERE, on the one sheet. 048: exports keep only what is
// inside the mask. 066: Share is ShareLink (Messages, Mail, AirDrop, Save to Photos — 062's lost
// idea, through the system share sheet). Save to Desktop stays CUT (t848s2359): pick Desktop here.

nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png = "PNG", jpeg = "JPEG", tiff = "TIFF", heic = "HEIC", gif = "GIF", bmp = "BMP"
    case pdf = "PDF", layersPDF = "PDF, one page per layer", animatedGIF = "Animated GIF (Camera frames)"
    case printPDF = "Print PDF (bleed and marks)", web = "Web folder of PNGs", appIcons = "Every app-icon size"
    case iconSet = "Icon Set (light and dark)"
    var id: String { rawValue }

    var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .tiff: .tiff
        case .heic: .heic
        case .gif, .animatedGIF: .gif
        case .bmp: .bmp
        case .pdf, .layersPDF, .printPDF: .pdf
        case .web, .appIcons, .iconSet: .folder
        }
    }

    static var available: [ExportFormat] {
        #if os(macOS)
        allCases
        #else
        allCases.filter { $0 != .iconSet }
        #endif
    }
}

/// Print setup (043): kept with the document, used by Print PDF.
nonisolated struct PrintSetup: Codable, Equatable, Sendable {
    var bleedInches: Double = 0.125
    var safeInches: Double = 0
    var cropMarks = true
    var registrationMarks = false
    var cmyk = false
}

nonisolated enum Exporter {
    /// The picture, canvas size, with the mask applied (048). `layers` lets the Icon Set pick floors.
    static func picture(_ m: ProjectManifest, layers: [Layer]? = nil, blobs: [String: Data], scale: Double = 1) -> CGImage? {
        let w = max(1, Int(Double(m.canvasWidth) * scale)), h = max(1, Int(Double(m.canvasHeight) * scale))
        guard let full = Compositor.image(layers: layers ?? m.layers, blobs: blobs, width: m.canvasWidth, height: m.canvasHeight)
        else { return nil }
        var b = Bitmap(width: w, height: h)
        b.draw { ctx, rect in
            if let mask = m.mask {
                ctx.scaleBy(x: rect.width / CGFloat(m.canvasWidth), y: rect.height / CGFloat(m.canvasHeight))
                clip(ctx, to: mask, canvasHeight: m.canvasHeight)
                ctx.draw(full, in: CGRect(x: 0, y: 0, width: m.canvasWidth, height: m.canvasHeight))
            } else {
                ctx.interpolationQuality = .high
                ctx.draw(full, in: rect)
            }
        }
        return b.cgImage()
    }

    /// Clips a canvas-sized context (y up) to the mask's shape.
    static func clip(_ ctx: CGContext, to mask: MaskSpec, canvasHeight: Int) {
        let r = CGRect(x: CGFloat(mask.rect.x), y: CGFloat(canvasHeight - mask.rect.y - mask.rect.height),
                       width: CGFloat(mask.rect.width), height: CGFloat(mask.rect.height))
        switch mask.shape {
        case .rectangle: ctx.addRect(r); ctx.clip()
        case .oval: ctx.addEllipse(in: r); ctx.clip()
        case .polygon, .star:
            ctx.addPath(MaskPath.path(mask.shape, in: r).cgPath); ctx.clip()
        case .character:
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, r.height * 0.9, nil)
            var glyph = CGGlyph(), ch = Array((mask.text?.first.map(String.init) ?? "A").utf16)
            CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1)
            if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
                let box = path.boundingBox
                var t = CGAffineTransform(translationX: r.midX - box.midX, y: r.midY - box.midY)
                if let moved = path.copy(using: &t) { ctx.addPath(moved); ctx.clip() }
            }
        case .symbol:
            if let s = ContentRender.symbol(SymbolContent(name: mask.text ?? "star.fill", colorHex: "#000000"), points: r.height) {
                let fit = min(r.width / CGFloat(s.width), r.height / CGFloat(s.height))
                let w = CGFloat(s.width) * fit, h = CGFloat(s.height) * fit
                ctx.clip(to: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h), mask: s)
            }
        }
    }

    static func data(_ image: CGImage, type: UTType, quality: Double = 0.9) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// PDF pages at the document's resolution (72 points per inch).
    static func pdf(_ pages: [CGImage], ppi: Int) -> Data? {
        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out), let first = pages.first else { return nil }
        let scale = 72 / Double(max(ppi, 1))
        var box = CGRect(x: 0, y: 0, width: Double(first.width) * scale, height: Double(first.height) * scale)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for page in pages {
            ctx.beginPDFPage(nil)
            ctx.draw(page, in: box)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out as Data
    }

    /// Print PDF (043): the picture plus bleed, with crop and registration marks, RGB or CMYK.
    static func printPDF(_ image: CGImage, ppi: Int, setup: PrintSetup) -> Data? {
        let pt = 72 / Double(max(ppi, 1))
        let trimW = Double(image.width) * pt, trimH = Double(image.height) * pt
        let bleed = setup.bleedInches * 72, margin = (setup.cropMarks || setup.registrationMarks) ? 36.0 : 0
        var box = CGRect(x: 0, y: 0, width: trimW + 2 * (bleed + margin), height: trimH + 2 * (bleed + margin))
        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        var picture = image
        if setup.cmyk, let space = CGColorSpace(name: CGColorSpace.genericCMYK),
           let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                             space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) {
            c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            picture = c.makeImage() ?? image
        }
        ctx.beginPDFPage(nil)
        let trim = CGRect(x: margin + bleed, y: margin + bleed, width: trimW, height: trimH)
        // The picture fills the bleed too (it is stretched by the bleed width on each side).
        ctx.draw(picture, in: trim.insetBy(dx: -bleed, dy: -bleed))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(0.25)
        if setup.cropMarks {
            for (x, y) in [(trim.minX, trim.minY), (trim.maxX, trim.minY), (trim.minX, trim.maxY), (trim.maxX, trim.maxY)] {
                let sx: CGFloat = x == trim.minX ? -1 : 1, sy: CGFloat = y == trim.minY ? -1 : 1
                ctx.move(to: CGPoint(x: x + sx * (bleed + 4), y: y)); ctx.addLine(to: CGPoint(x: x + sx * (bleed + 24), y: y))
                ctx.move(to: CGPoint(x: x, y: y + sy * (bleed + 4))); ctx.addLine(to: CGPoint(x: x, y: y + sy * (bleed + 24)))
            }
            ctx.strokePath()
        }
        if setup.registrationMarks {
            for c in [CGPoint(x: box.midX, y: 14), CGPoint(x: box.midX, y: box.maxY - 14),
                      CGPoint(x: 14, y: box.midY), CGPoint(x: box.maxX - 14, y: box.midY)] {
                ctx.strokeEllipse(in: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
                ctx.move(to: CGPoint(x: c.x - 9, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + 9, y: c.y))
                ctx.move(to: CGPoint(x: c.x, y: c.y - 9)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + 9))
                ctx.strokePath()
            }
        }
        if setup.safeInches > 0 {
            ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0.6, blue: 1, alpha: 0.6))
            ctx.stroke(trim.insetBy(dx: setup.safeInches * 72, dy: setup.safeInches * 72))
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return out as Data
    }

    static func animatedGIF(_ frames: [CGImage], fps: Double) -> Data? {
        let out = NSMutableData()
        guard !frames.isEmpty,
              let dest = CGImageDestinationCreateWithData(out, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / max(fps, 1)]] as CFDictionary
        for f in frames { CGImageDestinationAddImage(dest, f, props) }
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static let appIconSizes = [16, 20, 29, 32, 40, 58, 60, 64, 76, 80, 87, 120, 128, 152, 167, 180, 256, 512, 1024]

    /// Builds what the save panel writes.
    static func wrapper(_ format: ExportFormat, manifest m: ProjectManifest, blobs: [String: Data],
                        name: String, fps: Double, setup: PrintSetup) -> FileWrapper? {
        func file(_ data: Data?, _ n: String) -> (String, FileWrapper)? {
            guard let data else { return nil }
            let f = FileWrapper(regularFileWithContents: data); f.preferredFilename = n; return (n, f)
        }
        func folder(_ files: [(String, FileWrapper)?]) -> FileWrapper {
            FileWrapper(directoryWithFileWrappers: Dictionary(files.compactMap { $0 }, uniquingKeysWith: { a, _ in a }))
        }
        switch format {
        case .png, .jpeg, .tiff, .heic, .gif, .bmp:
            guard let img = picture(m, blobs: blobs), let d = data(img, type: format.type) else { return nil }
            return FileWrapper(regularFileWithContents: d)
        case .pdf:
            guard let img = picture(m, blobs: blobs), let d = pdf([img], ppi: m.ppi) else { return nil }
            return FileWrapper(regularFileWithContents: d)
        case .layersPDF:
            let pages = m.layers.filter(\.isVisible).compactMap { l -> CGImage? in picture(m, layers: [l], blobs: blobs) }
            guard let d = pdf(pages, ppi: m.ppi) else { return nil }
            return FileWrapper(regularFileWithContents: d)
        case .printPDF:
            guard let img = picture(m, blobs: blobs), let d = printPDF(img, ppi: m.ppi, setup: setup) else { return nil }
            return FileWrapper(regularFileWithContents: d)
        case .animatedGIF:
            let frames = m.frames.compactMap { blobs[$0.image].flatMap(Compositor.decode) }
            let pictures = frames.isEmpty ? [picture(m, blobs: blobs)].compactMap { $0 } : frames
            guard let d = animatedGIF(pictures, fps: fps) else { return nil }
            return FileWrapper(regularFileWithContents: d)
        case .web:
            return folder([file(picture(m, blobs: blobs, scale: 0.5).flatMap { data($0, type: .png) }, "\(name).png"),
                           file(picture(m, blobs: blobs).flatMap { data($0, type: .png) }, "\(name)@2x.png")])
        case .appIcons:
            return folder(appIconSizes.map { s in
                file(picture(m, blobs: blobs, scale: Double(s) / Double(max(m.canvasWidth, m.canvasHeight)))
                        .flatMap { data($0, type: .png) }, "icon-\(s).png")
            })
        case .iconSet:
            // Light appearance: the Light floor + content; Dark: the Dark floor + content (by role).
            func appearance(_ role: LayerRole) -> CGImage? {
                let ls = m.layers.compactMap { l -> Layer? in
                    if l.role.isBackground { guard l.role == role else { return nil }; var v = l; v.isVisible = true; return v }
                    return l
                }
                return picture(m, layers: ls, blobs: blobs, scale: 1024 / Double(max(m.canvasWidth, m.canvasHeight)))
            }
            return folder([file(appearance(.light).flatMap { data($0, type: .png) }, "\(name)-light-1024.png"),
                           file(appearance(.dark).flatMap { data($0, type: .png) }, "\(name)-dark-1024.png")])
        }
    }
}

struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [] }
    static var writableContentTypes: [UTType] { [.png, .jpeg, .tiff, .heic, .gif, .bmp, .pdf, .folder] }
    var wrapper: FileWrapper
    init(wrapper: FileWrapper) { self.wrapper = wrapper }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

/// File ▸ Export… (⌘E): pick a format, then Apple's save panel.
struct ExportSheet: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.export.format") private var format = ExportFormat.png
    @AppStorage("lw.cam.fps") private var fps = 8.0
    @State private var file: ExportFile?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.available) { Text($0.rawValue).tag($0) }
                }
                .accessibilityLabel("Format")
                LabeledContent("Size", value: "\(document.manifest.canvasWidth) × \(document.manifest.canvasHeight) pixels")
                if document.manifest.mask != nil {
                    Text("Only what is inside the mask is exported.").foregroundStyle(.secondary)
                }
                if format == .printPDF { PrintSetupFields(document: document) }
                if format == .animatedGIF {
                    Text(document.manifest.frames.isEmpty ? "No Camera frames yet: the GIF will be the picture alone."
                                                          : "\(document.manifest.frames.count) frames at \(Int(fps)) per second (the Lightbox speed).")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Export…", action: prepare).keyboardShortcut(.defaultAction) }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .fileExporter(isPresented: $saving, document: file, contentType: format.type, defaultFilename: baseName) { result in
            switch result {
            case .success(let url): editor.status = "Exported \(url.lastPathComponent)"
            case .failure(let error): editor.status = "Export failed: \(error.localizedDescription)"
            }
            dismiss()
        }
    }

    private var baseName: String { "Layerworks Picture" }

    private func prepare() {
        guard let w = Exporter.wrapper(format, manifest: document.manifest, blobs: document.blobs, name: baseName,
                                       fps: fps, setup: document.manifest.printSetup) else {
            editor.status = "That export couldn't be made"; return
        }
        file = ExportFile(wrapper: w)
        saving = true
    }
}

struct PrintSetupFields: View {
    @ObservedObject var document: LayerworksDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let s = document.manifest.printSetup
        Section("Print setup") {
            Stepper(value: binding(\.bleedInches), in: 0...1, step: 0.0625) {
                Text("Bleed \(s.bleedInches, specifier: "%.3g") in")
            }
            .accessibilityLabel("Bleed")
            Stepper(value: binding(\.safeInches), in: 0...2, step: 0.0625) {
                Text("Safe margin \(s.safeInches, specifier: "%.3g") in")
            }
            .accessibilityLabel("Safe margin")
            Toggle("Crop marks", isOn: binding(\.cropMarks)).accessibilityLabel("Crop marks")
            Toggle("Registration marks", isOn: binding(\.registrationMarks)).accessibilityLabel("Registration marks")
            Picker("Color", selection: binding(\.cmyk)) { Text("RGB").tag(false); Text("CMYK").tag(true) }
                .accessibilityLabel("Color")
        }
    }

    private func binding<T>(_ key: WritableKeyPath<PrintSetup, T>) -> Binding<T> {
        Binding(get: { document.manifest.printSetup[keyPath: key] },
                set: { v in var p = document.manifest.printSetup; p[keyPath: key] = v; document.setPrintSetup(p, undoManager: undoManager) })
    }
}

extension LayerworksDocument {
    func setPrintSetup(_ p: PrintSetup, undoManager: UndoManager?) {
        let old = manifest.printSetup
        guard old != p else { return }
        manifest.printSetup = p
        undoManager?.registerUndo(withTarget: self) { $0.setPrintSetup(old, undoManager: undoManager) }
        undoManager?.setActionName("Print Setup")
    }

}

/// A PNG of the picture, for ShareLink — drawn only when the person actually shares.
struct SharedPicture: Transferable {
    let manifest: ProjectManifest
    let blobs: [String: Data]
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let img = Exporter.picture(item.manifest, blobs: item.blobs),
                  let data = Exporter.data(img, type: .png) else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        .suggestedFileName("Layerworks Picture.png")
    }
}

struct ExportCommands: Commands {
    @FocusedObject private var editor: EditorState?
    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export…") { editor?.exporting = true }
                .keyboardShortcut("e")
                .disabled(editor == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { editor?.printing = true }
                .keyboardShortcut("p")
                .disabled(editor == nil)
        }
    }
}

/// File ▸ Print… — Apple's print panel with the picture (mask applied).
enum PrintPicture {
    @MainActor static func run(_ document: LayerworksDocument, _ editor: EditorState) {
        guard let image = Exporter.picture(document.manifest, blobs: document.blobs) else { return }
        #if os(macOS)
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: image.width, height: image.height))
        view.image = NSImage(cgImage: image, size: view.frame.size)
        view.imageScaling = .scaleProportionallyUpOrDown
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit; info.verticalPagination = .fit
        NSPrintOperation(view: view, printInfo: info).run()
        editor.status = "Sent to the printer"
        #else
        let controller = UIPrintInteractionController.shared
        controller.printingItem = UIImage(cgImage: image)
        controller.present(animated: true) { _, done, _ in if done { editor.status = "Sent to the printer" } }
        #endif
    }
}
