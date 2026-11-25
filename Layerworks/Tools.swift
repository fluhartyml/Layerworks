//
//  Tools.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import UniformTypeIdentifiers

// REM: Blueprint 029 / 007 — the tool box sits under the canvas in TWO rows (locked 2026-11-25:
// "Claude must make two rows work on the 390-pt 16e and the closed Duo, not fall back to three").
// The chosen tool is tinted; on the Mac, hover shows its name. The icons are Image Producer's
// own tool images, copied byte for byte (his word 2026-11-25: "use the original assets and icons").
// Only finished tools are in the box (his rule: no placeholders) — each step-4 slice adds its own.

enum Tool: String, CaseIterable, Identifiable {
    case canvas, palette, move, selection, mask, bucket, pen, eraser, eyedropper, text, symbol, image, playground, layer, cutout, lasso, adjust, camera
    var id: String { rawValue }

    var title: String {
        switch self {
        case .canvas: "Canvas"
        case .palette: "Palette"
        case .move: "Move"
        case .selection: "Selection"
        case .mask: "Mask"
        case .lasso: "Magic Lasso"
        case .layer: "Layer"
        case .cutout: "Remove Background"
        case .playground: "Image Playground"
        case .adjust: "Adjust"
        case .camera: "Camera"
        case .bucket: "Paint Bucket"
        case .pen: "Pen"
        case .eraser: "Eraser"
        case .eyedropper: "Eyedropper"
        case .text: "Text"
        case .symbol: "Symbol"
        case .image: "Image"
        }
    }

    /// Image Producer's own tool image, where it had one (copied byte for byte).
    var asset: String? {
        switch self {
        case .selection, .mask, .lasso, .layer, .cutout, .adjust, .camera: nil
        case .playground: "ImagePlayground"
        case .canvas: "CanvasTool"
        case .palette: "PaletteTool"
        case .move: "MoveTool"
        case .bucket: "BucketTool"
        case .pen: "PixelArtPenTool"
        case .eraser: "PinkEraser"
        case .eyedropper: "ColorSampleEyeDropper"
        case .text: "FontBook"
        case .symbol: "SFPickerTool"
        case .image: "PhotoTool"
        }
    }
}

// REM: Blueprint 074 — the single-letter tool keys are LOCKED (his rulings 005/005a, 11-04:
// "lock the letters in they look relatable to the command"). No modifier on purpose: he uses
// Sticky Keys, and a switch user can send one key. They are ordinary menu key equivalents in
// the Tools menu (Apple's way), not a custom key interceptor. Z was Image Producer's Zoom TOOL;
// Layerworks zooms from the View menu and the zoom panel, so Z stays reserved, unassigned.
extension Tool {
    var letter: Character {
        switch self {
        case .canvas: "c"; case .palette: "k"; case .move: "m"; case .selection: "s"
        case .mask: "q"; case .bucket: "b"; case .pen: "p"; case .eraser: "e"
        case .eyedropper: "i"; case .text: "t"; case .symbol: "y"; case .image: "g"
        case .playground: "a"; case .layer: "l"; case .cutout: "r"; case .lasso: "w"
        case .adjust: "j"; case .camera: "h"
        }
    }

    /// The name VoiceOver, Voice Control and bots use. REM 074: the canvas itself is "Canvas",
    /// so its tool is "Canvas Tool" (Image Producer's name, which bots already depend on).
    var accessibilityName: String { self == .canvas ? "Canvas Tool" : title }

    /// Hover text: "Paint Bucket (B)".
    var helpWithLetter: String { "\(title) (\(letter.uppercased()))" }
}

/// The Tools menu: every tool with its single letter.
struct ToolCommands: Commands {
    @FocusedObject private var editor: EditorState?
    var body: some Commands {
        CommandMenu("Tools") {
            ForEach(Tool.allCases) { tool in
                Button(tool.title) {
                    editor?.tool = tool
                    editor?.status = "\(tool.title) tool"
                }
                .keyboardShortcut(KeyEquivalent(tool.letter), modifiers: [])
                .disabled(editor == nil)
            }
        }
    }
}

extension Tool {
    /// Image Producer's SF Symbols for the tools that had no image of their own.
    var symbol: String {
        switch self {
        case .selection: "rectangle.dashed"
        case .mask: "theatermasks"
        case .lasso: "lasso.badge.sparkles"
        case .layer: "square.3.layers.3d.middle.filled"
        case .cutout: "person.and.background.dotted"
        case .adjust: "slider.horizontal.3"
        case .camera: "camera"
        default: "questionmark.square"
        }
    }
}

extension EditorState {
    static let toolSize: CGFloat = 44
}

struct ToolBox: View {
    @ObservedObject var editor: EditorState
    @State private var width: CGFloat = 0

    var body: some View {
        let tools = Tool.allCases
        // One row while every tool fits at 44 pt; otherwise exactly two rows, never three.
        let oneRow = CGFloat(tools.count) * (EditorState.toolSize + 4) <= width
        let perRow = oneRow ? tools.count : Int((Double(tools.count) / 2).rounded(.up))
        let rows = stride(from: 0, to: tools.count, by: max(perRow, 1)).map {
            Array(tools[$0..<min($0 + perRow, tools.count)])
        }
        // 44 pt where the width allows; on a narrow phone the row shares the width evenly (007).
        let side = width > 0 ? min(EditorState.toolSize, (width - 8) / CGFloat(max(perRow, 1)) - 4)
                             : EditorState.toolSize
        VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(rows[r]) { tool in
                        ToolButton(tool: tool, editor: editor, side: side)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
    }
}

struct ToolButton: View {
    let tool: Tool
    @ObservedObject var editor: EditorState
    let side: CGFloat

    private var chosen: Bool { editor.tool == tool }

    /// Image Producer's tool image, or the SF Symbol it used for tools without one.
    @ViewBuilder private var icon: some View {
        if let asset = tool.asset {
            Image(asset).resizable().scaledToFit()
        } else {
            Image(systemName: tool.symbol).resizable().scaledToFit().padding(4)
        }
    }

    var body: some View {
        Button {
            editor.tool = tool
            editor.status = "\(tool.title) tool"
        } label: {
            icon
                .padding(6)
                .frame(width: side, height: side)
                .background(chosen ? Color.accentColor.opacity(0.25) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(chosen ? Color.accentColor : Color.clear, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.helpWithLetter)
        .accessibilityLabel(tool.accessibilityName)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// Blueprint 029: the tool panel names the tool and the selected layer and holds that tool's
/// settings. ⓘ explains a setting.
struct ToolInspector: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Form {
            Section {
                LabeledContent("Tool", value: editor.tool.title)
                    .accessibilityIdentifier("Current tool")
                LabeledContent("Layer", value: document.layer(editor.selectedLayer)?.name ?? "None")
                    .accessibilityIdentifier("Selected layer")
            }
            switch editor.tool {
            case .canvas: CanvasToolView(document: document, editor: editor)
            case .palette: PaletteToolView(document: document, editor: editor)
            case .move: MoveToolView(document: document, editor: editor)
            case .selection: SelectionToolView(document: document, editor: editor)
            case .mask: MaskToolView(document: document, editor: editor)
            case .lasso: LassoToolView()
            case .layer: LayerToolView(document: document, editor: editor)
            case .adjust: AdjustToolView(document: document, editor: editor)
            case .playground: PlaygroundToolView(document: document, editor: editor)
            case .camera: CameraToolView(document: document, editor: editor)
            case .cutout: Section { RemoveBackgroundView(document: document, editor: editor) } header: { Text("Remove Background") }
            case .bucket: BucketToolView(document: document, editor: editor)
            case .pen: PenToolView(document: document, editor: editor)
            case .eraser: EraserToolView(document: document, editor: editor)
            case .eyedropper: EyedropperToolView(document: document, editor: editor)
            case .text: TextToolView(document: document, editor: editor)
            case .symbol: SymbolToolView(document: document, editor: editor)
            case .image: ImageToolView(document: document, editor: editor)
            }
            Section {
                Text(BuildStamp.line).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // 045: leaving the Move tool keeps the change.
        .onChange(of: editor.tool) { old, _ in
            if old == .move { editor.commitMove(document, undoManager: undoManager) }
        }
    }
}

/// A short explanation behind an ⓘ.
struct InfoTip: View {
    let text: String
    @State private var shown = false
    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel("About this setting")
            .popover(isPresented: $shown) {
                Text(text).padding().frame(maxWidth: 280).fixedSize(horizontal: false, vertical: true)
            }
    }
}

// MARK: - Canvas tool (Blueprint 042 / 043)

/// Size presets grouped by job. Screen sizes are pixels; print sizes are inches at the
/// document's resolution.
struct CanvasPreset: Identifiable {
    enum Size { case pixels(Int, Int), inches(Double, Double) }
    let name: String
    let size: Size
    var id: String { name }

    func pixels(ppi: Int) -> (Int, Int) {
        switch size {
        case .pixels(let w, let h): (w, h)
        case .inches(let w, let h): (Int((w * Double(ppi)).rounded()), Int((h * Double(ppi)).rounded()))
        }
    }

    func label(ppi: Int) -> String {
        let (w, h) = pixels(ppi: ppi)
        let shape = w == h ? "square" : (w > h ? "landscape" : "portrait")
        switch size {
        case .pixels: return "\(name) — \(w) × \(h), \(shape)"
        case .inches(let iw, let ih):
            return "\(name) — \(Self.inch(iw)) × \(Self.inch(ih)) in, \(shape)"
        }
    }

    private static func inch(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }

    static let groups: [(String, [CanvasPreset])] = [
        ("App Store Connect", [.init(name: "App icon", size: .pixels(1024, 1024)),
                               .init(name: "iPhone 6.9″ screenshot", size: .pixels(1320, 2868)),
                               .init(name: "iPad 13″ screenshot", size: .pixels(2064, 2752)),
                               .init(name: "Mac screenshot", size: .pixels(2880, 1800))]),
        ("Wallpapers", [.init(name: "iPhone", size: .pixels(1320, 2868)),
                        .init(name: "MacBook Air 15″", size: .pixels(2880, 1864)),
                        .init(name: "4K display", size: .pixels(3840, 2160))]),
        ("Social", [.init(name: "Square post", size: .pixels(1080, 1080)),
                    .init(name: "Portrait post", size: .pixels(1080, 1350)),
                    .init(name: "Story", size: .pixels(1080, 1920))]),
        ("Apple TV", [.init(name: "HD", size: .pixels(1920, 1080)),
                      .init(name: "4K", size: .pixels(3840, 2160)),
                      .init(name: "Top Shelf wide", size: .pixels(4640, 1440))]),
        ("Web ads", [.init(name: "Leaderboard", size: .pixels(728, 90)),
                     .init(name: "Medium rectangle", size: .pixels(300, 250)),
                     .init(name: "Skyscraper", size: .pixels(160, 600))]),
        ("Paper", [.init(name: "US Letter", size: .inches(8.5, 11)),
                   .init(name: "US Legal", size: .inches(8.5, 14)),
                   .init(name: "Tabloid", size: .inches(11, 17))]),
        ("Posters", [.init(name: "Poster 18 × 24", size: .inches(18, 24)),
                     .init(name: "Poster 24 × 36", size: .inches(24, 36))]),
        ("Signs & flyers", [.init(name: "Half-letter flyer", size: .inches(5.5, 8.5)),
                            .init(name: "Yard sign", size: .inches(24, 18))]),
        ("Event & stationery", [.init(name: "Postcard", size: .inches(6, 4)),
                                .init(name: "Business card", size: .inches(3.5, 2))]),
        ("Cards & envelopes", [.init(name: "Folded card 5 × 7", size: .inches(5, 7)),
                               .init(name: "A7 envelope", size: .inches(7.25, 5.25))]),
        ("Photo", [.init(name: "Photo 4 × 6", size: .inches(4, 6)),
                   .init(name: "Photo 5 × 7", size: .inches(5, 7)),
                   .init(name: "Photo 8 × 10", size: .inches(8, 10))]),
    ]
}

struct CanvasToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var width = 0
    @State private var height = 0
    @AppStorage("lw.canvas.keepRatio") private var keepRatio = false
    /// Apply ends typing, so the next ⌘Z undoes the canvas, not the digits in the box.
    @FocusState private var typing: Bool

    var body: some View {
        Section {
            HStack {
                TextField("Resolution", value: Binding(get: { document.manifest.ppi },
                                                       set: { guard $0 != document.manifest.ppi else { return }
                                                              document.setPPI($0, undoManager: undoManager)
                                                              editor.status = "Resolution \(document.manifest.ppi) ppi" }),
                          format: .number)
                    .accessibilityLabel("Resolution")
                Text("ppi").foregroundStyle(.secondary)
                InfoTip(text: "Pixels per inch when the picture is printed. 300 is standard for print — set it first, because print sizes are worked out from it.")
            }
        } header: { Text("Resolution") }

        Section {
            HStack {
                TextField("Width", value: $width, format: .number).accessibilityLabel("Width").focused($typing)
                Text("×")
                TextField("Height", value: $height, format: .number).accessibilityLabel("Height").focused($typing)
                Text("px").foregroundStyle(.secondary)
            }
            .onChange(of: width) { old, new in
                if keepRatio, old > 0, new != document.manifest.canvasWidth {
                    height = max(1, Int((Double(new) * Double(document.manifest.canvasHeight)
                                         / Double(max(document.manifest.canvasWidth, 1))).rounded()))
                }
            }
            Toggle("Keep proportions", isOn: $keepRatio).accessibilityLabel("Keep proportions")
            HStack {
                Button("Apply Size") { apply(width, height) }
                    .disabled(width == document.manifest.canvasWidth && height == document.manifest.canvasHeight)
                    .buttonStyle(.borderless)
                Spacer()
                Button("Swap Width and Height") { apply(document.manifest.canvasHeight, document.manifest.canvasWidth) }
                    .disabled(document.manifest.canvasWidth == document.manifest.canvasHeight)
                    .buttonStyle(.borderless)
                    .help("Landscape ↔ portrait. A square does not change.")
            }
            Menu("Size Presets") {
                ForEach(CanvasPreset.groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { preset in
                            Button(preset.label(ppi: document.manifest.ppi)) {
                                let (w, h) = preset.pixels(ppi: document.manifest.ppi)
                                apply(w, h)
                            }
                        }
                    }
                }
            }
        } header: { Text("Size") }
        .onAppear(perform: sync)
        .onChange(of: document.manifest.canvasWidth) { _, _ in sync() }
        .onChange(of: document.manifest.canvasHeight) { _, _ in sync() }
    }

    private func sync() {
        width = document.manifest.canvasWidth
        height = document.manifest.canvasHeight
    }

    private func apply(_ w: Int, _ h: Int) {
        typing = false
        document.resizeCanvas(width: w, height: h, undoManager: undoManager)
        sync()
        editor.canvasSize = CGSize(width: w, height: h)
        editor.fitWhole()
        editor.status = "Canvas is \(document.manifest.canvasWidth) × \(document.manifest.canvasHeight)"
    }
}

// MARK: - Palette tool (Blueprint 044)

struct PaletteToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var exporting = false
    @State private var importing = false

    private var colors: [String] { document.manifest.palette }
    private var index: Int { min(editor.colorIndex, colors.count - 1) }

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                ForEach(colors.indices, id: \.self) { i in
                    Button {
                        editor.colorIndex = i
                        editor.status = "Color \(colors[i])"
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(cgColor: Compositor.cgColor(hex: colors[i]) ?? CGColor(gray: 0, alpha: 1)))
                            .frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(i == index ? Color.accentColor : .secondary.opacity(0.4),
                                              lineWidth: i == index ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(i + 1), \(colors[i])")
                    .accessibilityAddTraits(i == index ? .isSelected : [])
                }
            }
            // Apple's own color picker changes the chosen swatch (044: no custom wheel).
            ColorPicker("Change Color", selection: Binding(
                get: { Color(cgColor: Compositor.cgColor(hex: colors[index]) ?? CGColor(gray: 0, alpha: 1)) },
                set: { set(index, to: $0) }), supportsOpacity: false)
            HStack {
                Button("Add Color") {
                    document.setPalette(colors + [colors[index]], undoManager: undoManager)
                    editor.colorIndex = colors.count - 1
                    editor.status = "Added a color"
                }
                .disabled(colors.count >= Palette.maximum)
                .buttonStyle(.borderless)
                Spacer()
                Button("Remove") {
                    var next = colors
                    next.remove(at: index)
                    document.setPalette(next, undoManager: undoManager)
                    editor.colorIndex = max(0, index - 1)
                    editor.status = "Removed a color"
                }
                .disabled(colors.count <= Palette.minimum)
                .buttonStyle(.borderless)
            }
        } header: { Text("Colors") }

        Section {
            Button("Save Palette…") { exporting = true }
            Button("Load Palette…") { importing = true }
        }
        .fileExporter(isPresented: $exporting,
                      document: PaletteDocument(file: PaletteFile(name: "Palette", colors: colors)),
                      contentType: .iconPalette, defaultFilename: "Palette") { result in
            if case .success = result { editor.status = "Palette saved" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.iconPalette]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url),
               let file = try? JSONDecoder().decode(PaletteFile.self, from: data) {
                document.setPalette(file.colors, undoManager: undoManager)
                editor.status = "Palette loaded"
            } else {
                editor.status = "That palette file couldn't be read"
            }
        }
    }

    private func set(_ i: Int, to color: Color) {
        let r = color.resolve(in: EnvironmentValues())
        let hex = String(format: "#%02X%02X%02X",
                         Int((min(max(r.red, 0), 1) * 255).rounded()),
                         Int((min(max(r.green, 0), 1) * 255).rounded()),
                         Int((min(max(r.blue, 0), 1) * 255).rounded()))
        var next = colors
        next[i] = hex
        document.setPalette(next, undoManager: undoManager)
        editor.status = "Color \(i + 1) is now \(hex)"
    }
}

extension UTType {
    /// Image Producer's palette file (.iconpalette). Imported: both apps read and write it.
    static let iconPalette = UTType(importedAs: "com.nightgard.Image-Producer.palette", conformingTo: .json)
}

struct PaletteDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.iconPalette] }
    var file: PaletteFile

    init(file: PaletteFile) { self.file = file }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        file = try JSONDecoder().decode(PaletteFile.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(file))
    }
}
