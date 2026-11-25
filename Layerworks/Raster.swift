//
//  Raster.swift
//  Layerworks
//
//  Created by Michael Fluharty on 11/25/26.
//

import Foundation
import CoreGraphics

// REM: Build step 4b — the pixel engine under Bucket, Pen, Eraser and Eyedropper. A Bitmap is
// one layer drawn at canvas size (RGBA, premultiplied, row 0 = top), so a click at canvas
// pixel (x, y) is index (y * width + x). Tools never edit a layer in place: they build a new
// Bitmap and the document puts it on a NEW layer with the original hidden (004: the layer
// design is the undo).

nonisolated struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
    }

    /// One layer at canvas size and full strength (its fill, then its picture in its frame).
    init(layer: Layer, blobs: [String: Data], canvasWidth: Int, canvasHeight: Int) {
        self.init(width: canvasWidth, height: canvasHeight)
        var flat = layer
        flat.isVisible = true
        flat.opacity = 1
        draw { ctx, rect in
            if let hex = flat.fillHex, let color = Compositor.cgColor(hex: hex) {
                ctx.setFillColor(color); ctx.fill(rect)
            }
            if let key = flat.image, let data = blobs[key], let picture = Compositor.decode(data) {
                ctx.draw(picture, in: Compositor.drawRect(flat.frame, canvasWidth: canvasWidth,
                                                          canvasHeight: canvasHeight, into: rect))
            }
        }
    }

    /// Wraps any CGImage (for example the whole picture, for the Eyedropper).
    init(image: CGImage, width: Int, height: Int) {
        self.init(width: width, height: height)
        draw { ctx, rect in ctx.draw(image, in: rect) }
    }

    mutating func draw(_ body: (CGContext, CGRect) -> Void) {
        let w = width, h = height
        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            body(ctx, CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    func cgImage() -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func png() -> Data? {
        guard let image = cgImage() else { return nil }
        return Compositor.pngData(image)
    }

    func contains(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }

    /// Straight (un-premultiplied) color at a pixel, 0…255.
    func rgba(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * width + x) * 4
        let a = Int(pixels[i + 3])
        guard a > 0 else { return (0, 0, 0, 0) }
        return (Int(pixels[i]) * 255 / a, Int(pixels[i + 1]) * 255 / a, Int(pixels[i + 2]) * 255 / a, a)
    }

    mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        let i = (y * width + x) * 4
        let a = Int(c.a)
        pixels[i] = UInt8(Int(c.r) * a / 255); pixels[i + 1] = UInt8(Int(c.g) * a / 255)
        pixels[i + 2] = UInt8(Int(c.b) * a / 255); pixels[i + 3] = c.a
    }

    /// Average color in a square of `size` pixels around (x, y) — the Eyedropper's sample size.
    func average(_ x: Int, _ y: Int, size: Int) -> RGBA? {
        let half = max(size, 1) / 2
        var r = 0, g = 0, b = 0, a = 0, n = 0
        for yy in (y - half)...(y + half) { for xx in (x - half)...(x + half) where contains(xx, yy) {
            let p = rgba(xx, yy); r += p.r; g += p.g; b += p.b; a += p.a; n += 1
        } }
        guard n > 0 else { return nil }
        return RGBA(r: UInt8(r / n), g: UInt8(g / n), b: UInt8(b / n), a: UInt8(a / n))
    }

    /// Does this pixel match a color within the tolerance (0…1)? Clear matches clear.
    func matches(_ x: Int, _ y: Int, _ target: (r: Int, g: Int, b: Int, a: Int), tolerance: Double) -> Bool {
        let p = rgba(x, y)
        let limit = Int(tolerance * 255)
        if target.a == 0 || p.a == 0 { return abs(p.a - target.a) <= limit }
        return abs(p.r - target.r) <= limit && abs(p.g - target.g) <= limit
            && abs(p.b - target.b) <= limit && abs(p.a - target.a) <= limit
    }

    /// The connected region around a pixel whose color is within the tolerance — the Bucket's
    /// "pour up to the outline".
    func region(from x: Int, _ y: Int, tolerance: Double) -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        guard contains(x, y) else { return mask }
        let target = rgba(x, y)
        var stack = [(x, y)]
        while let (sx, sy) = stack.popLast() {
            var lx = sx
            while lx >= 0, !mask[sy * width + lx], matches(lx, sy, target, tolerance: tolerance) { lx -= 1 }
            lx += 1
            var above = false, below = false
            var cx = lx
            while cx < width, !mask[sy * width + cx], matches(cx, sy, target, tolerance: tolerance) {
                mask[sy * width + cx] = true
                for (ny, flag) in [(sy - 1, 0), (sy + 1, 1)] where ny >= 0 && ny < height {
                    let ok = !mask[ny * width + cx] && matches(cx, ny, target, tolerance: tolerance)
                    if flag == 0 { if ok && !above { stack.append((cx, ny)) }; above = ok }
                    else { if ok && !below { stack.append((cx, ny)) }; below = ok }
                }
                cx += 1
            }
        }
        return mask
    }

    /// Every pixel near one color, anywhere — the Magic Eraser's match.
    func colorMatch(_ target: RGBA, tolerance: Double) -> [Bool] {
        let t = (Int(target.r), Int(target.g), Int(target.b), Int(target.a))
        var mask = [Bool](repeating: false, count: width * height)
        for y in 0..<height { for x in 0..<width where matches(x, y, t, tolerance: tolerance) {
            mask[y * width + x] = true
        } }
        return mask
    }

    mutating func fill(_ mask: [Bool], with c: RGBA) {
        for y in 0..<height { for x in 0..<width where mask[y * width + x] { set(x, y, c) } }
    }

    mutating func clear(_ mask: [Bool]) { fill(mask, with: RGBA(r: 0, g: 0, b: 0, a: 0)) }
}

nonisolated struct RGBA: Equatable, Sendable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

/// A mask as a picture: the given color where the mask is on, clear elsewhere (for previews).
nonisolated func maskImage(_ mask: [Bool], width: Int, height: Int, color: RGBA) -> CGImage? {
    var b = Bitmap(width: width, height: height)
    b.fill(mask, with: color)
    return b.cgImage()
}
