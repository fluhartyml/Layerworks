//
//  CameraTool.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// REM: Build step 4e2b — Camera, stop motion and the Lightbox (058).
// "Capture stamps everything visible onto a new top layer and copies it for paste … see-through or
// solid background, a larger size, trim to the picture. Each capture replaces the previous copy.
// Animation mode: each capture is a frame … a move not captured is not kept. Onion skin shows the
// last few frames. Play, speed, Loop, Exit preview. Frames between + Generate draws in-betweens.
// Slow in + out eases motion." Each frame keeps its layers, so Generate moves the layers between
// two frames (real in-betweens), not a cross-fade. "Use the system camera picker where the
// platform already provides one": Apple's camera on iPhone / iPad; on the Mac, Apple's
// File ▸ Import from iPhone.

nonisolated struct AnimFrame: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var layers: [Layer]
    /// The frame's picture, by hash.
    var image: String
    /// True for frames Generate drew between two captures.
    var generated = false
}

extension LayerworksDocument {
    /// The visible picture at full size, optionally on a solid background and trimmed.
    func capture(solid: Bool, trim: Bool, scale: Int) -> CGImage? {
        var layers = manifest.layers
        if solid { layers.insert(Layer(name: "", role: .content, fillHex: "#FFFFFF"), at: 0) }
        guard var image = Compositor.image(layers: layers, blobs: blobs, width: manifest.canvasWidth,
                                           height: manifest.canvasHeight) else { return nil }
        if trim, let box = Self.opaqueBounds(image) { image = image.cropping(to: box) ?? image }
        guard scale > 1 else { return image }
        var b = Bitmap(width: image.width * scale, height: image.height * scale)
        b.draw { ctx, rect in ctx.interpolationQuality = .none; ctx.draw(image, in: rect) }
        return b.cgImage()
    }

    /// The smallest box holding every pixel that is not clear.
    static func opaqueBounds(_ image: CGImage) -> CGRect? {
        let b = Bitmap(image: image, width: image.width, height: image.height)
        var minX = b.width, minY = b.height, maxX = -1, maxY = -1
        for y in 0..<b.height { for x in 0..<b.width where b.pixels[(y * b.width + x) * 4 + 3] > 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Capture (not animating): a new top layer named "Capture N".
    func addCapture(_ image: CGImage, undoManager: UndoManager?) -> UUID? {
        guard let png = Compositor.pngData(image) else { return nil }
        var n = 1
        while layers.contains(where: { $0.name == "Capture \(n)" }) { n += 1 }
        var layer = Layer(name: "Capture \(n)", role: .content, image: store(png))
        layer.frame = centeredFrame(image.width, image.height)
        commit("Capture", undoManager: undoManager) { $0.append(layer) }
        return layer.id
    }

    /// Frames are the animation, not pictures in History; Undo still takes a change back.
    func setFrames(_ frames: [AnimFrame], title: String, undoManager: UndoManager?) {
        let old = manifest.frames
        manifest.frames = frames
        undoManager?.registerUndo(withTarget: self) { $0.setFrames(old, title: title, undoManager: undoManager) }
        undoManager?.setActionName(title)
    }

    func captureFrame(undoManager: UndoManager?) {
        guard let image = Compositor.image(layers: manifest.layers, blobs: blobs, width: manifest.canvasWidth,
                                           height: manifest.canvasHeight),
              let png = Compositor.pngData(image) else { return }
        setFrames(manifest.frames + [AnimFrame(layers: manifest.layers, image: store(png))],
                  title: "Capture Frame", undoManager: undoManager)
    }

    /// Generate (058): `between` in-betweens for every pair of captured frames. Layers present in
    /// both frames glide (place, size, turn, see-through); with Slow in + out they ease.
    func generateInBetweens(_ between: Int, ease: Bool, undoManager: UndoManager?) {
        let keys = manifest.frames.filter { !$0.generated }
        guard keys.count >= 2, between > 0 else { return }
        var out: [AnimFrame] = []
        for (a, b) in zip(keys, keys.dropFirst()) {
            out.append(a)
            for k in 1...between {
                var t = Double(k) / Double(between + 1)
                if ease { t = t * t * (3 - 2 * t) }
                let layers = a.layers.map { la -> Layer in
                    guard let lb = b.layers.first(where: { $0.id == la.id }) else { return la }
                    var l = la
                    let fa = frame(of: la), fb = frame(of: lb)
                    func mix(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
                    l.frame = PixelRect(x: mix(fa.x, fb.x), y: mix(fa.y, fb.y), width: mix(fa.width, fb.width), height: mix(fa.height, fb.height))
                    let ra = la.rotation ?? 0, rb = lb.rotation ?? 0
                    l.rotation = ra + (rb - ra) * t
                    l.opacity = la.opacity + (lb.opacity - la.opacity) * t
                    return l
                }
                guard let img = Compositor.image(layers: layers, blobs: blobs, width: manifest.canvasWidth,
                                                 height: manifest.canvasHeight),
                      let png = Compositor.pngData(img) else { continue }
                out.append(AnimFrame(layers: layers, image: store(png), generated: true))
            }
        }
        out.append(keys.last!)
        setFrames(out, title: "Generate In-betweens", undoManager: undoManager)
    }
}

enum Clipboard {
    static func put(_ image: CGImage) {
        #if canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))])
        #else
        UIPasteboard.general.image = UIImage(cgImage: image)
        #endif
    }
}

struct CameraToolView: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.cam.solid") private var solid = false
    @AppStorage("lw.cam.trim") private var trim = false
    @AppStorage("lw.cam.scale") private var scale = 1
    @AppStorage("lw.cam.animate") private var animate = false
    @AppStorage("lw.cam.onion") private var onion = 2
    @AppStorage("lw.cam.between") private var between = 3
    @AppStorage("lw.cam.ease") private var ease = true
    @AppStorage("lw.cam.fps") private var fps = 8.0
    @AppStorage("lw.cam.loop") private var loop = true
    @State private var takingPhoto = false

    var body: some View {
        Section {
            Button(animate ? "Capture Frame" : "Capture", action: capture)
            Toggle("Animation mode", isOn: $animate).accessibilityLabel("Animation mode")
            if !animate {
                Toggle("Solid background", isOn: $solid).accessibilityLabel("Solid background")
                Toggle("Trim to the picture", isOn: $trim).accessibilityLabel("Trim to the picture")
                Picker("Size", selection: $scale) {
                    Text("Actual size").tag(1); Text("2×").tag(2); Text("4×").tag(4)
                }
                Text("Capture stamps everything visible onto a new top layer and copies it for pasting (Messages and so on). Each capture replaces the previous copy.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo…") { takingPhoto = true }
            }
            #endif
        } header: { Text("Camera") }
        #if os(iOS)
        .sheet(isPresented: $takingPhoto) {
            CameraPicker { image in
                if let image, let id = document.addPicture(image, name: "Photo", above: editor.selectedLayer,
                                                          replacing: false, undoManager: undoManager) {
                    editor.selectedLayer = id
                    editor.status = "Added a photo"
                }
                takingPhoto = false
            }
        }
        #endif

        if animate {
            Section {
                Text("\(document.manifest.frames.count) frames").accessibilityIdentifier("Frame count")
                Stepper("Onion skin: \(onion) frames", value: $onion, in: 0...5)
                Stepper("Frames between: \(between)", value: $between, in: 1...24)
                Toggle("Slow in + out", isOn: $ease).accessibilityLabel("Slow in + out")
                Button("Generate") {
                    document.generateInBetweens(between, ease: ease, undoManager: undoManager)
                    editor.status = "\(document.manifest.frames.count) frames with in-betweens"
                }
                .disabled(document.manifest.frames.filter { !$0.generated }.count < 2)
                HStack {
                    Text("Speed")
                    Slider(value: $fps, in: 1...30).accessibilityLabel("Speed")
                    Text("\(Int(fps)) fps").monospacedDigit().frame(width: 52)
                }
                Toggle("Loop", isOn: $loop).accessibilityLabel("Loop")
                HStack {
                    Button("Play") { editor.playing = true; editor.status = "Playing" }
                        .disabled(document.manifest.frames.isEmpty)
                    Spacer()
                    Button("Delete Last Frame") {
                        document.setFrames(Array(document.manifest.frames.dropLast()), title: "Delete Frame", undoManager: undoManager)
                    }
                    .disabled(document.manifest.frames.isEmpty)
                }
                .buttonStyle(.borderless)
                Button("Storyboard…") { editor.storyboarding = true }
                    .disabled(document.manifest.frames.isEmpty)
                Text("Put moving parts on their own layers, Move them, then Capture Frame again. A move that isn't captured isn't kept.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Lightbox") }
        }
    }

    private func capture() {
        if animate {
            document.captureFrame(undoManager: undoManager)
            editor.status = "Captured frame \(document.manifest.frames.count)"
            return
        }
        guard let image = document.capture(solid: solid, trim: trim, scale: scale) else { return }
        Clipboard.put(image)
        if let id = document.addCapture(image, undoManager: undoManager) {
            editor.selectedLayer = id
            editor.status = "Captured and copied (\(image.width) × \(image.height))"
        }
    }
}

/// Onion skin: the last few frames, faint, under the work (Lightbox).
struct OnionSkin: View {
    @ObservedObject var document: LayerworksDocument
    @AppStorage("lw.cam.animate") private var animate = false
    @AppStorage("lw.cam.onion") private var onion = 2

    var body: some View {
        if animate {
            ZStack {
                ForEach(Array(document.manifest.frames.suffix(onion).enumerated()), id: \.element.id) { k, f in
                    if let data = document.blobs[f.image], let img = Compositor.decode(data) {
                        Image(decorative: img, scale: 1).resizable().interpolation(.none)
                            .opacity(0.15 + 0.15 * Double(k))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Play: the frames at the chosen speed, over the canvas, until Exit.
struct LightboxPlayer: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @AppStorage("lw.cam.fps") private var fps = 8.0
    @AppStorage("lw.cam.loop") private var loop = true
    @State private var start = Date()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.85)
            TimelineView(.animation) { t in
                let frames = document.manifest.frames
                let n = Int(t.date.timeIntervalSince(start) * fps)
                let i = loop ? (frames.isEmpty ? 0 : n % frames.count) : min(n, max(frames.count - 1, 0))
                if frames.indices.contains(i), let data = document.blobs[frames[i].image], let img = Compositor.decode(data) {
                    Image(decorative: img, scale: 1).resizable().interpolation(.none).scaledToFit().padding(24)
                        .accessibilityLabel("Frame \(i + 1) of \(frames.count)")
                }
            }
            Button("Exit Preview") { editor.playing = false; editor.status = "Stopped" }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderedProminent)
                .padding(16)
        }
        .onAppear { start = Date() }
    }
}

#if os(iOS)
/// Apple's camera (058: the system camera picker where the platform provides one).
struct CameraPicker: UIViewControllerRepresentable {
    var done: (CGImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (CGImage?) -> Void
        init(done: @escaping (CGImage?) -> Void) { self.done = done }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Redraw so the photo is upright whatever way the phone was held.
            guard let photo = info[.originalImage] as? UIImage else { done(nil); return }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            done(UIGraphicsImageRenderer(size: photo.size, format: format).image { _ in photo.draw(at: .zero) }.cgImage)
        }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { done(nil) }
    }
}
#endif
