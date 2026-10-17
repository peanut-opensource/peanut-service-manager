import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: generate-app-icons.swift <iconset-directory> <menu-bar-png>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let menuURL = URL(fileURLWithPath: arguments[2])

func drawPeanut(in rect: CGRect, color: NSColor, detailed: Bool) {
    let scale = min(rect.width, rect.height)
    let path = NSBezierPath()
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
    }
    // A single shell with three chambers and an attached sprout reads as a peanut,
    // while avoiding the paired-bulb silhouette that resembles a dog bone.
    path.move(to: point(0.48, 0.06))
    path.curve(to: point(0.66, 0.13), controlPoint1: point(0.34, 0.00), controlPoint2: point(0.64, 0.00))
    path.curve(to: point(0.70, 0.42), controlPoint1: point(0.76, 0.22), controlPoint2: point(0.72, 0.32))
    path.curve(to: point(0.66, 0.76), controlPoint1: point(0.69, 0.53), controlPoint2: point(0.70, 0.66))
    path.curve(to: point(0.55, 0.94), controlPoint1: point(0.64, 0.87), controlPoint2: point(0.62, 0.94))
    path.curve(to: point(0.43, 0.94), controlPoint1: point(0.50, 1.00), controlPoint2: point(0.43, 1.00))
    path.curve(to: point(0.33, 0.76), controlPoint1: point(0.36, 0.94), controlPoint2: point(0.34, 0.87))
    path.curve(to: point(0.30, 0.42), controlPoint1: point(0.30, 0.66), controlPoint2: point(0.31, 0.53))
    path.curve(to: point(0.34, 0.13), controlPoint1: point(0.28, 0.32), controlPoint2: point(0.24, 0.22))
    path.curve(to: point(0.48, 0.06), controlPoint1: point(0.36, 0.00), controlPoint2: point(0.48, 0.00))
    path.close()
    color.setFill()
    path.fill()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let ridgeColor = NSColor(calibratedRed: 0.58, green: 0.33, blue: 0.13, alpha: detailed ? 0.62 : 0.45)
    ridgeColor.setStroke()
    let detailedRidges: [[NSPoint]] = [
        [point(0.37, 0.23), point(0.44, 0.27), point(0.56, 0.27), point(0.63, 0.23)],
        [point(0.38, 0.39), point(0.45, 0.43), point(0.55, 0.43), point(0.62, 0.39)],
        [point(0.39, 0.57), point(0.46, 0.61), point(0.55, 0.61), point(0.61, 0.57)],
        [point(0.36, 0.75), point(0.44, 0.79), point(0.55, 0.79), point(0.64, 0.75)]
    ]
    let simpleRidges: [[NSPoint]] = [detailedRidges[1], detailedRidges[2]]
    let ridges = detailed ? detailedRidges : simpleRidges
    for ridge in ridges {
        let line = NSBezierPath()
        line.lineWidth = max(0.55, scale * 0.008)
        line.lineCapStyle = .round
        line.move(to: ridge[0])
        line.curve(to: ridge[3], controlPoint1: ridge[1], controlPoint2: ridge[2])
        line.stroke()
    }
    if detailed {
        NSColor(calibratedRed: 0.54, green: 0.34, blue: 0.20, alpha: 0.34).setFill()
        for band in -1...1 {
            for index in 0..<8 {
                let t = 0.10 + CGFloat(index) * 0.112
                let stagger: CGFloat = index.isMultiple(of: 2) ? -0.018 : 0.018
                let offset = CGFloat(band) * 0.13 + stagger
                let x = 0.39 + offset
                let y = 0.18 + 0.66 * t
                let diameter = scale * (0.014 + CGFloat(index % 3) * 0.003)
                let center = point(x, y)
                NSBezierPath(ovalIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)).fill()
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}

func renderPNG(pixelSize: Int, points: CGFloat, appIcon: Bool) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: points, height: points)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let bounds = CGRect(origin: .zero, size: rep.size)
    if appIcon {
        let inset = points * 0.035
        let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: points * 0.23, yRadius: points * 0.23)
        NSColor(calibratedRed: 0.08, green: 0.36, blue: 0.36, alpha: 1).setFill()
        tile.fill()
        let pod = CGRect(x: points * 0.17, y: points * 0.08, width: points * 0.66, height: points * 0.82)
        drawPeanut(in: pod, color: NSColor(calibratedRed: 0.94, green: 0.72, blue: 0.39, alpha: 1), detailed: true)
        let stem = NSBezierPath()
        stem.lineWidth = points * 0.035
        stem.lineCapStyle = .round
        stem.move(to: CGPoint(x: points * 0.58, y: points * 0.64))
        stem.curve(to: CGPoint(x: points * 0.69, y: points * 0.73), controlPoint1: CGPoint(x: points * 0.62, y: points * 0.67), controlPoint2: CGPoint(x: points * 0.66, y: points * 0.71))
        NSColor(calibratedRed: 0.31, green: 0.55, blue: 0.34, alpha: 1).setStroke()
        stem.stroke()
        let leaf = NSBezierPath()
        leaf.move(to: CGPoint(x: points * 0.67, y: points * 0.70))
        leaf.curve(to: CGPoint(x: points * 0.84, y: points * 0.75), controlPoint1: CGPoint(x: points * 0.74, y: points * 0.78), controlPoint2: CGPoint(x: points * 0.82, y: points * 0.78))
        leaf.curve(to: CGPoint(x: points * 0.67, y: points * 0.70), controlPoint1: CGPoint(x: points * 0.80, y: points * 0.66), controlPoint2: CGPoint(x: points * 0.73, y: points * 0.66))
        NSColor(calibratedRed: 0.42, green: 0.69, blue: 0.43, alpha: 1).setFill()
        leaf.fill()
    } else {
        let pod = CGRect(x: points * 0.17, y: points * 0.08, width: points * 0.66, height: points * 0.82)
        drawPeanut(in: pod, color: .black, detailed: false)
        let leaf = NSBezierPath()
        leaf.move(to: CGPoint(x: points * 0.68, y: points * 0.70))
        leaf.curve(to: CGPoint(x: points * 0.83, y: points * 0.75), controlPoint1: CGPoint(x: points * 0.75, y: points * 0.77), controlPoint2: CGPoint(x: points * 0.82, y: points * 0.77))
        leaf.curve(to: CGPoint(x: points * 0.68, y: points * 0.70), controlPoint1: CGPoint(x: points * 0.80, y: points * 0.66), controlPoint2: CGPoint(x: points * 0.74, y: points * 0.66))
        NSColor.black.setFill()
        leaf.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconSizes: [(String, Int, CGFloat)] = [
    ("icon_16x16.png", 16, 16), ("icon_16x16@2x.png", 32, 16),
    ("icon_32x32.png", 32, 32), ("icon_32x32@2x.png", 64, 32),
    ("icon_128x128.png", 128, 128), ("icon_128x128@2x.png", 256, 128),
    ("icon_256x256.png", 256, 256), ("icon_256x256@2x.png", 512, 256),
    ("icon_512x512.png", 512, 512), ("icon_512x512@2x.png", 1024, 512)
]
for (name, pixels, points) in iconSizes {
    try renderPNG(pixelSize: pixels, points: points, appIcon: true).write(to: iconsetURL.appendingPathComponent(name), options: .atomic)
}
try FileManager.default.createDirectory(at: menuURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try renderPNG(pixelSize: 36, points: 18, appIcon: false).write(to: menuURL, options: .atomic)
