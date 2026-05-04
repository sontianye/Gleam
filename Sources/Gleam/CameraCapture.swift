import AVFoundation
import CoreImage

/// Streams camera frames as a Swift AsyncStream.
/// All AVFoundation callbacks are dispatched internally; consumers receive frames on a background queue.
@preconcurrency
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    // MARK: - Public stream

    typealias FrameStream = AsyncStream<CIImage>

    let frames: FrameStream
    private let continuation: FrameStream.Continuation

    // MARK: - Private

    private let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "dev.gleam.camera.output", qos: .userInteractive)

    // MARK: - Init

    override init() {
        (frames, continuation) = FrameStream.makeStream()
        super.init()
    }

    // MARK: - Lifecycle

    func start() throws {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            throw GleamError.noCameraFound
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw GleamError.cameraSetupFailed }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(output) else { throw GleamError.cameraSetupFailed }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
        continuation.finish()
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        continuation.yield(image)
    }
}
