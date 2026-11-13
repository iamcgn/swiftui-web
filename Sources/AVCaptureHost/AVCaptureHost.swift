// The browser's camera as AVFoundation's capture session uses it: the hook SwiftUIWebCanvas
// installs (CaptureHost.swift) and AVFoundation's AVCapture.swift uses. A module of its own,
// depending on nothing, so installing the hook links only this into an app that never opens a
// camera (decision 0006).

public enum _AVCaptureHost {
    /// Which camera the browser should pick.
    public enum Facing: String, Sendable { case user, environment, any = "" }

    /// The video inputs the browser has: -1 while it hasn't said (there may be one), 0 when it has none.
    nonisolated(unsafe) public static var cameraCount = 0
    /// The audio inputs, likewise.
    nonisolated(unsafe) public static var microphoneCount = 0
    /// The permissions as the browser last reported them, as `AVAuthorizationStatus` raw values
    /// (0 not asked, 2 denied, 3 granted).
    nonisolated(unsafe) public static var videoAuthorization = 0
    nonisolated(unsafe) public static var audioAuthorization = 0
    /// The code formats the host can read (the `BarcodeDetector` names: "qr_code", "ean_13"…).
    nonisolated(unsafe) public static var codeFormats: [String] = []
    /// Asks for the camera (`video`) or the microphone; the answer arrives on the main actor.
    nonisolated(unsafe) public static var requestAccess: ((_ video: Bool, _ completion: @escaping @MainActor (Bool) -> Void) -> Void)?
    /// Opens a camera as stream `session` (where the host's preview elements find it), at about
    /// `width` pixels across, with the microphone when `audio`. `started` comes later, never from
    /// within the call: the stream's size and abilities, or nil when the camera was refused or
    /// is missing.
    nonisolated(unsafe) public static var open: ((_ session: Int, _ facing: Facing, _ width: Int, _ audio: Bool,
                                                  _ started: @escaping @MainActor (_AVCaptureStarted?) -> Void) -> (any _AVCaptureStream)?)?
}

/// A stream that went live: its picture's size and what its camera can do.
public struct _AVCaptureStarted: Sendable {
    public var width: Int
    public var height: Int
    public var hasTorch: Bool
    public var maxZoom: Double
    public init(width: Int, height: Int, hasTorch: Bool = false, maxZoom: Double = 1) {
        self.width = width
        self.height = height
        self.hasTorch = hasTorch
        self.maxZoom = maxZoom
    }
}

/// A code the host read: its format's `BarcodeDetector` name, its text and its corners in the
/// picture, as x, y pairs from 0 to 1 from the top left.
public struct _AVCaptureCode: Sendable, Equatable {
    public var format: String
    public var value: String
    public var corners: [Double]
    public init(format: String, value: String, corners: [Double]) {
        self.format = format
        self.value = value
        self.corners = corners
    }
}

/// An open camera in the host.
public protocol _AVCaptureStream: AnyObject {
    func stop()
    /// Frames as BGRA bytes, at most `fps` a second and `maxWidth` pixels across, with the time
    /// in seconds; nil stops them.
    func deliverFrames(maxWidth: Int, fps: Double, _ deliver: (@MainActor (_ width: Int, _ height: Int, _ bgra: [UInt8], _ time: Double) -> Void)?)
    /// A still at the stream's size: JPEG bytes and the RGBA pixels (both empty when it failed).
    func takePhoto(_ completion: @escaping @MainActor (_ jpeg: [UInt8], _ width: Int, _ height: Int, _ rgba: [UInt8]) -> Void)
    /// Reads the formats' codes from the picture a few times a second; nil stops.
    func detectCodes(formats: [String], _ deliver: (@MainActor ([_AVCaptureCode]) -> Void)?)
    func setTorch(_ on: Bool, level: Double)
    func setZoom(_ factor: Double)
    /// Where to focus and meter, 0 to 1 from the top left; nil for the whole picture.
    func setPointOfInterest(x: Double, y: Double)
    func startRecording()
    /// The recording's bytes and its MIME type (empty when nothing was recorded).
    func stopRecording(_ completion: @escaping @MainActor (_ data: [UInt8], _ mimeType: String) -> Void)
}
