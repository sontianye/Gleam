import AppKit
import CoreGraphics

// Generates Gleam app icon at all required sizes and packages into .icns
// Run: swift scripts/generate-icon.swift

let sizes: [Int] = [16, 32, 128, 256, 512, 1024]

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Rounded rect background with gradient
    let cornerRadius = s * 0.2237 // ~22.37% per Apple HIG
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.addPath(path)
    ctx.clip()

    // Gradient: warm yellow → orange
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0),   // warm yellow
        CGColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0),   // orange
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: s, y: 0),
            options: []
        )
    }

    // Subtle inner highlight at top
    let highlightColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
    ] as CFArray
    if let highlightGrad = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0.0, 0.5]) {
        ctx.drawLinearGradient(
            highlightGrad,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: 0, y: s * 0.5),
            options: []
        )
    }

    // SF Symbol: face.smiling
    let symbolSize = s * 0.55
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {

        // Tint white
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
        if let tintCtx = NSGraphicsContext.current?.cgContext {
            tintCtx.setBlendMode(.sourceIn)
            tintCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
            tintCtx.fill(NSRect(origin: .zero, size: symbol.size))
        }
        tinted.unlockFocus()

        // Center the symbol
        let symbolRect = NSRect(
            x: (s - symbol.size.width) / 2,
            y: (s - symbol.size.height) / 2 - s * 0.02,
            width: symbol.size.width,
            height: symbol.size.height
        )
        tinted.draw(in: symbolRect)
    }

    image.unlockFocus()
    return image
}

// Generate iconset
let fileManager = FileManager.default
let iconsetURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    .appendingPathComponent("Sources/Gleam/Resources/AppIcon.iconset")

try? fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for size in sizes {
    let image = drawIcon(size: size)
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    rep.size = NSSize(width: size, height: size)

    let pngData = rep.representation(using: .png, properties: [:])!

    if size == 1024 {
        // 1024 only has 1x
        let filename = "icon_512x512@2x.png"
        try pngData.write(to: iconsetURL.appendingPathComponent(filename))
    } else {
        // 1x
        let filename = "icon_\(size)x\(size).png"
        try pngData.write(to: iconsetURL.appendingPathComponent(filename))

        // 2x (draw at 2x size, save as @2x)
        if size <= 512 {
            let image2x = drawIcon(size: size * 2)
            let rep2x = NSBitmapImageRep(data: image2x.tiffRepresentation!)!
            rep2x.size = NSSize(width: size, height: size)
            let pngData2x = rep2x.representation(using: .png, properties: [:])!
            let filename2x = "icon_\(size)x\(size)@2x.png"
            try pngData2x.write(to: iconsetURL.appendingPathComponent(filename2x))
        }
    }
}

// Convert to .icns
let icnsURL = iconsetURL.deletingPathExtension().appendingPathExtension("icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icnsURL.path, iconsetURL.path]
try process.run()
process.waitUntilExit()

// Clean up iconset
try? fileManager.removeItem(at: iconsetURL)

if process.terminationStatus == 0 {
    print("Generated: \(icnsURL.path)")
} else {
    print("Error: iconutil failed with status \(process.terminationStatus)")
}
