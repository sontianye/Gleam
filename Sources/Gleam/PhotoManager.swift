import Foundation
import CoreImage
import AppKit

/// Saves smile photos to ~/Pictures/Gleam/{year}/{month}/
/// Thread-safe via actor.
actor PhotoManager {

    // MARK: - Types

    struct SmilePhoto: Codable, Identifiable, Sendable {
        let id: UUID
        let filePath: String
        let capturedAt: Date
        let smileIntensity: Float

        var url: URL { URL(fileURLWithPath: filePath) }
    }

    // MARK: - Private

    private let ciContext = CIContext()
    private let fm = FileManager.default
    private let metadataURL: URL

    private(set) var photos: [SmilePhoto] = []

    // MARK: - Init

    init() {
        let support = URL.gleamSupportDirectory
        self.metadataURL = support.appendingPathComponent("photos.json")
        // Actor inits run before the actor is fully set up, so we call the
        // synchronous helper directly — safe because no other task can observe
        // this actor yet at init time.
        if let data = try? Data(contentsOf: support.appendingPathComponent("photos.json")),
           let decoded = try? JSONDecoder().decode([SmilePhoto].self, from: data) {
            photos = decoded.filter { FileManager.default.fileExists(atPath: $0.filePath) }
        }
    }

    // MARK: - Public

    /// Saves the given CIImage as a JPEG and records metadata.
    @discardableResult
    func save(image: CIImage, intensity: Float) throws -> SmilePhoto {
        let now = Date()
        let dir = photosDirectory(for: now)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileName = "\(ISO8601DateFormatter.filenameSafe.string(from: now)).jpg"
        let fileURL = dir.appendingPathComponent(fileName)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let jpegData = ciContext.jpegRepresentation(of: image,
                                                          colorSpace: colorSpace,
                                                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.88]) else {
            throw GleamError.imageEncodingFailed
        }

        try jpegData.write(to: fileURL)

        let photo = SmilePhoto(id: UUID(), filePath: fileURL.path, capturedAt: now, smileIntensity: intensity)
        photos.append(photo)
        persistMetadata()
        return photo
    }

    /// Photos captured in the given week (ISO week).
    func photos(inWeekOf date: Date) -> [SmilePhoto] {
        let calendar = Calendar.current
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return photos.filter {
            calendar.component(.weekOfYear, from: $0.capturedAt) == week &&
            calendar.component(.yearForWeekOfYear, from: $0.capturedAt) == year
        }
    }

    /// Photos captured today.
    func todayPhotos() -> [SmilePhoto] {
        let calendar = Calendar.current
        return photos.filter { calendar.isDateInToday($0.capturedAt) }
    }

    // MARK: - Private helpers

    private func photosDirectory(for date: Date) -> URL {
        let calendar = Calendar.current
        let year  = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return URL.gleamPhotosDirectory
            .appendingPathComponent("\(year)")
            .appendingPathComponent(String(format: "%02d", month))
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([SmilePhoto].self, from: data) else { return }
        // Filter out entries whose files no longer exist
        photos = decoded.filter { fm.fileExists(atPath: $0.filePath) }
    }

    private func persistMetadata() {
        guard let data = try? JSONEncoder().encode(photos) else { return }
        try? data.write(to: metadataURL)
    }
}

// MARK: - URL helpers

extension URL {
    static var gleamSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Gleam")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var gleamPhotosDirectory: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let dir = pictures.appendingPathComponent("Gleam")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

extension ISO8601DateFormatter {
    /// Produces filenames like "2025-05-03T143052" — no colons (invalid on macOS paths).
    /// nonisolated(unsafe) is correct here: the formatter is created once, never mutated,
    /// and only used inside the PhotoManager actor — effectively read-only after init.
    nonisolated(unsafe) static let filenameSafe: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime]   // NO withColonSeparatorInTime
        return f
    }()
}
