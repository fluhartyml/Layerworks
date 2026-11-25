//
//  ContentTools.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// REM: Build step 4c — Text (053), Symbol (054), Image (055).
// 053 (2026 NOV 25): no homemade font picker — Apple's Font panel on the Mac, Apple's font
// picker on iPhone / iPad. Insert glyph = Apple's Character Viewer (Mac). Colors come from the
// palette (044). 055: imports go through the system file picker and the system Photos picker.

// MARK: - Text

struct TextToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.text.font") private var fontName = "Helvetica"
    @AppStorage("lw.text.size") private var size = 96.0
    @AppStorage("lw.text.bold") private var bold = false
    @AppStorage("lw.text.italic") private var italic = false
    @AppStorage("lw.text.underline") private var underline = false
    @AppStorage("lw.text.outline") private var outline = false
    @AppStorage("lw.text.outlineWidth") private var outlineWidth = 4.0
    @AppStorage("lw.text.threeD") private var threeD = false
    @AppStorage("lw.text.depth") private var depth = 40.0
    @AppStorage("lw.text.turn") private var turn = 25.0
    @AppStorage("lw.text.tilt") private var tilt = -15.0
    @State private var words = ""
    @State private var choosingFont = false

    /// The selected layer, when it is a text layer: the style controls edit it live.
    private var textLayer: Layer? { document.layer(editor.selectedLayer).flatMap { $0.text != nil ? $0 : nil } }

    var body: some View {
        Section {
            TextField("Type here", text: $words)
                .accessibilityLabel("Text")
                // Return makes the line a new layer and starts the next one (053).
                .onSubmit(addLine)
            HStack(spacing: 4) {
                Toggle(isOn: $bold) { Label("Bold", systemImage: "bold") }
                Toggle(isOn: $italic) { Label("Italic", systemImage: "italic") }
                Toggle(isOn: $underline) { Label("Underline", systemImage: "underline") }
                Toggle(isOn: $threeD) { Label("3D", systemImage: "cube") }
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            Button("New Text Layer", action: addLine)
                .disabled(words.trimmingCharacters(in: .whitespaces).isEmpty)
            #if os(macOS)
            Button("Insert Glyph…") { NSApp.orderFrontCharacterPalette(nil) }
                .help("Apple's Character Viewer: every glyph in every font, Wingdings included")
            #endif
        } header: { Text("Text") }

        Section {
            HStack {
                Text(fontName).lineLimit(1)
                Spacer()
                Button("Fonts…") { showFonts() }
            }
            Stepper(value: $size, in: 6...2000, step: 6) {
                Text("Size \(Int(size)) px").monospacedDigit()
            }
            .accessibilityLabel("Size")
            ColorChip(document: document, editor: editor)
            Toggle("Outline", isOn: $outline)
            if outline {
                Stepper(value: $outlineWidth, in: 1...64) { Text("Outline \(Int(outlineWidth)) px").monospacedDigit() }
                Text("The outline uses palette color 1 (\(document.manifest.palette[0])); the letters use the color in use.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if threeD {
                Stepper(value: $depth, in: 2...400, step: 4) { Text("Depth \(Int(depth)) px").monospacedDigit() }
                HStack { Text("Turn"); Slider(value: $turn, in: -80...80).accessibilityLabel("Turn"); Text("\(Int(turn))°").monospacedDigit().frame(width: 44) }
                HStack { Text("Tilt"); Slider(value: $tilt, in: -80...80).accessibilityLabel("Tilt"); Text("\(Int(tilt))°").monospacedDigit().frame(width: 44) }
            }
            if textLayer != nil {
                Button("Apply Style to Selected Text") { restyle() }
            }
        } header: { Text("Style") }
        .onChange(of: [bold, italic, underline, outline, threeD]) { _, _ in restyle() }
        .onChange(of: [depth, turn, tilt]) { _, _ in restyle() }
        .onChange(of: size) { _, _ in restyle() }
        .onChange(of: outlineWidth) { _, _ in restyle() }
        .onChange(of: fontName) { _, _ in restyle() }
        #if os(iOS)
        .sheet(isPresented: $choosingFont) {
            FontPicker { fontName = $0; choosingFont = false }
        }
        #endif
    }

    private func style(_ s: String) -> TextContent {
        TextContent(string: s, fontName: fontName, size: size, colorHex: editor.color(in: document),
                    bold: bold, italic: italic, underline: underline,
                    outlineHex: outline ? document.manifest.palette[0] : nil, outlineWidth: outlineWidth,
                    depth: threeD ? depth : nil, turn: turn, tilt: tilt)
    }

    private func addLine() {
        let s = words.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        if let id = document.addText(style(s), above: editor.selectedLayer, undoManager: undoManager) {
            editor.selectedLayer = id
            editor.status = "Added text “\(s)”"
        }
        words = ""
    }

    /// Live style: changes apply to the selected text layer at once.
    private func restyle() {
        guard let layer = textLayer, let t = layer.text else { return }
        document.updateText(layer.id, style(t.string), undoManager: undoManager)
        editor.status = "Restyled “\(layer.name)”"
    }

    private func showFonts() {
        #if os(macOS)
        FontPanelBridge.shared.show(current: fontName, size: size) { name, newSize in
            fontName = name
            size = newSize
        }
        #else
        choosingFont = true
        #endif
    }
}

#if os(macOS)
/// Apple's Font panel, reporting the chosen face and size back to the Text tool.
final class FontPanelBridge: NSObject {
    static let shared = FontPanelBridge()
    private var onChange: ((String, Double) -> Void)?
    private var font = NSFont.systemFont(ofSize: 96)

    func show(current name: String, size: Double, onChange: @escaping (String, Double) -> Void) {
        self.onChange = onChange
        font = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(font, isMultiple: false)
        manager.orderFrontFontPanel(nil)
    }

    @objc func changeFont(_ sender: Any?) {
        font = NSFontManager.shared.convert(font)
        onChange?(font.fontName, Double(font.pointSize))
    }
}
#else
/// Apple's font picker on iPhone and iPad.
struct FontPicker: UIViewControllerRepresentable {
    var picked: (String) -> Void

    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let controller = UIFontPickerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIFontPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }

    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        let picked: (String) -> Void
        init(picked: @escaping (String) -> Void) { self.picked = picked }
        func fontPickerViewControllerDidPickFont(_ controller: UIFontPickerViewController) {
            if let d = controller.selectedFontDescriptor {
                picked(UIFont(descriptor: d, size: 12).fontName)
            }
        }
    }
}
#endif

// MARK: - Symbol

struct SymbolToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var search = ""
    @State private var chosen = "star.fill"

    /// The starting set; search takes any SF Symbol name.
    static let starting = ["star.fill", "heart.fill", "sun.max.fill", "moon.fill", "cloud.fill", "bolt.fill",
                           "leaf.fill", "flame.fill", "drop.fill", "snowflake", "music.note", "camera.fill",
                           "house.fill", "car.fill", "airplane", "bicycle", "pawprint.fill", "fish.fill",
                           "cup.and.saucer.fill", "gift.fill", "bell.fill", "flag.fill", "trophy.fill",
                           "crown.fill", "gamecontroller.fill", "paintbrush.fill", "pencil", "book.fill",
                           "globe.americas.fill", "checkmark.seal.fill", "sparkles", "wand.and.stars"]

    private var results: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.starting }
        var out = Self.starting.filter { $0.contains(q) }
        if ContentRender.symbolExists(q), !out.contains(q) { out.insert(q, at: 0) }
        return out
    }

    private var color: String { editor.color(in: document) }

    var body: some View {
        Section {
            TextField("Search symbols", text: $search).accessibilityLabel("Search symbols")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                ForEach(results, id: \.self) { name in
                    Button { chosen = name } label: {
                        Image(systemName: name)
                            .font(.title2)
                            .foregroundStyle(Color(cgColor: Compositor.cgColor(hex: color) ?? CGColor(gray: 0, alpha: 1)))
                            .frame(width: 44, height: 44)
                            .background(chosen == name ? Color.accentColor.opacity(0.25) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(chosen == name ? .isSelected : [])
                }
            }
            ColorChip(document: document, editor: editor)
        } header: { Text("Symbol — preview: \(chosen)") }

        Section {
            Button("Create New Layer") {
                if let id = document.addSymbol(SymbolContent(name: chosen, colorHex: color),
                                               above: editor.selectedLayer, replacing: false, undoManager: undoManager) {
                    editor.selectedLayer = id
                    editor.status = "Added \(chosen)"
                }
            }
            Button("Apply to Selected Layer") {
                _ = document.addSymbol(SymbolContent(name: chosen, colorHex: color),
                                       above: editor.selectedLayer, replacing: true, undoManager: undoManager)
                editor.status = "Swapped to \(chosen)"
            }
            .disabled(document.layer(editor.selectedLayer)?.symbol == nil)
            .help("Swap or recolor the selected symbol; size and place stay")
            Text("SF Symbols are Apple's: fine in pictures, never in an app icon or logo.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Image

struct ImageToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @State private var importing = false
    @State private var replacing = false
    @State private var photo: PhotosPickerItem?

    /// PNG, JPEG, HEIC, TIFF, GIF, BMP — and PSD on the Mac (055).
    static var types: [UTType] {
        var t: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        #if os(macOS)
        if let psd = UTType("com.adobe.photoshop-image") { t.append(psd) }
        #endif
        return t
    }

    var body: some View {
        Section {
            Button("Import Image to New Layer…") { replacing = false; importing = true }
            Button("Import Image to Selected Layer…") { replacing = true; importing = true }
                .disabled(editor.selectedLayer == nil)
            PhotosPicker("Choose from Photos…", selection: $photo, matching: .images)
            Text("Place and size it with Move.").font(.callout).foregroundStyle(.secondary)
        } header: { Text("Image") }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.types) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let image = ContentRender.picture(at: url) else {
                editor.status = "That picture couldn't be read"; return
            }
            add(image, name: url.deletingPathExtension().lastPathComponent)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = ContentRender.picture(data: data) {
                    add(image, name: "Photo")
                } else {
                    editor.status = "That photo couldn't be read"
                }
                photo = nil
            }
        }
    }

    private func add(_ image: CGImage, name: String) {
        if let id = document.addPicture(image, name: name, above: editor.selectedLayer,
                                        replacing: replacing, undoManager: undoManager) {
            editor.selectedLayer = id
            editor.status = "Imported “\(name)”"
        }
    }
}

// MARK: - New from Import… (055)

extension LayerworksDocument {
    /// An Untitled picture made from a file. The original file is never written (021 / 025).
    convenience init(importing image: CGImage, name: String) {
        self.init(width: image.width, height: image.height)
        if let png = Compositor.pngData(image) {
            let layer = Layer(name: name, role: .content, image: store(png))
            var m = manifest
            m.layers.append(layer)
            m.history = [HistoryStep(title: "Original", layers: m.layers,
                                     canvasWidth: m.canvasWidth, canvasHeight: m.canvasHeight)]
            manifest = m
        }
    }
}

#if os(macOS)
struct NewFromImportCommand: Commands {
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            #if os(macOS)
            // REM: Mac only for now — iPhone / iPad start a picture from Apple's document browser,
            // then use Image ▸ Import (no dead menu item on iPad's keyboard menu).
            Button("New from Import…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = ImageToolView.types + [.pdf]
                guard panel.runModal() == .OK, let url = panel.url,
                      let image = ContentRender.picture(at: url) else { return }
                let name = url.deletingPathExtension().lastPathComponent
                newDocument { LayerworksDocument(importing: image, name: name) }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            #endif
        }
    }
}
#endif
