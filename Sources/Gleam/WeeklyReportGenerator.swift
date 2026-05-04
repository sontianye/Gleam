import AppKit
import CoreImage
import CoreGraphics

/// Generates a weekly collage of smile photos and delivers a notification.
actor WeeklyReportGenerator {

    /// Renders a grid collage from the given photos and returns the saved URL.
    func generate(photos: [PhotoManager.SmilePhoto], weekStats: (count: Int, peak: String)) async throws -> URL {
        guard !photos.isEmpty else { throw GleamError.noPhotosForReport }

        let columns   = 3
        let thumbSize = CGSize(width: 200, height: 200)
        let padding: CGFloat = 12
        let headerHeight: CGFloat = 80

        let rows   = Int(ceil(Double(min(photos.count, 9)) / Double(columns)))
        let width  = CGFloat(columns) * (thumbSize.width + padding) + padding
        let height = CGFloat(rows) * (thumbSize.height + padding) + padding + headerHeight

        let outputSize = CGSize(width: width, height: height)

        guard let context = CGContext(
            data: nil,
            width: Int(outputSize.width),
            height: Int(outputSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GleamError.imageEncodingFailed }

        // Background
        context.setFillColor(CGColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1))
        context.fill(CGRect(origin: .zero, size: outputSize))

        // Draw thumbnails (up to 9)
        let ciContext = CIContext()
        for (idx, photo) in photos.prefix(9).enumerated() {
            let col = idx % columns
            let row = idx / columns
            let x = padding + CGFloat(col) * (thumbSize.width + padding)
            // CoreGraphics origin is bottom-left; flip rows
            let y = padding + CGFloat(rows - 1 - row) * (thumbSize.height + padding)
            let rect = CGRect(origin: CGPoint(x: x, y: y), size: thumbSize)

            let ciImg = CIImage(contentsOf: photo.url)?.cropped(toAspectRatio: 1) ?? CIImage()
            if let cgImg = ciContext.createCGImage(ciImg, from: ciImg.extent) {
                context.draw(cgImg, in: rect)
            }
        }

        // Header text
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let title = NSAttributedString(string: "✨ \(weekStats.count) smiles this week", attributes: titleAttrs)
        let titleLine = CTLineCreateWithAttributedString(title)
        context.textPosition = CGPoint(x: padding, y: outputSize.height - headerHeight + 20)
        CTLineDraw(titleLine, context)

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.gray
        ]
        let sub = NSAttributedString(string: "Happiest hour: \(weekStats.peak)  •  Made by Gleam", attributes: subAttrs)
        let subLine = CTLineCreateWithAttributedString(sub)
        context.textPosition = CGPoint(x: padding, y: outputSize.height - headerHeight + 0)
        CTLineDraw(subLine, context)

        guard let cgImage = context.makeImage() else { throw GleamError.imageEncodingFailed }

        // Save
        let dir = URL.gleamSupportDirectory.appendingPathComponent("reports")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("week-\(weekTag()).jpg")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(dest)

        return url
    }

    private func weekTag() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-'W'ww"
        return f.string(from: Date())
    }
}

// MARK: - CIImage crop helper

private extension CIImage {
    func cropped(toAspectRatio ratio: CGFloat) -> CIImage {
        let w = extent.width
        let h = extent.height
        if w == h { return self }
        if w > h {
            let dx = (w - h) / 2
            return cropped(to: CGRect(x: extent.minX + dx, y: extent.minY, width: h, height: h))
        } else {
            let dy = (h - w) / 2
            return cropped(to: CGRect(x: extent.minX, y: extent.minY + dy, width: w, height: w))
        }
    }
}
