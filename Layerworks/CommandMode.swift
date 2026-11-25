//
//  CommandMode.swift
//  Layerworks
//
//  Build step 7b — Blueprint 075: command mode for bots (no window).
//
//  REM: his rule — "when he says API for his app he means a CLI MODE": one file, run from the
//  App's init(). 075: "Rebuild this as a clean CLI on the new document model, not by lifting
//  CLIRunner.swift." Every step calls the SAME document functions the panels call.
//
//  Run (Mac only):
//    Layerworks.app/Contents/MacOS/Layerworks --command job.json
//    Layerworks.app/Contents/MacOS/Layerworks --help
//
//  The app stays sandboxed (App Store), so every name in a job is a plain file name inside the
//  JOB FOLDER — no "/", "~" or "..":
//    • the folder chosen once in Layerworks ▸ Settings… (kept as a security-scoped bookmark;
//      command mode never shows a window, so it can't ask), or until then
//    • the app's own Command folder: ~/Library/Containers/com.nightgard.Layerworks/Data/Documents/Command
//
//  Job file:
//    { "name": "Two cats", "width": 1024, "height": 1024,
//      "steps": [ { "do": "addImage", "file": "cat.png" },
//                 { "do": "removeBackground" },
//                 { "do": "magicErase", "color": "#FFFFFF", "tolerance": 24 },
//                 { "do": "merge" },
//                 { "do": "resize", "width": 512 },
//                 { "do": "exportPNG", "file": "out.png" },
//                 { "do": "saveProject", "file": "out.layerworks" } ] }
//  Each step acts on the TOP visible picture layer. A job starts Untitled, in memory only (075
//  ALIGN): nothing is written until exportPNG / saveProject. "open" starts from a saved project.
//  Output: one "ok" or "FAIL" line per step, then <job name>.status.json in the job folder.
//  Exit 0 = every step ok, 1 = a step failed (earlier steps' files are kept), 2 = usage error.
//
//  ⚠️ Image Playground needs a person: Apple's sheet has no headless Done. The imagePlayground
//  step saves the project and stops, and says so (075).
//

import Foundation

#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CommandMode {
    static let bookmarkKey = "lw.command.folderBookmark"

    /// Called first thing from LayerworksApp.init(). Returns only when there is no command.
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") { print(usage); exit(0) }
        guard let i = args.firstIndex(of: "--command") else { return }
        guard i + 1 < args.count else { fail("--command needs a job file name"); exit(2) }
        let code = MainActor.assumeIsolated { run(jobName: args[i + 1]) }
        exit(code)
    }

    static let usage = """
    Layerworks command mode (no window)

      Layerworks --command <job.json>    run a job file from the job folder
      Layerworks --help                  show this

    Job folder: the one chosen in Layerworks ▸ Settings…, or until then
      ~/Library/Containers/com.nightgard.Layerworks/Data/Documents/Command
    Every name in a job is a plain file name in that folder (no /, ~ or ..).

    Job: { "name": "...", "width": 1024, "height": 1024, "steps": [ { "do": "...", ... } ] }
    Steps (each acts on the top visible picture layer):
      open          file: a .layerworks (or Image Producer .imgprd) to start from
      addImage      file: a picture, added as a new top layer
      removeBackground
      magicErase    color: "#FFFFFF" (default), tolerance: 0–100 (default 24)
      merge         all visible picture layers into one
      resize        width or height: scales the whole picture, keeps its shape
      crop          width, height: a smaller canvas, centered
      extend        width, height: a bigger canvas, centered
      scaleToFit    width, height: scales the picture to fit, then sets that canvas
      exportPNG     file: the picture as a PNG
      saveProject   file: a .layerworks project you can open and keep working on
      imagePlayground  saves the project and stops: Image Playground needs a person
    Output: one ok or FAIL line per step, then <name>.status.json.
    Exit: 0 ok, 1 a step failed (earlier steps kept), 2 usage error.
    """

    // MARK: The job folder

    /// The chosen folder (security-scoped), or the app's own Command folder.
    static func jobFolder() -> (URL, scoped: Bool) {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                  bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                             relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                }
                return (url, true)
            }
        }
        return (containerFolder, false)
    }

    static var containerFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Command", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A plain name inside the folder, or nil (absolute paths and climbing out are refused, not guessed).
    static func file(_ name: String?, in folder: URL) -> URL? {
        guard let name, !name.isEmpty, !name.contains("/"), !name.hasPrefix("~"), name != "..", name != "." else { return nil }
        return folder.appendingPathComponent(name)
    }

    // MARK: Running a job

    struct Job: Decodable {
        var name: String
        var width: Int?
        var height: Int?
        var steps: [Step]
    }

    struct Step: Decodable {
        var `do`: String
        var file: String?
        var color: String?
        var tolerance: Double?
        var width: Int?
        var height: Int?
    }

    struct StepResult: Encodable {
        var step: Int
        var `do`: String
        var ok: Bool
        var message: String
    }

    struct Status: Encodable {
        var name: String
        var result: String   // "ok", "failed" or "stopped"
        var finished: Date
        var steps: [StepResult]
    }

    @MainActor static func run(jobName: String) -> Int32 {
        let (folder, scoped) = jobFolder()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let jobURL = file(jobName, in: folder) else {
            fail("\"\(jobName)\" must be a plain file name in the job folder (\(folder.path))"); return 2
        }
        let job: Job
        do {
            job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: jobURL))
        } catch {
            fail("couldn't read the job \(jobName) in \(folder.path): \(error.localizedDescription)"); return 2
        }
        guard !job.steps.isEmpty else { fail("the job has no steps"); return 2 }

        var document = LayerworksDocument(width: min(max(job.width ?? 1024, 1), 16_384),
                                          height: min(max(job.height ?? 1024, 1), 16_384))
        var results: [StepResult] = []
        var outcome = "ok"
        var code: Int32 = 0
        for (n, step) in job.steps.enumerated() {
            let r = perform(step, on: &document, folder: folder, jobName: job.name)
            results.append(StepResult(step: n + 1, do: step.do, ok: r.ok, message: r.message))
            print("\(r.stop ? "STOP" : r.ok ? "ok  " : "FAIL") \(n + 1) \(step.do): \(r.message)")
            if r.stop { outcome = "stopped"; break }
            if !r.ok { outcome = "failed"; code = 1; break }
        }
        let status = Status(name: job.name, result: outcome, finished: Date(), steps: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let statusURL = file(job.name + ".status.json", in: folder), let data = try? encoder.encode(status) {
            try? data.write(to: statusURL, options: .atomic)
        }
        return code
    }

    /// The top visible picture layer.
    @MainActor static func top(_ d: LayerworksDocument) -> Layer? {
        d.layers.last { $0.isVisible && !$0.role.isBackground }
    }

    @MainActor static func perform(_ step: Step, on d: inout LayerworksDocument, folder: URL,
                                   jobName: String) -> (ok: Bool, stop: Bool, message: String) {
        func ok(_ m: String) -> (Bool, Bool, String) { (true, false, m) }
        func no(_ m: String) -> (Bool, Bool, String) { (false, false, m) }
        func named(_ ext: String?) -> URL? {
            guard let url = file(step.file, in: folder) else { return nil }
            return ext.map { url.pathExtension.isEmpty ? url.appendingPathExtension($0) : url } ?? url
        }
        switch step.do {
        case "open":
            guard let url = named(nil) else { return no("needs \"file\": a plain name in the job folder") }
            do {
                let (m, blobs) = try PackageLayout.read(FileWrapper(url: url, options: .immediate))
                d = LayerworksDocument(manifest: m, blobs: blobs)
                return ok("opened \(url.lastPathComponent) (\(m.canvasWidth) × \(m.canvasHeight), \(m.layers.count) layers)")
            } catch { return no("couldn't open \(url.lastPathComponent): \(error.localizedDescription)") }

        case "addImage":
            guard let url = named(nil) else { return no("needs \"file\": a plain name in the job folder") }
            guard let data = try? Data(contentsOf: url), let image = ContentRender.picture(data: data) else {
                return no("couldn't read the picture \(url.lastPathComponent)")
            }
            guard d.addPicture(image, name: url.deletingPathExtension().lastPathComponent, above: top(d)?.id,
                               replacing: false, undoManager: nil) != nil else { return no("couldn't add the picture") }
            return ok("added \(url.lastPathComponent) (\(image.width) × \(image.height))")

        case "removeBackground":
            guard let layer = top(d), let b = d.bitmap(of: layer.id) else { return no("there is no picture layer") }
            let (count, cutout) = Effects.liftSubjects(b, keep: nil)
            guard let cutout, count > 0 else { return no("no subject found in \(layer.name)") }
            _ = d.fork(layer.id, into: cutout, label: "Cutout", title: "Remove Background", undoManager: nil)
            return ok(count > 1 ? "kept all \(count) subjects" : "background removed")

        case "magicErase":
            let hex = step.color ?? "#FFFFFF"
            guard let target = RGBA(hex: hex) else { return no("\"color\" must look like #FFFFFF") }
            guard let layer = top(d), var b = d.bitmap(of: layer.id) else { return no("there is no picture layer") }
            let tolerance = min(max(step.tolerance ?? 24, 0), 100) / 100 * 0.5   // the panel's slider runs 0–0.5
            b.clear(b.colorMatch(target, tolerance: tolerance))
            _ = d.fork(layer.id, into: b, label: "Erase", title: "Eraser", undoManager: nil)
            return ok("erased \(hex) at tolerance \(Int(step.tolerance ?? 24))")

        case "merge":
            let ids = Set(d.layers.filter { $0.isVisible && !$0.role.isBackground }.map(\.id))
            guard ids.count >= 2 else { return ok("only one picture layer: nothing to merge") }
            guard d.merge(ids, undoManager: nil) != nil else { return no("couldn't merge") }
            return ok("merged \(ids.count) layers")

        case "resize":
            let w0 = d.manifest.canvasWidth, h0 = d.manifest.canvasHeight
            let s: Double
            if let w = step.width, w > 0 { s = Double(w) / Double(w0) }
            else if let h = step.height, h > 0 { s = Double(h) / Double(h0) }
            else { return no("needs \"width\" or \"height\"; to change the shape use crop, extend or scaleToFit") }
            d.scalePicture(by: s, title: "Resize", undoManager: nil)
            return ok("resized to \(d.manifest.canvasWidth) × \(d.manifest.canvasHeight)")

        case "crop", "extend":
            guard let w = step.width, let h = step.height, w > 0, h > 0 else { return no("needs \"width\" and \"height\"") }
            let w0 = d.manifest.canvasWidth, h0 = d.manifest.canvasHeight
            if step.do == "crop", w > w0 || h > h0 { return no("crop makes the canvas smaller; use extend to grow it") }
            if step.do == "extend", w < w0 || h < h0 { return no("extend makes the canvas bigger; use crop to shrink it") }
            d.resizeCanvas(width: w, height: h, undoManager: nil)
            return ok("canvas \(w) × \(h), picture centered")

        case "scaleToFit":
            guard let w = step.width, let h = step.height, w > 0, h > 0 else { return no("needs \"width\" and \"height\"") }
            let s = min(Double(w) / Double(d.manifest.canvasWidth), Double(h) / Double(d.manifest.canvasHeight))
            d.scalePicture(by: s, title: "Scale to Fit", undoManager: nil)
            d.resizeCanvas(width: w, height: h, undoManager: nil)
            return ok("scaled to fit \(w) × \(h)")

        case "exportPNG":
            guard let url = named("png") else { return no("needs \"file\": a plain name in the job folder") }
            guard let image = Exporter.picture(d.manifest, blobs: d.blobs), let data = Exporter.data(image, type: .png) else {
                return no("couldn't draw the picture")
            }
            do { try data.write(to: url, options: .atomic) } catch { return no("couldn't write \(url.lastPathComponent): \(error.localizedDescription)") }
            return ok("wrote \(url.lastPathComponent) (\(image.width) × \(image.height))")

        case "saveProject":
            guard let url = named("layerworks") else { return no("needs \"file\": a plain name in the job folder") }
            return save(d, to: url).map(no) ?? ok("saved \(url.lastPathComponent)")

        case "imagePlayground":
            let name = step.file ?? jobName + ".layerworks"
            guard let url = file(name, in: folder).map({ $0.pathExtension.isEmpty ? $0.appendingPathExtension("layerworks") : $0 }) else {
                return no("\"file\" must be a plain name in the job folder")
            }
            if let error = save(d, to: url) { return no(error) }
            return (true, true, "saved \(url.lastPathComponent) and stopped: open it in Layerworks and use Image Playground (it needs a person to press Done)")

        default:
            return no("unknown step \"\(step.do)\" (Layerworks --help lists them)")
        }
    }

    /// Writes a .layerworks package. Returns an error message, or nil.
    @MainActor static func save(_ d: LayerworksDocument, to url: URL) -> String? {
        do {
            let wrapper = try PackageLayout.wrapper(for: d.manifest, blobs: d.blobs)
            try? FileManager.default.removeItem(at: url)
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
            return nil
        } catch { return "couldn't save \(url.lastPathComponent): \(error.localizedDescription)" }
    }

    static func fail(_ message: String) {
        FileHandle.standardError.write(Data("Layerworks: \(message)\nRun Layerworks --help for usage.\n".utf8))
    }
}

// MARK: - Settings: the job folder

/// Layerworks ▸ Settings… — the job folder for command mode.
struct CommandSettingsView: View {
    @State private var path = CommandSettingsView.currentPath()
    @State private var choosing = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Job folder", value: path).accessibilityIdentifier("Job folder")
                HStack {
                    Button("Choose…") { choosing = true }
                    Button("Use the App's Own Folder") {
                        UserDefaults.standard.removeObject(forKey: CommandMode.bookmarkKey)
                        path = Self.currentPath()
                    }
                    .disabled(UserDefaults.standard.data(forKey: CommandMode.bookmarkKey) == nil)
                }
                Text("Bots run Layerworks --command job.json. Every file in a job is read from and written to this folder. A folder in your home folder (for example Layerworks Jobs) is easiest for scripts to reach.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Command Mode") }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(data, forKey: CommandMode.bookmarkKey)
            }
            path = Self.currentPath()
        }
    }

    static func currentPath() -> String {
        let (url, scoped) = CommandMode.jobFolder()
        if scoped { url.stopAccessingSecurityScopedResource() }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}
#endif

// MARK: - Scaling the whole picture (command mode's resize and scaleToFit)

extension LayerworksDocument {
    /// Scales the canvas and every layer's frame by `s` (one History step). Pictures are redrawn
    /// at their new size when composited, exactly as the Move tool's Scale does.
    func scalePicture(by s: Double, title: String, undoManager: UndoManager?) {
        guard s > 0, s != 1 else { return }
        let w0 = manifest.canvasWidth, h0 = manifest.canvasHeight
        let w = min(max(Int((Double(w0) * s).rounded()), 1), 16_384)
        let h = min(max(Int((Double(h0) * s).rounded()), 1), 16_384)
        var next = manifest.layers
        for i in next.indices where next[i].image != nil {
            let f = next[i].frame ?? PixelRect(x: 0, y: 0, width: w0, height: h0)
            next[i].frame = PixelRect(x: Int((Double(f.x) * s).rounded()), y: Int((Double(f.y) * s).rounded()),
                                      width: max(1, Int((Double(f.width) * s).rounded())),
                                      height: max(1, Int((Double(f.height) * s).rounded())))
        }
        var m = manifest
        m.history.removeSubrange((m.historyCursor + 1)...)
        m.canvasWidth = w
        m.canvasHeight = h
        m.history.append(HistoryStep(title: title, layers: next, canvasWidth: w, canvasHeight: h))
        m.historyCursor = m.history.count - 1
        m.layers = next
        manifest = m
    }
}
