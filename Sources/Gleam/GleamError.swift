import Foundation

enum GleamError: LocalizedError {
    case noCameraFound
    case cameraSetupFailed
    case imageEncodingFailed
    case noPhotosForReport

    var errorDescription: String? {
        switch self {
        case .noCameraFound:        return "No camera found on this Mac."
        case .cameraSetupFailed:    return "Failed to configure the camera session."
        case .imageEncodingFailed:  return "Failed to encode image to JPEG."
        case .noPhotosForReport:    return "No photos available for this week's report."
        }
    }
}
