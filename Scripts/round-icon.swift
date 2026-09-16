// Converts opaque square artwork into a macOS-shaped app icon: crops to the
// artwork's own rounded square, masks the corners transparent, and lays it out
// on Apple's 1024pt icon grid.
//
// Needed because artwork exported from most image tools has a solid background,
// and an .icns built from that shows a white box behind the icon everywhere
// macOS draws it.
//
//   swift Scripts/round-icon.swift in.png out.png

import AppKit
import CoreGraphics
import Foundation

// Apple's macOS icon grid: the body occupies 824 of a 1024 canvas, leaving room
// for the shadow macOS draws itself.
let canvas = 1024.0
let body = 824.0

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: round-icon.swift <in.png> <out.png>\n".utf8))
    exit(2)
}
let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let source = NSImage(contentsOfFile: inputPath),
      let cgSource = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("could not read \(inputPath)\n".utf8))
    exit(1)
}

let width = cgSource.width
let height = cgSource.height

// Read the pixels so we can find the artwork inside its background.
var pixels = [UInt8](repeating: 0, count: width * height * 4)
guard let readContext = CGContext(
    data: &pixels,
    width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
readContext.draw(cgSource, in: CGRect(x: 0, y: 0, width: width, height: height))

func isBackground(_ x: Int, _ y: Int) -> Bool {
    let i = (y * width + x) * 4
    // Near-white, or fully transparent if the source did have alpha.
    if pixels[i + 3] < 8 { return true }
    return pixels[i] > 244 && pixels[i + 1] > 244 && pixels[i + 2] > 244
}

// 1. Bounding box of the actual artwork.
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width where !isBackground(x, y) {
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
guard maxX > minX, maxY > minY else {
    FileHandle.standardError.write(Data("image looks blank\n".utf8))
    exit(1)
}
let boxWidth = maxX - minX + 1
let boxHeight = maxY - minY + 1

// 2. Measure the artwork's own corner radius, so the mask matches it instead of
//    clipping real pixels or leaving white slivers. Along the artwork's topmost
//    row, a rounded rect starts exactly `radius` in from the left edge.
var radius = 0
for x in minX...maxX where !isBackground(x, minY) {
    radius = x - minX
    break
}
// Fall back to Apple's proportion if the measurement looks implausible.
let measured = Double(radius) / Double(boxWidth)
let radiusFraction = (measured > 0.05 && measured < 0.40) ? measured : 0.225

// 3. Redraw masked onto a transparent 1024 canvas.
guard let output = CGContext(
    data: nil,
    width: Int(canvas), height: Int(canvas),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

output.interpolationQuality = .high
let inset = (canvas - body) / 2
let bodyRect = CGRect(x: inset, y: inset, width: body, height: body)
let path = CGPath(
    roundedRect: bodyRect,
    cornerWidth: body * radiusFraction,
    cornerHeight: body * radiusFraction,
    transform: nil
)
output.addPath(path)
output.clip()

guard let cropped = cgSource.cropping(to: CGRect(x: minX, y: minY, width: boxWidth, height: boxHeight)) else {
    exit(1)
}
output.draw(cropped, in: bodyRect)

guard let result = output.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: result)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: outputPath))

print("  source \(width)×\(height), artwork box \(boxWidth)×\(boxHeight) at (\(minX),\(minY))")
print("  corner radius measured at \(String(format: "%.1f", radiusFraction * 100))% of width")
print("  wrote \(outputPath) — \(Int(canvas))×\(Int(canvas)) with transparent corners")
