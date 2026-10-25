import AVFoundation
import LookshiftCore
import Vision

enum CameraFailure: Error, Sendable {
    case noCamera, configurationFailed

    var message: String {
        switch self {
        case .noCamera: "No built-in camera found. Open your Mac's lid."
        case .configurationFailed: "The camera couldn't start. Another app may be using it."
        }
    }
}

/// Runs the built-in camera and reports a `FaceReading` (or nil) about 12 times a second.
/// Frames are analysed in memory and dropped. Nothing is stored or sent anywhere.
@MainActor
final class HeadTracker {
    private(set) var isRunning = false
    private(set) var failure: CameraFailure?
    var onFailure: (() -> Void)?

    private let engine: CaptureEngine

    init(onSample: @escaping @MainActor @Sendable (FaceReading?) -> Void) {
        engine = CaptureEngine { features in
            DispatchQueue.main.async { MainActor.assumeIsolated { onSample(features) } }
        }
    }

    func start() {
        guard !isRunning, failure == nil else { return }
        isRunning = true
        engine.start { [weak self] failure in
            guard let failure else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Log.camera.error("Camera failed to start: \(String(describing: failure))")
                    self.isRunning = false
                    self.failure = failure
                    self.onFailure?()
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.stop()
    }

    /// Lets the next `start()` try again after a failure.
    func clearFailure() { failure = nil }
}

/// The capture session and frame analysis. All mutable state is confined to `queue`.
private final class CaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Lookshift.camera")
    private let session = AVCaptureSession()
    private let request = VNDetectFaceLandmarksRequest()
    private let deliver: @Sendable (FaceReading?) -> Void
    private var configured = false
    private var lastFrame: TimeInterval = 0
    private let frameInterval: TimeInterval = 1.0 / 12

    init(deliver: @escaping @Sendable (FaceReading?) -> Void) {
        self.deliver = deliver
    }

    func start(completion: @escaping @Sendable (CameraFailure?) -> Void) {
        queue.async { [self] in
            do {
                if !configured { try configure() }
                session.startRunning()
                completion(nil)
            } catch {
                completion(error as? CameraFailure ?? .configurationFailed)
            }
        }
    }

    func stop() {
        queue.async { [self] in session.stopRunning() }
    }

    private func configure() throws {
        // Built-in camera only, so virtual cameras and an iPhone are never picked.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        guard let device = discovery.devices.first else { throw CameraFailure.noCamera }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Eyes are small; 720p gives the pupil search enough pixels.
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            throw CameraFailure.configurationFailed
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        // Plane 0 of this format is plain grayscale, which the pupil search reads directly.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraFailure.configurationFailed }
        session.addOutput(output)
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= frameInterval, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now

        do {
            try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])
        } catch {
            deliver(nil)
            return
        }
        let face = request.results?.max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }
        deliver(face.flatMap { Self.reading(of: $0, in: pixels) })
    }

    private static func reading(of face: VNFaceObservation, in pixels: CVPixelBuffer) -> FaceReading? {
        guard let landmarks = face.landmarks,
              let nose = landmarks.nose?.normalizedPoints,
              let left = landmarks.leftEye, let right = landmarks.rightEye else { return nil }
        let l = left.normalizedPoints, r = right.normalizedPoints
        let leftPupil = landmarks.leftPupil?.normalizedPoints.first
        let rightPupil = landmarks.rightPupil?.normalizedPoints.first
        guard let head = FaceGeometry.headTurn(nose: nose, leftEye: l, rightEye: r),
              let tilt = FaceGeometry.headTilt(nose: nose, leftEye: l, rightEye: r),
              let eyesX = FaceGeometry.average(FaceGeometry.pupilOffset(eye: l, pupil: leftPupil),
                                               FaceGeometry.pupilOffset(eye: r, pupil: rightPupil)),
              let eyesY = FaceGeometry.average(FaceGeometry.pupilOffsetY(eye: l, pupil: leftPupil),
                                               FaceGeometry.pupilOffsetY(eye: r, pupil: rightPupil)),
              let dark = darkPupilOffsets(left: left, right: right, in: pixels)
        else { return nil }
        let horizontal = [head, eyesX, dark.x]
        // Where the face sits in the frame matters for a point on screen: the same
        // head angle looks at a different spot when you lean sideways.
        let box = face.boundingBox
        return FaceReading(horizontal: horizontal,
                           all: horizontal + [tilt, eyesY, dark.y, Double(box.midX), Double(box.midY), Double(box.width)])
    }

    /// Dark-pupil offsets, horizontal and vertical, averaged over both eyes.
    private static func darkPupilOffsets(left: VNFaceLandmarkRegion2D, right: VNFaceLandmarkRegion2D,
                                         in pixels: CVPixelBuffer) -> (x: Double, y: Double)? {
        let format = CVPixelBufferGetPixelFormatType(pixels)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return nil }

        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)
        let plane = LumaPlane(width: width, height: height) { x, y in luma[y * rowBytes + x] }

        // Vision's origin is bottom-left; pixel rows run top-down.
        let size = CGSize(width: width, height: height)
        let outline = { (eye: VNFaceLandmarkRegion2D) in
            eye.pointsInImage(imageSize: size).map { CGPoint(x: $0.x, y: CGFloat(height) - $0.y) }
        }
        let l = outline(left), r = outline(right)
        guard let x = FaceGeometry.average(PupilFinder.offset(eye: l, in: plane), PupilFinder.offset(eye: r, in: plane)),
              let y = FaceGeometry.average(PupilFinder.verticalOffset(eye: l, in: plane),
                                           PupilFinder.verticalOffset(eye: r, in: plane)) else { return nil }
        return (x, y)
    }
}
