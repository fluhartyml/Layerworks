//
//  Storyboard.swift
//  Layerworks
//
//  Build step 6b — Blueprint 066 / 067: the Storyboard and video export.
//
//  REM: 066 — "A sheet for sequencing frames / shots for animation and export, beside Camera's
//  Lightbox. Rebuild it as a standard sheet or inspector, not a one-off window."
//  REM: 067 — "the Storyboard button should not sit on every document's toolbar ... Put it under
//  File or the Camera tool so a still-image window does not look like a video app. Storyboard
//  data already in a document must still play and export."
//  So: File ▸ Storyboard… (⌥⌘B) and a Storyboard… button in the Camera tool's Lightbox section.
//  No toolbar button.
//
//  REM: the cards ARE the Camera tool's frames (manifest.frames). Nothing new is stored per
//  picture. The storyboard only saves what differs from the Lightbox: a hold per frame, a
//  transition between two frames, and an optional soundtrack. A document with no storyboard
//  settings plays at the Lightbox speed (lw.cam.fps), so an old file still plays and exports.
//
//  REM: Claude's calls, not from the sheet (Normalize: "use Apple's standard ... cut bloat"):
//  - Transitions are Apple's own Core Image transition filters (CIDissolveTransition,
//    CISwipeTransition, CIBarsSwipeTransition, CICopyMachineTransition, CIFlashTransition,
//    CIModTransition, CIPageCurlTransition) plus fades through black or white. Image Producer
//    drew its 21 by hand (Transitions.swift); these come with the system.
//  - Motion in-betweens are the Camera tool's Generate (058), so they are not a transition here.
//  - One soundtrack, cut where the video ends. Image Producer's per-card sound effects were only
//    partly built there and the Blueprint doesn't ask for them: left out, not stubbed.
//  - Video is 30 fps on white (video has no transparency), at the canvas size rounded up to even
//    pixels (H.264 / HEVC need even sizes). Formats: H.264 (.mp4), HEVC (.mp4), ProRes 422 (.mov).
//

import AVFoundation
import AVKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

// MARK: - What the document saves

nonisolated struct StoryboardSpec: Codable, Equatable, Sendable {
    /// A frame held longer or shorter than the Lightbox speed.
    struct Hold: Codable, Equatable, Sendable {
        var frame: UUID
        var seconds: Double
    }
    /// What plays between two frames. Reordering the frames drops it (back to a cut).
    struct Transition: Codable, Equatable, Sendable {
        var from: UUID
        var to: UUID
        /// The effect's saved name; a name this build doesn't know reads as a cut.
        var effectName: String
        var seconds: Double
        var effect: StoryboardEffect { StoryboardEffect(rawValue: effectName) ?? .cut }
    }
    /// The soundtrack: the bytes live in the package's Sounds folder, by hash.
    struct Sound: Codable, Equatable, Sendable {
        var name: String
        var key: String
        var fileExtension: String
    }

    var holds: [Hold] = []
    var transitions: [Transition] = []
    var soundtrack: Sound?

    static let fps: Int32 = 30
    static let shortestHold = 1.0 / 30
    static let longestHold = 10.0
    static let defaultTransition = 0.5

    var isEmpty: Bool { holds.isEmpty && transitions.isEmpty && soundtrack == nil }

    func seconds(for frame: UUID, lightboxFPS: Double) -> Double {
        holds.first { $0.frame == frame }?.seconds ?? 1 / max(lightboxFPS, 1)
    }

    mutating func setSeconds(_ s: Double, for frame: UUID) {
        holds.removeAll { $0.frame == frame }
        holds.append(Hold(frame: frame, seconds: min(max(s, Self.shortestHold), Self.longestHold)))
    }

    func transition(from a: UUID, to b: UUID) -> Transition? {
        transitions.first { $0.from == a && $0.to == b }
    }

    mutating func setTransition(_ effect: StoryboardEffect, seconds: Double, from a: UUID, to b: UUID) {
        transitions.removeAll { $0.from == a && $0.to == b }
        if effect != .cut {
            transitions.append(Transition(from: a, to: b, effectName: effect.rawValue,
                                          seconds: min(max(seconds, Self.shortestHold), 3)))
        }
    }

    /// Drops settings for frames that are gone or pairs that are no longer next to each other.
    func pruned(to frames: [AnimFrame]) -> StoryboardSpec {
        let ids = Set(frames.map(\.id))
        let pairs = Set(zip(frames, frames.dropFirst()).map { "\($0.id)>\($1.id)" })
        var s = self
        s.holds = holds.filter { ids.contains($0.frame) }
        s.transitions = transitions.filter { pairs.contains("\($0.from)>\($0.to)") }
        return s
    }

    /// The video's length in seconds, as the video writer counts it (whole 1/30 s frames).
    func totalSeconds(_ frames: [AnimFrame], lightboxFPS: Double) -> Double {
        Double(StoryboardPlan(spec: self, frames: frames, lightboxFPS: lightboxFPS).totalFrames) / Double(Self.fps)
    }
}

/// Apple's Core Image transitions, plus fades through black or white.
nonisolated enum StoryboardEffect: String, CaseIterable, Identifiable, Sendable {
    case cut, dissolve, fadeBlack, fadeWhite, swipe, bars, copyMachine, flash, shards, pageCurl
    var id: String { rawValue }

    var name: String {
        switch self {
        case .cut: "Cut"
        case .dissolve: "Dissolve"
        case .fadeBlack: "Fade Through Black"
        case .fadeWhite: "Fade Through White"
        case .swipe: "Swipe"
        case .bars: "Bars"
        case .copyMachine: "Copy Machine"
        case .flash: "Flash"
        case .shards: "Shards"
        case .pageCurl: "Page Curl"
        }
    }

    /// The picture partway from `a` to `b` (t from 0 to 1).
    func blend(_ a: CIImage, _ b: CIImage, _ t: Double, extent: CGRect) -> CIImage {
        func filter(_ name: String, _ from: CIImage, _ to: CIImage, _ time: Double) -> CIImage {
            guard let f = CIFilter(name: name) else { return time < 0.5 ? from : to }
            f.setValue(from, forKey: kCIInputImageKey)
            f.setValue(to, forKey: kCIInputTargetImageKey)
            f.setValue(time, forKey: kCIInputTimeKey)
            let keys = f.inputKeys
            if keys.contains(kCIInputExtentKey) { f.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey) }
            if keys.contains(kCIInputCenterKey) {
                f.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
            }
            if keys.contains("inputColor") { f.setValue(CIColor.white, forKey: "inputColor") }
            if keys.contains("inputBacksideImage") { f.setValue(from, forKey: "inputBacksideImage") }
            if keys.contains(kCIInputWidthKey), name == "CISwipeTransition" {
                f.setValue(extent.width / 4, forKey: kCIInputWidthKey)
            }
            return (f.outputImage ?? to).composited(over: StoryboardPlan.solid(.white, extent)).cropped(to: extent)
        }
        switch self {
        case .cut: return t < 0.5 ? a : b
        case .dissolve: return filter("CIDissolveTransition", a, b, t)
        case .fadeBlack, .fadeWhite:
            let mid = StoryboardPlan.solid(self == .fadeBlack ? .black : .white, extent)
            return t < 0.5 ? filter("CIDissolveTransition", a, mid, t * 2)
                           : filter("CIDissolveTransition", mid, b, (t - 0.5) * 2)
        case .swipe: return filter("CISwipeTransition", a, b, t)
        case .bars: return filter("CIBarsSwipeTransition", a, b, t)
        case .copyMachine: return filter("CICopyMachineTransition", a, b, t)
        case .flash: return filter("CIFlashTransition", a, b, t)
        case .shards: return filter("CIModTransition", a, b, t)
        case .pageCurl: return filter("CIPageCurlTransition", a, b, t)
        }
    }
}

// MARK: - The plan: how many 1/30 s video frames each card and transition gets

nonisolated struct StoryboardPlan: Sendable {
    struct Step: Sendable {
        var card: Int
        var holdFrames: Int
        /// The transition into the next card, if any.
        var effect: StoryboardEffect
        var transitionFrames: Int
    }
    var steps: [Step]
    var totalFrames: Int { steps.reduce(0) { $0 + $1.holdFrames + $1.transitionFrames } }

    init(spec: StoryboardSpec, frames: [AnimFrame], lightboxFPS: Double) {
        let fps = Double(StoryboardSpec.fps)
        var list: [Step] = []
        for (i, f) in frames.enumerated() {
            let hold = max(1, Int((spec.seconds(for: f.id, lightboxFPS: lightboxFPS) * fps).rounded()))
            var effect = StoryboardEffect.cut, between = 0
            if i + 1 < frames.count, let t = spec.transition(from: f.id, to: frames[i + 1].id), t.effect != .cut {
                effect = t.effect
                between = max(1, Int((t.seconds * fps).rounded()))
            }
            list.append(Step(card: i, holdFrames: hold, effect: effect, transitionFrames: between))
        }
        steps = list
    }

    static func solid(_ color: CIColor, _ extent: CGRect) -> CIImage {
        CIImage(color: color).cropped(to: extent)
    }

    /// The video's pixel size: the canvas, rounded up to even numbers.
    static func size(_ m: ProjectManifest) -> (Int, Int) {
        (m.canvasWidth + m.canvasWidth % 2, m.canvasHeight + m.canvasHeight % 2)
    }
}

// MARK: - Video

nonisolated enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264 = "H.264 (.mp4)", hevc = "HEVC (.mp4)", proRes = "ProRes 422 (.mov)"
    var id: String { rawValue }
    var codec: AVVideoCodecType {
        switch self { case .h264: .h264; case .hevc: .hevc; case .proRes: .proRes422 }
    }
    var fileType: AVFileType { self == .proRes ? .mov : .mp4 }
    var contentType: UTType { self == .proRes ? .quickTimeMovie : .mpeg4Movie }
    var fileExtension: String { self == .proRes ? "mov" : "mp4" }
    var reencodePreset: String {
        switch self {
        case .h264: AVAssetExportPresetHighestQuality
        case .hevc: AVAssetExportPresetHEVCHighestQuality
        case .proRes: AVAssetExportPresetAppleProRes422LPCM
        }
    }
}

nonisolated enum VideoMaker {
    struct Input: Sendable {
        var cards: [CGImage]
        var plan: StoryboardPlan
        var width: Int
        var height: Int
        var codec: VideoCodec
        /// The soundtrack's bytes and file extension.
        var sound: Data?
        var soundExtension: String
    }

    /// Everything the writer needs, read from the document on the main actor.
    @MainActor static func input(_ document: LayerworksDocument, codec: VideoCodec, lightboxFPS: Double) -> Input? {
        let m = document.manifest
        let cards = m.frames.compactMap { document.blobs[$0.image].flatMap(Compositor.decode) }
        guard !cards.isEmpty, cards.count == m.frames.count else { return nil }
        let (w, h) = StoryboardPlan.size(m)
        let sound = m.storyboard.soundtrack
        return Input(cards: cards, plan: StoryboardPlan(spec: m.storyboard, frames: m.frames, lightboxFPS: lightboxFPS),
                     width: w, height: h, codec: codec,
                     sound: sound.flatMap { document.blobs[$0.key] }, soundExtension: sound?.fileExtension ?? "m4a")
    }

    /// Writes the video to a new temporary file and returns it. `progress` gets (done, total).
    @concurrent static func make(_ input: Input, progress: @escaping @Sendable (Int, Int) -> Void) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Layerworks Video", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let silent = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(input.codec.fileExtension)
        try await write(input, to: silent, progress: progress)
        guard let sound = input.sound else { return silent }

        let soundURL = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(input.soundExtension)
        try sound.write(to: soundURL)
        defer { try? FileManager.default.removeItem(at: soundURL) }
        let out = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(input.codec.fileExtension)
        try await addSound(soundURL, to: silent, out: out, codec: input.codec)
        try? FileManager.default.removeItem(at: silent)
        return out
    }

    private static func write(_ input: Input, to url: URL, progress: @escaping @Sendable (Int, Int) -> Void) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: input.codec.fileType)
        let settings: [String: Any] = [AVVideoCodecKey: input.codec.codec,
                                       AVVideoWidthKey: input.width, AVVideoHeightKey: input.height]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: input.width, kCVPixelBufferHeightKey as String: input.height])
        guard writer.canAdd(video) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(video)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        let extent = CGRect(x: 0, y: 0, width: input.width, height: input.height)
        let white = StoryboardPlan.solid(.white, extent)
        let context = CIContext()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Each card sits at the top-left of the even-sized video, on white.
        let cards = input.cards.map { img in
            CIImage(cgImage: img).transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(input.height - img.height)))
                .composited(over: white).cropped(to: extent)
        }
        let total = input.plan.totalFrames
        var frame: Int64 = 0

        func append(_ image: CIImage) async throws {
            while !video.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
            context.render(image, to: buffer, bounds: extent, colorSpace: space)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: StoryboardSpec.fps)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
            frame += 1
            if frame % 10 == 0 || Int(frame) == total { progress(Int(frame), total) }
        }

        for step in input.plan.steps {
            let card = cards[step.card]
            for _ in 0..<step.holdFrames { try await append(card) }
            if step.transitionFrames > 0, step.card + 1 < cards.count {
                let next = cards[step.card + 1]
                for k in 1...step.transitionFrames {
                    let t = Double(k) / Double(step.transitionFrames + 1)
                    try await append(step.effect.blend(card, next, t, extent: extent))
                }
            }
        }
        video.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: frame, timescale: StoryboardSpec.fps))
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// Lays the soundtrack under the video, cut where the video ends.
    private static func addSound(_ sound: URL, to video: URL, out: URL, codec: VideoCodec) async throws {
        let videoAsset = AVURLAsset(url: video)
        let duration = try await videoAsset.load(.duration)
        let composition = AVMutableComposition()
        guard let source = try await videoAsset.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.fileWriteUnknown) }
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)

        let soundAsset = AVURLAsset(url: sound)
        if let audio = try await soundAsset.loadTracks(withMediaType: .audio).first,
           let lane = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let length = try await soundAsset.load(.duration)
            try lane.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(length, duration)), of: audio, at: .zero)
        }
        // Passthrough keeps the video as written; a sound the container can't carry is re-encoded.
        for preset in [AVAssetExportPresetPassthrough, codec.reencodePreset] {
            guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            try? FileManager.default.removeItem(at: out)
            do { try await session.export(to: out, as: codec.fileType); return } catch { continue }
        }
        throw CocoaError(.fileWriteUnknown)
    }
}

// MARK: - Document edits

extension LayerworksDocument {
    func setStoryboard(_ s: StoryboardSpec, title: String, undoManager: UndoManager?) {
        let old = manifest.storyboard
        guard old != s else { return }
        manifest.storyboard = s
        undoManager?.registerUndo(withTarget: self) { $0.setStoryboard(old, title: title, undoManager: undoManager) }
        undoManager?.setActionName(title)
    }

    /// Reorders or removes frames, keeping the storyboard settings that still apply.
    func arrangeFrames(_ frames: [AnimFrame], title: String, undoManager: UndoManager?) {
        undoManager?.beginUndoGrouping()
        setFrames(frames, title: title, undoManager: undoManager)
        setStoryboard(manifest.storyboard.pruned(to: frames), title: title, undoManager: undoManager)
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(title)
    }

    func setSoundtrack(_ data: Data, name: String, fileExtension: String, undoManager: UndoManager?) {
        let key = storeSound(data)
        var s = manifest.storyboard
        s.soundtrack = .init(name: name, key: key, fileExtension: fileExtension)
        setStoryboard(s, title: "Add Soundtrack", undoManager: undoManager)
    }
}

// MARK: - The sheet

/// File ▸ Storyboard… (⌥⌘B), or Storyboard… in the Camera tool.
struct StoryboardSheet: View {
    @ObservedObject var document: LayerworksDocument
    @ObservedObject var editor: EditorState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @AppStorage("lw.cam.fps") private var fps = 8.0
    @State private var player: AVPlayer?
    @State private var making: (done: Int, total: Int)?
    @State private var addingSound = false
    @State private var job: Task<Void, Never>?

    private var frames: [AnimFrame] { document.manifest.frames }
    private var board: StoryboardSpec { document.manifest.storyboard }

    var body: some View {
        NavigationStack {
            Form {
                if frames.isEmpty {
                    Text("No frames yet. In the Camera tool, turn on Animation mode and Capture Frame.")
                        .foregroundStyle(.secondary)
                } else {
                    preview
                    Section("Frames") {
                        ForEach(Array(frames.enumerated()), id: \.element.id) { i, f in
                            frameRow(i, f)
                            if i + 1 < frames.count { transitionRow(f, frames[i + 1]) }
                        }
                    }
                    soundSection
                    Section {
                        LabeledContent("Length", value: Self.seconds(board.totalSeconds(frames, lightboxFPS: fps)))
                            .accessibilityIdentifier("Video length")
                        Button("Reset Timing") {
                            var s = board; s.holds = []; s.transitions = []
                            setBoard(s, "Reset Timing")
                        }
                        .disabled(board.holds.isEmpty && board.transitions.isEmpty)
                        Text("A frame with no hold of its own shows for \(Self.seconds(1 / max(fps, 1))), the Lightbox speed. Export the video with File ▸ Export… ▸ Video.")
                            .font(.callout).foregroundStyle(.secondary)
                    } header: { Text("Video") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Storyboard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { job?.cancel(); dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .fileImporter(isPresented: $addingSound, allowedContentTypes: [.audio], onCompletion: addSound)
        .onDisappear { job?.cancel(); player?.pause() }
    }

    private func addSound(_ result: Result<URL, Error>) {
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { editor.status = "That sound couldn't be read"; return }
            document.setSoundtrack(data, name: url.lastPathComponent, fileExtension: url.pathExtension.isEmpty ? "m4a" : url.pathExtension,
                                   undoManager: undoManager)
            player = nil
            editor.status = "Added the soundtrack \(url.lastPathComponent)"
    }

    @ViewBuilder private var preview: some View {
        Section {
            Button(player == nil ? "Play" : "Play Again", action: play)
                .accessibilityLabel("Play")
                .disabled(making != nil)
        }
        if let making {
            Section {
                ProgressView(value: Double(making.done), total: Double(max(making.total, 1))) {
                    Text("Making frame \(making.done) of \(making.total)")
                }
                .accessibilityIdentifier("Making video")
            }
        } else if let player {
            Section {
                PlayerView(player: player).frame(height: 240).accessibilityLabel("Video preview")
            }
        }
    }

    private func frameRow(_ i: Int, _ f: AnimFrame) -> some View {
        let seconds = board.seconds(for: f.id, lightboxFPS: fps)
        return HStack(spacing: 12) {
            thumbnail(f)
            VStack(alignment: .leading) {
                Text("Frame \(i + 1)" + (f.generated ? " (in-between)" : ""))
                Stepper(value: Binding(get: { seconds },
                                       set: { v in var s = board; s.setSeconds(v, for: f.id); setBoard(s, "Frame Hold") }),
                        in: StoryboardSpec.shortestHold...StoryboardSpec.longestHold, step: 0.25) {
                    Text("Hold \(Self.seconds(seconds))").monospacedDigit()
                }
                .accessibilityLabel("Hold for frame \(i + 1)")
            }
            Spacer()
            Button { move(i, by: -1) } label: { Image(systemName: "arrow.up") }
                .accessibilityLabel("Move frame \(i + 1) up").disabled(i == 0)
            Button { move(i, by: 1) } label: { Image(systemName: "arrow.down") }
                .accessibilityLabel("Move frame \(i + 1) down").disabled(i == frames.count - 1)
            Button(role: .destructive) {
                var list = frames; list.remove(at: i)
                document.arrangeFrames(list, title: "Remove Frame", undoManager: undoManager)
                player = nil
            } label: { Image(systemName: "trash") }
                .accessibilityLabel("Remove frame \(i + 1)")
        }
        .buttonStyle(.borderless)
    }

    private func transitionRow(_ a: AnimFrame, _ b: AnimFrame) -> some View {
        let t = board.transition(from: a.id, to: b.id)
        let effect = t?.effect ?? .cut
        let seconds = t?.seconds ?? StoryboardSpec.defaultTransition
        let n = (frames.firstIndex(of: a) ?? 0) + 1
        return HStack {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
            Picker("Then", selection: Binding(get: { effect }, set: { e in
                var s = board; s.setTransition(e, seconds: seconds, from: a.id, to: b.id); setBoard(s, "Transition")
            })) {
                ForEach(StoryboardEffect.allCases) { Text($0.name).tag($0) }
            }
            .accessibilityLabel("Transition after frame \(n)")
            if effect != .cut {
                Stepper(value: Binding(get: { seconds }, set: { v in
                    var s = board; s.setTransition(effect, seconds: v, from: a.id, to: b.id); setBoard(s, "Transition Length")
                }), in: 0.25...3, step: 0.25) {
                    Text(Self.seconds(seconds)).monospacedDigit()
                }
                .accessibilityLabel("Transition length after frame \(n)")
                .fixedSize()
            }
        }
    }

    private var soundSection: some View {
        Section {
            if let sound = board.soundtrack {
                LabeledContent("Soundtrack", value: sound.name).accessibilityIdentifier("Soundtrack name")
                Button("Remove Soundtrack", role: .destructive) {
                    var s = board; s.soundtrack = nil; setBoard(s, "Remove Soundtrack")
                }
            } else {
                Text("No soundtrack").foregroundStyle(.secondary)
            }
            Button(board.soundtrack == nil ? "Add Soundtrack…" : "Replace Soundtrack…") {
                // Robot tests only (LW_ROBOT): skip Apple's open panel and use a made tone, as Export
                // skips its save panel.
                if ProcessInfo.processInfo.environment["LW_ROBOT"] != nil, let tone = Self.robotTone() {
                    addSound(.success(tone))
                } else {
                    addingSound = true
                }
            }
            Text("Your own sound file plays from the start and stops where the video ends.")
                .font(.callout).foregroundStyle(.secondary)
        } header: { Text("Sound") }
    }

    @ViewBuilder private func thumbnail(_ f: AnimFrame) -> some View {
        if let img = document.blobs[f.image].flatMap(Compositor.decode) {
            Image(decorative: img, scale: 1).resizable().interpolation(.medium).scaledToFit()
                .frame(width: 56, height: 56).background(.white).clipShape(.rect(cornerRadius: 4))
        } else {
            Color.secondary.opacity(0.2).frame(width: 56, height: 56)
        }
    }

    private func move(_ i: Int, by d: Int) {
        var list = frames
        list.swapAt(i, i + d)
        document.arrangeFrames(list, title: "Move Frame", undoManager: undoManager)
        player = nil
    }

    private func setBoard(_ s: StoryboardSpec, _ title: String) {
        document.setStoryboard(s, title: title, undoManager: undoManager)
        player = nil
    }

    /// Play: makes the video (H.264) and plays it here.
    private func play() {
        guard let input = VideoMaker.input(document, codec: .h264, lightboxFPS: fps) else {
            editor.status = "The frames couldn't be read"; return
        }
        player?.pause(); player = nil
        making = (0, input.plan.totalFrames)
        editor.status = "Making the video"
        job = Task {
            do {
                let url = try await VideoMaker.make(input) { done, total in
                    Task { @MainActor in if making != nil { making = (done, total) } }
                }
                making = nil
                let p = AVPlayer(url: url)
                player = p
                p.play()
                editor.status = "Playing the storyboard (\(Self.seconds(Double(input.plan.totalFrames) / Double(StoryboardSpec.fps))))"
            } catch {
                making = nil
                if !(error is CancellationError) { editor.status = "The video couldn't be made: \(error.localizedDescription)" }
            }
        }
    }

    /// Robot tests only: one second of a 440 Hz tone, written to the app's temporary folder.
    static func robotTone() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Robot Tone.m4a")
        try? FileManager.default.removeItem(at: url)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
              let file = try? AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                                     AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
        else { return nil }
        buffer.frameLength = 44_100
        for i in 0..<44_100 { buffer.floatChannelData![0][i] = Float(sin(2 * .pi * 440 * Double(i) / 44_100) * 0.3) }
        do { try file.write(from: buffer) } catch { return nil }
        return url
    }

    /// "2.5 s", "0.25 s", "1 min 5 s".
    static func seconds(_ s: Double) -> String {
        if s >= 60 { return "\(Int(s) / 60) min \(Int(s) % 60) s" }
        let r = (s * 100).rounded() / 100
        return r == r.rounded() ? "\(Int(r)) s" : "\(String(format: "%g", r)) s"
    }
}

/// Apple's player view. REM: SwiftUI's VideoPlayer crashed on the Mac here (AVKit SwiftUI type
/// metadata, 2026 NOV 25), so the AppKit / UIKit players are wrapped instead.
#if os(macOS)
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.player = player; v.controlsStyle = .inline; return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { if v.player !== player { v.player = player } }
}
#else
struct PlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController(); c.player = player; return c
    }
    func updateUIViewController(_ c: AVPlayerViewController, context: Context) { if c.player !== player { c.player = player } }
}
#endif

struct StoryboardCommands: Commands {
    @FocusedObject private var editor: EditorState?
    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Storyboard…") { editor?.storyboarding = true }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(editor == nil)
        }
    }
}
