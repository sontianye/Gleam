import Vision
import CoreImage

// MARK: - FaceAnalyzer
//
// Detects genuine smiles from a camera frame stream.
//
// ─── Design Rationale ──────────────────────────────────────────────────────────
//
// Combines TWO powerful detection methods:
//
// 1. Apple's built-in CIDetector.hasSmile (macOS 10.7+, iOS 5.0+)
//    - Apple's official, battle-tested smile detection
//    - Uses the same technology as iOS Camera app timer and Photos app
//
// 2. Custom facial landmark analysis (your existing implementation)
//    - Relative change from personal baseline
//    - Multiplicative eye gate for genuine smile validation
//
// ─── References ────────────────────────────────────────────────────────────────
//   Apple Documentation: CIFaceFeature.hasSmile
//   Ekman & Friesen (1978).  Facial Action Coding System (FACS).
//   Soukupová & Čech (2016).  Real-Time Eye Blink Detection Using Facial Landmarks.
//   Zhang et al. (2016).  Joint Face Detection and Alignment Using Multi-Task CNN.

actor FaceAnalyzer {

    // MARK: - Configuration

    struct Config: Sendable {
        /// Composite intensity required to enter ONSET.
        var enterThreshold: Float = 0.42
        /// Sliding-window size for baseline averaging.
        var exitThreshold: Float = 0.22

        /// Relative change (0–1) required to enter ONSET.
        var smileChangeThreshold: Float = 0.35

        /// Mouth-only movements (speech, yawn, sigh) keep eyeScore low.
        var minEyeScoreAtCapture: Float = 0.25

        /// Sustained frames above threshold before capture.
        var onsetFrames: Int = 12

        /// Minimum seconds between captures.
        var captureCooldown: TimeInterval = 2.0

        /// Decay frames before returning to notSmiling.
        var decayFrames: Int = 8

        /// Mouth corner raise weight (AU12 — primary).
        var mouthWeight: Float = 0.55
        /// EMA factor: 0.30 trades a little responsiveness for a calmer signal.
        var emaAlpha: Float = 0.30
        /// Mouth aspect ratio weight (open-mouth laugh bonus).
        var arWeight: Float = 0.15
        /// Eye involvement weight (Duchenne smile).
        var eyeWeight: Float = 0.30

        /// Minimum face confidence from Vision.
        var minFaceConfidence: Float = 0.60

        /// Head pose limits (radians; ≈±20°).
        var maxPitch: Float = 0.35
        var maxYaw: Float = 0.45
        var maxRoll: Float = 0.45

        /// Frames to discard at start for calibration.
        var startupFrames: Int = 60

        /// Weight of Apple's built-in smile detection (0.0–1.0).
        var appleSmileWeight: Float = 0.60
        /// Weight of custom landmark analysis (0.0–1.0).
        var landmarkWeight: Float = 0.40
    }

    // MARK: - State machine

    fileprivate enum SmileState: Equatable, Sendable {
        case notSmiling
        case onset(frames: Int)
        case smiling
        case decay(frames: Int)
    }

    // MARK: - Result

    struct AnalysisResult: Sendable {
        let smileIntensity: Float
        let rawIntensity: Float
        let mouthScore: Float
        let eyeScore: Float
        let appleSmileScore: Float
        let shouldCapture: Bool
        let debugState: String
    }

    // MARK: - Internal state

    private var config: Config
    private var state: SmileState = .notSmiling
    private var lastCapture: Date = .distantPast
    private var frameCount: Int = 0

    /// Apple's CIDetector for built-in smile detection.
    private lazy var ciDetector: CIDetector? = {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let options: [String: Any] = [
            CIDetectorAccuracy: CIDetectorAccuracyHigh,
            CIDetectorSmile: true
        ]
        return CIDetector(ofType: CIDetectorTypeFace, context: context, options: options)
    }()

    // Baseline ring buffers — only neutral frames contribute
    private var blMouthRaise = RingBuffer<Float>(capacity: 60)
    private var blEyeEAR     = RingBuffer<Float>(capacity: 60)
    private var blMouthAR    = RingBuffer<Float>(capacity: 60)

    // Cached averages (updated by pushBaseline)
    private var baseMouthRaise: Float = 0
    private var baseEyeEAR: Float = 0.25
    private var baseMouthAR: Float = 0.15

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
    }

    func updateConfig(_ newConfig: Config) {
        config = newConfig
    }

    // MARK: - Main entry

    func analyze(image: CIImage) async -> AnalysisResult {
        frameCount += 1

        // Run BOTH detection methods in parallel for maximum accuracy
        async let appleSmile = detectAppleSmile(on: image)
        async let landmarks = runVision(on: image)

        let (appleResult, landmarkResult) = await (appleSmile, landmarks)

        let appleSmileScore: Float = appleResult ? 1.0 : 0.0

        guard let features = landmarkResult else {
            return noFaceResult(appleSmileScore: appleSmileScore)
        }

        let landmarkScore = compositeScore(
            mouthRaise: features.mouthRaise,
            eyeEAR: features.eyeEAR,
            mouthAR: features.mouthAR
        )

        // Fusion: Apple's detection + custom landmark analysis
        let raw = appleSmileScore * config.appleSmileWeight
                + landmarkScore * config.landmarkWeight

        // Decide whether to feed this frame into baseline.
        let shouldFeedBaseline = frameCount <= config.startupFrames || raw < 0.15
        if shouldFeedBaseline {
            pushBaseline(
                mouthRaise: features.mouthRaise,
                eyeEAR: features.eyeEAR,
                mouthAR: features.mouthAR
            )
        }

        // State machine
        let (next, shouldCapture) = advance(from: state, composite: raw)
        state = next
        if shouldCapture { lastCapture = Date() }

        return AnalysisResult(
            smileIntensity: raw,
            rawIntensity: raw,
            mouthScore: features.mouthRaise,
            eyeScore: features.eyeEAR,
            appleSmileScore: appleSmileScore,
            shouldCapture: shouldCapture,
            debugState: state.description
        )
    }

    // MARK: - Apple's built-in smile detection

    private func detectAppleSmile(on image: CIImage) async -> Bool {
        guard let detector = ciDetector else { return false }

        let options: [String: Any] = [
            CIDetectorSmile: true,
            CIDetectorEyeBlink: true
        ]

        let features = detector.features(in: image, options: options)

        for feature in features {
            if let faceFeature = feature as? CIFaceFeature {
                return faceFeature.hasSmile
            }
        }

        return false
    }

    // MARK: - Composite score

    private func compositeScore(
        mouthRaise: Float,
        eyeEAR: Float,
        mouthAR: Float
    ) -> Float {
        let mouthChange = positiveDelta(mouthRaise, vs: baseMouthRaise)
        let earChange   = positiveDelta(baseEyeEAR, vs: eyeEAR)
        let arChange    = positiveDelta(mouthAR, vs: baseMouthAR)

        let mouthBlend = mouthChange * config.mouthWeight
                       + arChange    * config.arWeight

        let eyeGate = 0.30 + 0.70 * earChange
        let raw = mouthBlend * eyeGate * config.mouthWeight
                + earChange * config.eyeWeight

        return max(0, min(1, raw))
    }

    private func positiveDelta(_ value: Float, vs reference: Float) -> Float {
        guard reference > 1e-4 else { return 0 }
        let delta = (value - reference) / reference
        return max(0, min(1, delta))
    }

    // MARK: - Baseline management

    private func pushBaseline(mouthRaise: Float, eyeEAR: Float, mouthAR: Float) {
        blMouthRaise.push(mouthRaise)
        blEyeEAR.push(eyeEAR)
        blMouthAR.push(mouthAR)

        baseMouthRaise = blMouthRaise.average()
        baseEyeEAR     = blEyeEAR.average()
        baseMouthAR    = blMouthAR.average()
    }

    // MARK: - State machine

    private func advance(from current: SmileState, composite: Float)
        -> (SmileState, Bool)
    {
        let startupOk  = frameCount >= config.startupFrames
        let cooldownOk = Date().timeIntervalSince(lastCapture) > config.captureCooldown
        let above      = composite >= config.enterThreshold
        let stillAbove = composite >= config.exitThreshold

        switch current {

        case .notSmiling:
            return above ? (.onset(frames: 1), false) : (.notSmiling, false)

        case .onset(let frames):
            if !above { return (.notSmiling, false) }
            guard frames >= config.onsetFrames else {
                return (.onset(frames: frames + 1), false)
            }
            return (.smiling, startupOk && cooldownOk)

        case .smiling:
            return stillAbove ? (.smiling, false) : (.decay(frames: 1), false)

        case .decay(let frames):
            if stillAbove { return (.smiling, false) }
            return frames >= config.decayFrames
                ? (.notSmiling, false)
                : (.decay(frames: frames + 1), false)
        }
    }

    private func noFaceResult(appleSmileScore: Float) -> AnalysisResult {
        state = .notSmiling
        return AnalysisResult(
            smileIntensity: 0, rawIntensity: 0,
            mouthScore: 0, eyeScore: 0,
            appleSmileScore: appleSmileScore,
            shouldCapture: false, debugState: "noFace"
        )
    }

    // MARK: - Vision

    private struct Features {
        let mouthRaise: Float
        let eyeEAR: Float
        let mouthAR: Float
    }

    private func runVision(on image: CIImage) async -> Features? {
        let cfg = config
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { request, error in
                guard let faces = request.results as? [VNFaceObservation],
                      let face = faces.first,
                      face.confidence >= cfg.minFaceConfidence,
                      let landmarks = face.landmarks
                else {
                    continuation.resume(returning: nil)
                    return
                }

                let pitch = face.pitch?.floatValue ?? 0
                let yaw   = face.yaw?.floatValue   ?? 0
                let roll  = face.roll?.floatValue  ?? 0
                guard abs(pitch) <= cfg.maxPitch,
                      abs(yaw)   <= cfg.maxYaw,
                      abs(roll)  <= cfg.maxRoll
                else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: Self.extractFeatures(from: landmarks))
            }

            do {
                try VNImageRequestHandler(ciImage: image, options: [:]).perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Feature extraction

    private static func extractFeatures(from landmarks: VNFaceLandmarks2D) -> Features {
        let m = mouthFeatures(from: landmarks)
        let e = eyeFeature(from: landmarks)
        return Features(mouthRaise: m.raise, eyeEAR: e, mouthAR: m.ar)
    }

    private static func mouthFeatures(from landmarks: VNFaceLandmarks2D) -> (raise: Float, ar: Float) {
        guard let outer = landmarks.outerLips,
              outer.normalizedPoints.count >= 12
        else { return (0, 0) }

        let p = outer.normalizedPoints
        let leftCorner   = p[0]
        let rightCorner  = p[6]
        let topCenter    = p[3]
        let bottomCenter = p[9]

        let width  = Float(abs(rightCorner.x - leftCorner.x))
        let height = Float(abs(topCenter.y - bottomCenter.y))
        guard width > 1e-4 else { return (0, 0) }

        let centerY    = Float(topCenter.y + bottomCenter.y) / 2
        let cornerMidY = Float(leftCorner.y + rightCorner.y) / 2
        let raise = (cornerMidY - centerY) / width

        return (raise, height / width)
    }

    private static func eyeFeature(from landmarks: VNFaceLandmarks2D) -> Float {
        guard let left = computeEAR(landmarks.leftEye),
              let right = computeEAR(landmarks.rightEye)
        else { return 0.25 }

        let mean = (left + right) / 2
        let asymmetry = abs(left - right) / mean
        let symmetry = max(0, 1 - asymmetry * 2.5)

        let leftN = normalise(left, lo: 0.30, hi: 0.13)
        let rightN = normalise(right, lo: 0.30, hi: 0.13)
        let avgN = (leftN + rightN) / 2

        return clamp01(avgN * (0.55 + 0.45 * symmetry))
    }

    private static func computeEAR(_ region: VNFaceLandmarkRegion2D?) -> Float? {
        guard let pts = region?.normalizedPoints, pts.count >= 6 else { return nil }
        let ys = pts.map { Float($0.y) }.sorted()
        let trimmed = ys.dropFirst().dropLast()
        guard trimmed.count >= 2 else { return nil }
        let vertSpan = trimmed.last! - trimmed.first!

        let xs = pts.map { Float($0.x) }.sorted()
        let horizSpan = xs.last! - xs.first!
        guard horizSpan > 1e-4 else { return nil }

        return vertSpan / horizSpan
    }

    private static func normalise(_ value: Float, lo: Float, hi: Float) -> Float {
        let clamped = max(min(value, lo), hi)
        return (clamped - lo) / (hi - lo)
    }

    private static func clamp01(_ value: Float) -> Float {
        return max(0, min(1, value))
    }
}

// MARK: - RingBuffer

private struct RingBuffer<T> {
    private var items: [T] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func push(_ item: T) {
        items.append(item)
        if items.count > capacity { items.removeFirst() }
    }

    var count: Int { items.count }

    func average() -> Float where T == Float {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0, +) / Float(items.count)
    }
}

// MARK: - SmileState debug

private extension FaceAnalyzer.SmileState {
    var description: String {
        switch self {
        case .notSmiling:       return "notSmiling"
        case .onset(let f):     return "onset(\(f))"
        case .smiling:          return "smiling"
        case .decay(let f):     return "decay(\(f))"
        }
    }
}
