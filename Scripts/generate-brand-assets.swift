#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fm = FileManager.default

let deepGreen = NSColor(srgbRed: 46/255, green: 143/255, blue: 79/255, alpha: 1)
let darkGreen = NSColor(srgbRed: 27/255, green: 88/255, blue: 50/255, alpha: 1)
let cream = NSColor(srgbRed: 247/255, green: 241/255, blue: 228/255, alpha: 1)
let orange = NSColor(srgbRed: 243/255, green: 154/255, blue: 74/255, alpha: 1)
let mutedGreen = NSColor(srgbRed: 90/255, green: 119/255, blue: 99/255, alpha: 1)

func ensureDirectory(_ url: URL) throws {
    try fm.createDirectory(at: url, withIntermediateDirectories: true)
}

func makeContext(width: Int, height: Int, alpha: Bool) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info: CGBitmapInfo = alpha
        ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        : CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info.rawValue)!
}

func savePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "BrandAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG destination failed"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "BrandAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
}

func drawMark(in rect: NSRect) {
    let scale = min(rect.width, rect.height) / 1024
    let center = NSPoint(x: rect.midX, y: rect.midY)

    let ringRect = NSRect(
        x: center.x - 280 * scale,
        y: center.y - 280 * scale,
        width: 560 * scale,
        height: 560 * scale
    )
    cream.setStroke()
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = 58 * scale
    ring.stroke()

    let leaf = NSBezierPath()
    leaf.move(to: NSPoint(x: center.x - 118 * scale, y: center.y - 96 * scale))
    leaf.curve(
        to: NSPoint(x: center.x + 118 * scale, y: center.y + 126 * scale),
        controlPoint1: NSPoint(x: center.x - 35 * scale, y: center.y + 88 * scale),
        controlPoint2: NSPoint(x: center.x + 78 * scale, y: center.y + 148 * scale)
    )
    leaf.curve(
        to: NSPoint(x: center.x - 118 * scale, y: center.y - 96 * scale),
        controlPoint1: NSPoint(x: center.x + 146 * scale, y: center.y - 20 * scale),
        controlPoint2: NSPoint(x: center.x + 20 * scale, y: center.y - 112 * scale)
    )
    leaf.close()
    cream.setFill()
    leaf.fill()

    darkGreen.setStroke()
    let vein = NSBezierPath()
    vein.move(to: NSPoint(x: center.x - 88 * scale, y: center.y - 70 * scale))
    vein.curve(
        to: NSPoint(x: center.x + 85 * scale, y: center.y + 93 * scale),
        controlPoint1: NSPoint(x: center.x - 8 * scale, y: center.y - 4 * scale),
        controlPoint2: NSPoint(x: center.x + 42 * scale, y: center.y + 52 * scale)
    )
    vein.lineWidth = 12 * scale
    vein.lineCapStyle = .round
    vein.stroke()

    orange.setStroke()
    let energy = NSBezierPath()
    energy.appendArc(withCenter: center, radius: 352 * scale, startAngle: -56, endAngle: 56, clockwise: false)
    energy.lineWidth = 34 * scale
    energy.lineCapStyle = .round
    energy.stroke()

    let dotRadius = 15 * scale
    orange.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x + 352 * scale - dotRadius,
        y: center.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )).fill()
}

func drawIcon(size: Int) throws -> CGImage {
    let context = makeContext(width: size, height: size, alpha: false)
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSGradient(colors: [deepGreen, darkGreen])!.draw(in: rect, angle: -45)
    drawMark(in: rect)
    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

func drawLaunchCover(width: Int, height: Int, language: String = "zh-Hans") throws -> CGImage {
    let context = makeContext(width: width, height: height, alpha: true)
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let unit = CGFloat(width) / 320
    let iconSize = 176 * unit
    let iconRect = NSRect(x: (CGFloat(width) - iconSize) / 2, y: CGFloat(height) - 206 * unit, width: iconSize, height: iconSize)
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 40 * unit, yRadius: 40 * unit)
    NSGradient(colors: [deepGreen, darkGreen])!.draw(in: iconPath, angle: -45)
    drawMark(in: iconRect)

    let title = language == "en" ? "Nutrition Diary" : "饮食营养记录"
    let slogan = language == "en" ? "Track every meal. See your balance." : "记录每一餐，看见营养平衡"
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 29 * unit, weight: .bold),
        .foregroundColor: darkGreen
    ]
    let sloganAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14 * unit, weight: .medium),
        .foregroundColor: mutedGreen
    ]
    let titleSize = title.size(withAttributes: titleAttrs)
    let sloganSize = slogan.size(withAttributes: sloganAttrs)
    title.draw(at: NSPoint(x: (CGFloat(width) - titleSize.width) / 2, y: 104 * unit), withAttributes: titleAttrs)
    slogan.draw(at: NSPoint(x: (CGFloat(width) - sloganSize.width) / 2, y: 68 * unit), withAttributes: sloganAttrs)

    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

let iosIconDir = root.appendingPathComponent("Apps/Shared/Assets.xcassets/AppIcon.appiconset")
let macIconDir = root.appendingPathComponent("Apps/macOS/Assets.xcassets/AppIcon.appiconset")
let launchDir = root.appendingPathComponent("Apps/Shared/Assets.xcassets/LaunchCover.imageset")
let previewDir = root.appendingPathComponent("Docs/Brand")
for dir in [iosIconDir, macIconDir, launchDir, previewDir] { try ensureDirectory(dir) }

let ios1024 = try drawIcon(size: 1024)
try savePNG(ios1024, to: iosIconDir.appendingPathComponent("AppIcon-1024.png"))
try savePNG(ios1024, to: previewDir.appendingPathComponent("app-icon-preview.png"))

let macSizes: [(String, Int)] = [
    ("AppIcon-mac-16.png", 16),
    ("AppIcon-mac-16@2x.png", 32),
    ("AppIcon-mac-32.png", 32),
    ("AppIcon-mac-32@2x.png", 64),
    ("AppIcon-mac-128.png", 128),
    ("AppIcon-mac-128@2x.png", 256),
    ("AppIcon-mac-256.png", 256),
    ("AppIcon-mac-256@2x.png", 512),
    ("AppIcon-mac-512.png", 512),
    ("AppIcon-mac-512@2x.png", 1024)
]
for (filename, size) in macSizes {
    let image = size == 1024 ? ios1024 : try drawIcon(size: size)
    try savePNG(image, to: macIconDir.appendingPathComponent(filename))
}

for scale in 1...3 {
    let zhImage = try drawLaunchCover(width: 320 * scale, height: 400 * scale, language: "zh-Hans")
    try savePNG(zhImage, to: launchDir.appendingPathComponent("LaunchCover@\(scale)x.png"))
    let enImage = try drawLaunchCover(width: 320 * scale, height: 400 * scale, language: "en")
    try savePNG(enImage, to: launchDir.appendingPathComponent("LaunchCover-en@\(scale)x.png"))
}
try savePNG(try drawLaunchCover(width: 960, height: 1200, language: "zh-Hans"), to: previewDir.appendingPathComponent("launch-cover-preview.png"))
try savePNG(try drawLaunchCover(width: 960, height: 1200, language: "en"), to: previewDir.appendingPathComponent("launch-cover-en-preview.png"))
print("Brand assets generated in \(root.path)")
