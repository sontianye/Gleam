import Foundation
@preconcurrency import CoreImage

/// Orchestrates the full pipeline: camera → face analysis → photo capture.
/// @MainActor for @Published; heavy work is offloaded via Task.detached.
@MainActor
final class SmilePipeline: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var smileIntensity: Float = 0
    @Published private(set) var lastCaptureDate: Date?

    // MARK: - Dependencies

    private let camera = CameraCapture()
    private let analyzer = FaceAnalyzer()
    private let photoManager: PhotoManager
    private let statsManager: StatsManager

    private var processingTask: Task<Void, Never>?

    // MARK: - Init

    init(photoManager: PhotoManager, statsManager: StatsManager) {
        self.photoManager = photoManager
        self.statsManager = statsManager
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        do {
            try camera.start()
            isRunning = true
            // Detach so Vision work runs on a background thread,
            // never blocking the main run loop.
            let camera    = self.camera
            let analyzer  = self.analyzer
            let photoMgr  = self.photoManager
            let statsMgr  = self.statsManager
            processingTask = Task.detached(priority: .userInitiated) { [weak self] in
                await SmilePipeline.runLoop(
                    camera: camera,
                    analyzer: analyzer,
                    photoManager: photoMgr,
                    statsManager: statsMgr,
                    pipeline: self
                )
            }
        } catch {
            print("[Gleam] ❌ Camera start failed: \(error.localizedDescription)")
            // Surface the error visibly in debug builds
            assertionFailure("[Gleam] Camera start failed: \(error)")
        }
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil
        camera.stop()
        isRunning = false
    }

    // MARK: - Processing loop (nonisolated, runs on background)

    private static func runLoop(
        camera: CameraCapture,
        analyzer: FaceAnalyzer,
        photoManager: PhotoManager,
        statsManager: StatsManager,
        pipeline: SmilePipeline?
    ) async {
        for await frame in camera.frames {
            guard !Task.isCancelled else { break }

            let result = await analyzer.analyze(image: frame)

            // Publish intensity to main thread
            await MainActor.run {
                pipeline?.smileIntensity = result.smileIntensity
            }

            guard result.shouldCapture else { continue }

            do {
                let photo = try await photoManager.save(image: frame, intensity: result.smileIntensity)
                await statsManager.recordSmile(at: photo.capturedAt)
                await MainActor.run {
                    pipeline?.lastCaptureDate = photo.capturedAt
                }
            } catch {
                print("[Gleam] Failed to save photo: \(error)")
            }
        }
    }
}
