//
//  LayerworksDocument.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

// REM: Blueprint 006 / 008 / 019 / 021 — Apple's standard document model. DocumentGroup +
// ReferenceFileDocument. A new document is "Untitled" in memory; the name and place come from
// the first Save panel (his word 2026-11-25: ImageProducerNNNN is superseded). After that,
// Apple's autosave and Versions take over.
//
// REM: Blueprint 023 + Walk Q1/Q3 (approved 2026-11-25) — Layerworks is a NEW app beside Image
// Producer, so it IMPORTS Image Producer's package type instead of exporting a second claim on
// the same extensions. New files are written as .imgprd; .picprod and .iconproj stay readable.

extension UTType {
    /// Image Producer's project package (imgprd / picprod / iconproj). Imported, not exported.
    static let layerworksProject = UTType(importedAs: "com.nightgard.Image-Producer.project",
                                         conformingTo: .package)
}

/// What is on disk inside the package: `manifest.json` plus real image files (Blueprint 006:
/// never base64 every picture into one JSON).
struct ProjectManifest: Codable, Equatable {
    /// Package format written by Layerworks. Image Producer's manifests have no such key.
    var layerworksFormat: Int = 1
    var canvasWidth: Int
    var canvasHeight: Int
    /// Print resolution. Blueprint 003: 300 dpi by default.
    var ppi: Int = 300
}

final class LayerworksDocument: ReferenceFileDocument {
    typealias Snapshot = ProjectManifest

    nonisolated static var readableContentTypes: [UTType] { [.layerworksProject] }
    nonisolated static var writableContentTypes: [UTType] { [.layerworksProject] }

    @Published var manifest: ProjectManifest

    /// A new picture. Size is set in the Canvas tool (Blueprint 022: no name ask, size only).
    init(width: Int = 1024, height: Int = 1024) {
        manifest = ProjectManifest(canvasWidth: width, canvasHeight: height)
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file
        guard wrapper.isDirectory,
              let data = wrapper.fileWrappers?[PackageLayout.manifestName]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = try PackageLayout.decodeManifest(data)
        _manifest = Published(initialValue: decoded)
    }

    func snapshot(contentType: UTType) throws -> ProjectManifest { manifest }

    nonisolated func fileWrapper(snapshot: ProjectManifest,
                                 configuration: WriteConfiguration) throws -> FileWrapper {
        try PackageLayout.wrapper(for: snapshot)
    }
}

/// The package's folder layout, kept in one place so reader and writer cannot drift.
nonisolated enum PackageLayout {
    static let manifestName = "manifest.json"
    /// Blueprint 023a: Finder, Files, Spotlight and Open panels read a package's
    /// QuickLook/Thumbnail.png, so the file icon shows the picture.
    static let quickLookFolder = "QuickLook"
    static let thumbnail = "Thumbnail.png"

    static func decodeManifest(_ data: Data) throws -> ProjectManifest {
        // REM: An Image Producer manifest (no layerworksFormat key) still opens here at its
        // canvas size; its layers load once the layer model is built (Blueprint build step 3).
        struct Legacy: Decodable { var canvasWidth: Int; var canvasHeight: Int; var ppi: Int? }
        if let current = try? JSONDecoder().decode(ProjectManifest.self, from: data) {
            return current
        }
        let old = try JSONDecoder().decode(Legacy.self, from: data)
        return ProjectManifest(canvasWidth: old.canvasWidth, canvasHeight: old.canvasHeight,
                               ppi: old.ppi ?? 300)
    }

    static func wrapper(for manifest: ProjectManifest) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestFile = FileWrapper(regularFileWithContents: try encoder.encode(manifest))
        manifestFile.preferredFilename = manifestName
        var children: [String: FileWrapper] = [manifestName: manifestFile]
        if let png = thumbnailPNG(for: manifest) {
            let thumb = FileWrapper(regularFileWithContents: png)
            thumb.preferredFilename = thumbnail
            let folder = FileWrapper(directoryWithFileWrappers: [thumbnail: thumb])
            folder.preferredFilename = quickLookFolder
            children[quickLookFolder] = folder
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }


    /// A 512-pixel-max picture of the canvas for the file icon.
    static func thumbnailPNG(for manifest: ProjectManifest) -> Data? {
        let longest = max(manifest.canvasWidth, manifest.canvasHeight, 1)
        let scale = min(1.0, 512.0 / Double(longest))
        let w = max(1, Int(Double(manifest.canvasWidth) * scale))
        let h = max(1, Int(Double(manifest.canvasHeight) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
