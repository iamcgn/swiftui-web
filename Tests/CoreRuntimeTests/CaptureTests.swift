// The camera (AVFoundation's capture session) over a stand-in for the browser's camera: what
// OldOS's camera and Hipstapaper's QR scanner call, in the order they call it. The devices and
// the permission, the session going live after the browser opens the camera, the preview layer
// as a host element (on its own, and as a representable view's `layerClass` or sublayer), frames
// to a video data output, codes to a metadata output, stills to a photo output, and recordings.
#if !os(WASI)
import AVFoundation
import AVCaptureHost
import Foundation
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Testing

/// Plays the browser's camera: keeps what the session asked for and answers when told to.
private final class StandInStream: _AVCaptureStream {
    var stopped = false
    var frames: (@MainActor (Int, Int, [UInt8], Double) -> Void)?
    var frameWidth = 0
    var codes: (@MainActor ([_AVCaptureCode]) -> Void)?
    var codeFormats: [String] = []
    var torch = false
    var zoom = 1.0
    var point: (Double, Double)?
    var recording = false

    func stop() { stopped = true }
    func deliverFrames(maxWidth: Int, fps: Double, _ deliver: (@MainActor (Int, Int, [UInt8], Double) -> Void)?) {
        frames = deliver
        frameWidth = maxWidth
    }
    func takePhoto(_ completion: @escaping @MainActor ([UInt8], Int, Int, [UInt8]) -> Void) {
        MainActor.assumeIsolated { completion([0xFF, 0xD8, 0xFF, 0xD9], 2, 1, [10, 20, 30, 255, 40, 50, 60, 255]) }
    }
    func detectCodes(formats: [String], _ deliver: (@MainActor ([_AVCaptureCode]) -> Void)?) {
        codes = deliver
        codeFormats = formats
    }
    func setTorch(_ on: Bool, level: Double) { torch = on }
    func setZoom(_ factor: Double) { zoom = factor }
    func setPointOfInterest(x: Double, y: Double) { point = (x, y) }
    func startRecording() { recording = true }
    func stopRecording(_ completion: @escaping @MainActor ([UInt8], String) -> Void) {
        recording = false
        MainActor.assumeIsolated { completion([1, 2, 3], "video/webm") }
    }
}

@MainActor
private enum StandInCamera {
    nonisolated(unsafe) static var stream: StandInStream?
    nonisolated(unsafe) static var opened: [(session: Int, facing: _AVCaptureHost.Facing, width: Int)] = []
    nonisolated(unsafe) static var started: (@MainActor (_AVCaptureStarted?) -> Void)?

    static func install(cameras: Int = 2, granted: Bool = true) {
        stream = nil
        opened = []
        started = nil
        _AVCaptureHost.cameraCount = cameras
        _AVCaptureHost.microphoneCount = 1
        _AVCaptureHost.videoAuthorization = 0
        _AVCaptureHost.audioAuthorization = 0
        _AVCaptureHost.codeFormats = ["qr_code", "ean_13", "code_128"]
        _AVCaptureHost.requestAccess = { _, completion in Task { @MainActor in completion(granted) } }
        _AVCaptureHost.open = { session, facing, width, _, started in
            let stream = StandInStream()
            StandInCamera.stream = stream
            StandInCamera.opened.append((session, facing, width))
            StandInCamera.started = started
            return stream
        }
    }

    /// The browser has the camera running at 640 × 480.
    static func goLive(torch: Bool = true) {
        started?(_AVCaptureStarted(width: 640, height: 480, hasTorch: torch, maxZoom: 4))
    }

    static func uninstall() {
        _AVCaptureHost.cameraCount = 0
        _AVCaptureHost.microphoneCount = 0
        _AVCaptureHost.requestAccess = nil
        _AVCaptureHost.open = nil
        _AVCaptureHost.codeFormats = []
        _AVCaptureHost.videoAuthorization = 0
        _AVCaptureHost.audioAuthorization = 0
    }
}

/// What the session posted.
private final class Posted: @unchecked Sendable {
    var started = 0, stopped = 0
    var errors: [AVError.Code] = []
}

private final class FrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var sizes: [(Int, Int)] = []
    var firstPixel: [UInt8] = []
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        sizes.append((CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer)))
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        firstPixel = Array(UnsafeBufferPointer(start: base, count: 4))
    }
}

private final class CodeReceiver: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var found: [AVMetadataObject] = []
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        found += metadataObjects
    }
}

private final class PhotoReceiver: NSObject, AVCapturePhotoCaptureDelegate {
    var steps: [String] = []
    var photos: [AVCapturePhoto] = []
    var error: (any Error)?
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) { steps.append("willBegin") }
    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) { steps.append("didCapture") }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        steps.append("processed")
        photos.append(photo)
        self.error = error
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {
        steps.append("finished")
    }
}

private final class MovieReceiver: NSObject, AVCaptureFileOutputRecordingDelegate {
    var started: URL?
    var finished: URL?
    var error: (any Error)?
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) { started = fileURL }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        finished = outputFileURL
        self.error = error
    }
}

/// OldOS's camera preview: a view whose layer is the preview.
private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let asSublayer: Bool
    func makeUIView(context: Context) -> UIView {
        if asSublayer {
            // Hipstapaper's scanner: the preview layer added to the view's own layer.
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
            return view
        }
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@Suite(.serialized) @MainActor
struct CaptureTests {
    init() { StandInCamera.uninstall() }

    private func makeSession(position: AVCaptureDevice.Position = .back) throws -> AVCaptureSession {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        let device = try #require(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position))
        let input = try AVCaptureDeviceInput(device: device)
        #expect(session.canAddInput(input))
        session.addInput(input)
        session.commitConfiguration()
        return session
    }

    @Test func withoutACameraThereIsNoDeviceAndRunningFails() async {
        #expect(AVCaptureDevice.default(for: .video) == nil)
        #expect(AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.isEmpty)
        #expect(AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined)
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        #expect(!granted)
        #expect(AVCaptureDevice.authorizationStatus(for: .video) == .denied)
    }

    @Test func theDevicesAreTheBrowsersCamerasByFacing() async {
        StandInCamera.install(cameras: 1)
        #expect(AVCaptureDevice.default(for: .video)?.position == .back)
        // The browser picks by facing, so a front camera is there whenever a camera is.
        #expect(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)?.position == .front)
        #expect(AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) == nil)
        #expect(AVCaptureDevice.default(for: .audio) != nil)
        StandInCamera.install(cameras: 2)
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
        #expect(found.map(\.position) == [.back, .front])
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        #expect(granted && AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        StandInCamera.uninstall()
    }

    @Test func theSessionGoesLiveWhenTheBrowserOpensTheCamera() throws {
        StandInCamera.install()
        let session = try makeSession(position: .front)
        let posted = Posted()
        let center = NotificationCenter.default
        let a = center.addObserver(forName: .AVCaptureSessionDidStartRunning, object: session, queue: nil) { _ in posted.started += 1 }
        let b = center.addObserver(forName: .AVCaptureSessionDidStopRunning, object: session, queue: nil) { _ in posted.stopped += 1 }
        defer { center.removeObserver(a); center.removeObserver(b) }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        #expect(preview._hostElementKind == .camera(session: session._identifier, live: false, mirrored: true, gravity: "AVLayerVideoGravityResizeAspectFill"))

        session.startRunning()
        #expect(session.isRunning && !session._isLive)
        #expect(StandInCamera.opened.count == 1)
        #expect(StandInCamera.opened.first?.facing == .user && StandInCamera.opened.first?.width == 640)
        StandInCamera.goLive()
        #expect(session._isLive && posted.started == 1)
        // The front camera's picture is mirrored, as on a phone.
        #expect(preview._hostElementKind == .camera(session: session._identifier, live: true, mirrored: true, gravity: "AVLayerVideoGravityResizeAspectFill"))
        #expect(AVCaptureVideoPreviewLayer(session: session).connection?.isVideoMirrored == true)

        session.stopRunning()
        #expect(!session.isRunning && StandInCamera.stream?.stopped == true && posted.stopped == 1)
        #expect(preview._hostElementKind == .camera(session: session._identifier, live: false, mirrored: true, gravity: "AVLayerVideoGravityResizeAspectFill"))
        StandInCamera.uninstall()
    }

    @Test func aRefusedCameraPostsARuntimeError() throws {
        StandInCamera.install()
        let session = try makeSession()
        let posted = Posted()
        let observer = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { note in
            if let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError { posted.errors.append(error.code) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        session.startRunning()
        _AVCaptureHost.videoAuthorization = AVAuthorizationStatus.denied.rawValue
        StandInCamera.started?(nil)
        #expect(posted.errors == [.applicationIsNotAuthorizedToUseDevice])
        #expect(!session.isRunning && StandInCamera.stream?.stopped == true)
        StandInCamera.uninstall()
    }

    @Test func switchingCamerasReopensTheStream() throws {
        StandInCamera.install()
        let session = try makeSession()
        session.startRunning()
        StandInCamera.goLive()
        let first = StandInCamera.stream
        session.beginConfiguration()
        session.removeInput(session.inputs[0])
        let front = try #require(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front))
        session.addInput(try AVCaptureDeviceInput(device: front))
        session.commitConfiguration()
        #expect(first?.stopped == true)
        #expect(StandInCamera.opened.map(\.facing) == [.environment, .user])
        session.stopRunning()
        StandInCamera.uninstall()
    }

    @Test func framesArriveAsBGRAPixelBuffers() throws {
        StandInCamera.install()
        let session = try makeSession()
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let receiver = FrameReceiver()
        output.setSampleBufferDelegate(receiver, queue: .main)
        #expect(session.canAddOutput(output))
        session.addOutput(output)
        output.connection(with: .video)?.videoOrientation = .portrait
        session.startRunning()
        StandInCamera.goLive()
        let stream = try #require(StandInCamera.stream)
        #expect(stream.frames != nil && stream.frameWidth == 640)
        stream.frames?(2, 1, [1, 2, 3, 4, 5, 6, 7, 8], 0.5)
        #expect(receiver.sizes.count == 1 && receiver.sizes[0] == (2, 1))
        #expect(receiver.firstPixel == [1, 2, 3, 4])
        // No delegate, no frames.
        output.setSampleBufferDelegate(nil, queue: nil)
        #expect(stream.frames == nil)
        session.stopRunning()
        StandInCamera.uninstall()
    }

    @Test func codesArriveAsMachineReadableObjects() throws {
        StandInCamera.install()
        let session = try makeSession()
        let output = AVCaptureMetadataOutput()
        // Before it is in a session it can find nothing, as on iOS.
        #expect(output.availableMetadataObjectTypes.isEmpty)
        session.addOutput(output)
        let receiver = CodeReceiver()
        output.setMetadataObjectsDelegate(receiver, queue: .main)
        output.metadataObjectTypes = [.qr, .aztec]
        #expect(output.metadataObjectTypes == [.qr], "the browser can't read Aztec codes here")
        session.startRunning()
        StandInCamera.goLive()
        let stream = try #require(StandInCamera.stream)
        #expect(stream.codeFormats == ["qr_code"])
        stream.codes?([_AVCaptureCode(format: "qr_code", value: "https://example.com", corners: [0.25, 0.25, 0.75, 0.25, 0.75, 0.75, 0.25, 0.75])])
        let code = try #require(receiver.found.first as? AVMetadataMachineReadableCodeObject)
        #expect(code.type == .qr && code.stringValue == "https://example.com")
        #expect(code.bounds == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))

        // In a 320 × 240 layer filled by the 4:3 picture, the code's corners in points.
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = CGRect(x: 0, y: 0, width: 320, height: 240)
        let placed = try #require(preview.transformedMetadataObject(for: code) as? AVMetadataMachineReadableCodeObject)
        #expect(placed.corners.first == CGPoint(x: 80, y: 60))
        #expect(placed.bounds == CGRect(x: 80, y: 60, width: 160, height: 120))
        #expect(preview.captureDevicePointConverted(fromLayerPoint: CGPoint(x: 160, y: 120)) == CGPoint(x: 0.5, y: 0.5))
        session.stopRunning()
        StandInCamera.uninstall()
    }

    @Test func aPhotoIsTheStreamsStillAsJPEG() throws {
        StandInCamera.install()
        let session = try makeSession()
        let output = AVCapturePhotoOutput()
        session.addOutput(output)
        let receiver = PhotoReceiver()
        // Not running yet: the capture fails.
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: receiver)
        #expect(receiver.steps == ["willBegin", "processed", "finished"] && receiver.error != nil)

        session.startRunning()
        StandInCamera.goLive()
        let done = PhotoReceiver()
        output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: done)
        #expect(done.steps == ["willBegin", "didCapture", "processed", "finished"])
        #expect(done.error == nil)
        let photo = try #require(done.photos.first)
        #expect(photo.fileDataRepresentation() == Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(photo.resolvedSettings.photoDimensions == CMVideoDimensions(width: 2, height: 1))
        // The pixels as BGRA.
        #expect(photo.pixelBuffer?.bytes == [30, 20, 10, 255, 60, 50, 40, 255])
        session.stopRunning()
        StandInCamera.uninstall()
    }

    @Test func torchZoomAndFocusGoToTheStream() throws {
        StandInCamera.install()
        let session = try makeSession()
        session.startRunning()
        StandInCamera.goLive()
        let device = try #require(AVCaptureDevice.default(for: .video))
        let stream = try #require(StandInCamera.stream)
        #expect(device.hasTorch && device.maxAvailableVideoZoomFactor == 4)
        try device.lockForConfiguration()
        device.torchMode = .on
        device.videoZoomFactor = 2
        device.focusPointOfInterest = CGPoint(x: 0.25, y: 0.75)
        device.unlockForConfiguration()
        #expect(stream.torch && device.isTorchActive)
        #expect(stream.zoom == 2)
        #expect(stream.point.map { $0 == (0.25, 0.75) } == true)
        device.torchMode = .off
        #expect(!stream.torch && !device.isTorchActive)
        session.stopRunning()
        StandInCamera.uninstall()
    }

    @Test func aMovieIsWrittenToTheFile() throws {
        StandInCamera.install()
        let session = try makeSession()
        let output = AVCaptureMovieFileOutput()
        session.addOutput(output)
        session.startRunning()
        StandInCamera.goLive()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).mov")
        let receiver = MovieReceiver()
        output.startRecording(to: url, recordingDelegate: receiver)
        #expect(output.isRecording && StandInCamera.stream?.recording == true && receiver.started == url)
        output.stopRecording()
        #expect(!output.isRecording && receiver.finished == url && receiver.error == nil)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        try? FileManager.default.removeItem(at: url)
        session.stopRunning()
        StandInCamera.uninstall()
    }

    @Test func stoppingTheSessionMidRecordingStillWritesTheMovie() throws {
        StandInCamera.install()
        let session = try makeSession()
        let output = AVCaptureMovieFileOutput()
        session.addOutput(output)
        session.startRunning()
        StandInCamera.goLive()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).mov")
        let receiver = MovieReceiver()
        output.startRecording(to: url, recordingDelegate: receiver)
        session.stopRunning()
        #expect(!output.isRecording && receiver.finished == url)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        try? FileManager.default.removeItem(at: url)
        StandInCamera.uninstall()
    }

    @Test(arguments: [false, true])
    func aPreviewInARepresentableIsAHostElement(asSublayer: Bool) throws {
        StandInCamera.install()
        let session = try makeSession()
        let runtime = Runtime()
        runtime.mount(VStack(spacing: 0) {
            Color.red.frame(height: 40)
            CameraPreview(session: session, asSublayer: asSublayer).frame(height: 200)
        })
        runtime.layout(in: CGSize(width: 320, height: 240))
        _ = runtime.render(scale: 2)
        let elements = runtime.hostElements()
        #expect(elements.count == 1)
        let gravity = asSublayer ? "AVLayerVideoGravityResizeAspectFill" : "AVLayerVideoGravityResizeAspect"
        #expect(elements.first?.kind == .camera(session: session._identifier, live: false, mirrored: false, gravity: gravity))
        #expect(elements.first?.frame == CGRect(x: 0, y: 40, width: 320, height: 200), "\(String(describing: elements.first?.frame))")
        session.startRunning()
        StandInCamera.goLive()
        runtime.layout(in: CGSize(width: 320, height: 240))
        _ = runtime.render(scale: 2)
        #expect(runtime.hostElements().first?.kind == .camera(session: session._identifier, live: true, mirrored: false, gravity: gravity))
        session.stopRunning()
        StandInCamera.uninstall()
    }
}
#endif
