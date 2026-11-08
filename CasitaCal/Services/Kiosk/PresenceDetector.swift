@preconcurrency import AVFoundation
import UIKit
import Vision

/// Wakes the kitchen display when someone walks up to it, using the front camera.
///
/// Runs only while the slideshow is showing. Frames are checked for a face a few times a
/// second and thrown away — nothing is recorded, saved or sent anywhere. iPadOS shows its green
/// camera dot while this runs.
final class PresenceDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// A face at least this tall (fraction of the frame) counts as "walked up" (~1–1.5 m away).
    static let minFaceHeight: CGFloat = 0.10
    /// How often frames are checked.
    static let interval: TimeInterval = 0.25

    private let queue = DispatchQueue(label: "casitacal.presence")
    private let session = AVCaptureSession()
    private var configured = false
    private var lastCheck = Date.distantPast
    private var hits = 0
    private let onPresence: @MainActor () -> Void

    init(onPresence: @escaping @MainActor () -> Void) {
        self.onPresence = onPresence
    }

    static var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    @MainActor
    func start() {
        guard Self.isAuthorized else { return }
        // Match frames to the screen's orientation so faces come in upright.
        let angle: CGFloat? = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front).map {
            AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: nil).videoRotationAngleForHorizonLevelCapture
        }
        queue.async { [self] in
            if !configured { configure() }
            if let angle, let connection = (session.outputs.first as? AVCaptureVideoDataOutput)?.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            hits = 0
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        configured = true
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastCheck) >= Self.interval else { return }
        lastCheck = now

        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up).perform([request])
        let close = (request.results ?? []).contains { $0.boundingBox.height >= Self.minFaceHeight }
        hits = close ? hits + 1 : 0
        // Two checks in a row (~half a second) so a passing reflection doesn't wake it.
        if hits >= 2 {
            hits = 0
            let wake = onPresence
            Task { @MainActor in wake() }
        }
    }
}
