#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Configuration

let size: CGFloat = 1024
let outputPath = "ios/Orbi/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

// MARK: - Color helpers

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> [CGFloat] {
    return [r, g, b, a]
}

// MARK: - Drawing

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create CGContext")
}

// Flip coordinate system so (0,0) is top-left (matches SwiftUI)
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// 1. Fill background with dark navy
let bgColor = CGColor(colorSpace: colorSpace, components: [0.05, 0.08, 0.15, 1.0])!
ctx.setFillColor(bgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// 2. Draw the gradient globe
let globeRadius = size * 0.35
let centerX = size / 2
let centerY = size / 2

// Globe gradient colors: blue → teal → green → lime (topLeading to bottomTrailing)
let globeColors: [CGFloat] = [
    0.1, 0.4, 0.85, 1.0,   // blue
    0.0, 0.65, 0.75, 1.0,  // teal
    0.2, 0.75, 0.3, 1.0,   // green
    0.5, 0.85, 0.2, 1.0,   // lime
]
let globeLocations: [CGFloat] = [0.0, 0.33, 0.66, 1.0]

guard let globeGradient = CGGradient(
    colorSpace: colorSpace,
    colorComponents: globeColors,
    locations: globeLocations,
    count: 4
) else {
    fatalError("Failed to create globe gradient")
}

// Clip to circle and draw linear gradient (topLeading to bottomTrailing)
ctx.saveGState()
let globeRect = CGRect(
    x: centerX - globeRadius,
    y: centerY - globeRadius,
    width: globeRadius * 2,
    height: globeRadius * 2
)
ctx.addEllipse(in: globeRect)
ctx.clip()
ctx.drawLinearGradient(
    globeGradient,
    start: CGPoint(x: centerX - globeRadius, y: centerY - globeRadius),
    end: CGPoint(x: centerX + globeRadius, y: centerY + globeRadius),
    options: []
)
ctx.restoreGState()

// 3. Draw specular highlight on globe
ctx.saveGState()
ctx.addEllipse(in: globeRect)
ctx.clip()

let highlightColors: [CGFloat] = [
    1.0, 1.0, 1.0, 0.35,  // white, 35% opacity at center
    1.0, 1.0, 1.0, 0.0,   // white, 0% opacity at edge
]
let highlightLocations: [CGFloat] = [0.0, 1.0]
guard let highlightGradient = CGGradient(
    colorSpace: colorSpace,
    colorComponents: highlightColors,
    locations: highlightLocations,
    count: 2
) else {
    fatalError("Failed to create highlight gradient")
}

// Highlight center offset: 35% from left, 25% from top of globe
let highlightCenterX = centerX - globeRadius * 0.3
let highlightCenterY = centerY - globeRadius * 0.5
ctx.drawRadialGradient(
    highlightGradient,
    startCenter: CGPoint(x: highlightCenterX, y: highlightCenterY),
    startRadius: 0,
    endCenter: CGPoint(x: highlightCenterX, y: highlightCenterY),
    endRadius: globeRadius * 0.7,
    options: []
)
ctx.restoreGState()

// 4. Draw the orbital ring (ellipse tilted at -30 degrees)
// The ring is an ellipse with width = size * 0.95, height = size * 0.3, rotated -30 degrees
// We draw the back arc first (behind globe), then the globe on top, then the front arc

// Helper to draw an elliptical arc with rotation
func drawEllipticalArc(
    context: CGContext,
    cx: CGFloat, cy: CGFloat,
    rx: CGFloat, ry: CGFloat,
    rotation: CGFloat,  // in radians
    startAngle: CGFloat, endAngle: CGFloat,  // in radians
    lineWidth: CGFloat,
    color: CGColor
) {
    context.saveGState()
    context.translateBy(x: cx, y: cy)
    context.rotate(by: rotation)
    context.scaleBy(x: 1.0, y: ry / rx)

    context.setStrokeColor(color)
    context.setLineWidth(lineWidth * (rx / ry))
    context.setLineCap(.round)
    context.addArc(center: .zero, radius: rx, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    context.strokePath()

    context.restoreGState()
}

let ringRx = size * 0.475   // half-width of ellipse
let ringRy = size * 0.15    // half-height of ellipse
let ringRotation = -30.0 * .pi / 180.0  // -30 degrees in radians
let ringLineWidth = size * 0.028

// Back arc of ring (behind globe) — full ring at low opacity
let backRingColor = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.2])!
drawEllipticalArc(
    context: ctx,
    cx: centerX, cy: centerY,
    rx: ringRx, ry: ringRy,
    rotation: ringRotation,
    startAngle: 0, endAngle: .pi * 2,
    lineWidth: ringLineWidth * 0.85,
    color: backRingColor
)

// Re-draw the globe on top to create the "ring goes behind" effect
// Slightly smaller globe (0.62 ratio like the SwiftUI version)
let frontGlobeRadius = size * 0.31
ctx.saveGState()
let frontGlobeRect = CGRect(
    x: centerX - frontGlobeRadius,
    y: centerY - frontGlobeRadius,
    width: frontGlobeRadius * 2,
    height: frontGlobeRadius * 2
)
ctx.addEllipse(in: frontGlobeRect)
ctx.clip()
ctx.drawLinearGradient(
    globeGradient,
    start: CGPoint(x: centerX - frontGlobeRadius, y: centerY - frontGlobeRadius),
    end: CGPoint(x: centerX + frontGlobeRadius, y: centerY + frontGlobeRadius),
    options: []
)
ctx.restoreGState()

// Re-draw specular highlight on front globe
ctx.saveGState()
ctx.addEllipse(in: frontGlobeRect)
ctx.clip()
ctx.drawRadialGradient(
    highlightGradient,
    startCenter: CGPoint(x: highlightCenterX, y: highlightCenterY),
    startRadius: 0,
    endCenter: CGPoint(x: highlightCenterX, y: highlightCenterY),
    endRadius: frontGlobeRadius * 0.65,
    options: []
)
ctx.restoreGState()

// Front arc of ring (in front of globe) — brighter, partial arc
// In the SwiftUI version, trim(from: 0.55, to: 0.95) with -30 degree rotation
// That corresponds to angles: 0.55 * 2π to 0.95 * 2π
let frontArcStart = 0.55 * 2.0 * .pi
let frontArcEnd = 0.95 * 2.0 * .pi
let frontRingColor = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 0.85])!
drawEllipticalArc(
    context: ctx,
    cx: centerX, cy: centerY,
    rx: ringRx, ry: ringRy,
    rotation: ringRotation,
    startAngle: CGFloat(frontArcStart), endAngle: CGFloat(frontArcEnd),
    lineWidth: ringLineWidth,
    color: frontRingColor
)

// MARK: - Save as PNG

guard let image = ctx.makeImage() else {
    fatalError("Failed to create CGImage")
}

// Determine output URL
let scriptDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputURL = scriptDir.appendingPathComponent(outputPath)

// Ensure directory exists
let outputDir = outputURL.deletingLastPathComponent()
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Failed to create image destination at \(outputURL.path)")
}

CGImageDestinationAddImage(destination, image, nil)

guard CGImageDestinationFinalize(destination) else {
    fatalError("Failed to write PNG to \(outputURL.path)")
}

print("✅ App icon generated at: \(outputURL.path)")
