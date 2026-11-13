// The camera for the web: `AVCaptureSession` over the browser's `getUserMedia` (through
// `_AVCaptureHost`, which SwiftUIWebCanvas installs, CaptureHost.swift). The preview layer is
// the host's `<video>` element showing the session's stream where the layer is; a video data
// output gets the stream's frames as BGRA pixel buffers, a photo output a still as JPEG data, a
// metadata output the codes the browser's `BarcodeDetector` reads, a movie file output what
// `MediaRecorder` records. The browser picks the camera by the facing the device asks for (the
// back camera is "environment", the front "user"), so on a computer with one webcam both are
// that webcam. Point coordinates are the upright picture's, from its top left (0, 0) to its
// bottom right (1, 1). Without a host there is no camera: no device, no permission.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
#if canImport(CoreGraphics) && !os(WASI)
import CoreGraphics
#endif
import UIKitWebCore
import AVCaptureHost

// MARK: - Media types, permission, errors

/// A kind of media.
public struct AVMediaType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let video = AVMediaType("vide")
    public static let audio = AVMediaType("soun")
    public static let text = AVMediaType("text")
    public static let closedCaption = AVMediaType("clcp")
    public static let subtitle = AVMediaType("sbtl")
    public static let timecode = AVMediaType("tmcd")
    public static let metadata = AVMediaType("meta")
    public static let muxed = AVMediaType("muxx")
    public static let depthData = AVMediaType("dpth")
}

/// Whether the app may use a capture device.
public enum AVAuthorizationStatus: Int, Sendable {
    case notDetermined = 0, restricted, denied, authorized
}

/// How a video fills the bounds of the layer or view that shows it.
public struct AVLayerVideoGravity: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let resizeAspect = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspect")
    public static let resizeAspectFill = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspectFill")
    public static let resize = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResize")
}

/// A file format.
public struct AVFileType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let mov = AVFileType("com.apple.quicktime-movie")
    public static let mp4 = AVFileType("public.mpeg-4")
    public static let m4v = AVFileType("com.apple.m4v-video")
    public static let m4a = AVFileType("com.apple.m4a-audio")
    public static let jpg = AVFileType("public.jpeg")
    public static let heic = AVFileType("public.heic")
    public static let heif = AVFileType("public.heif")
    public static let dng = AVFileType("com.adobe.raw-image")
    public static let tif = AVFileType("public.tiff")
    public static let wav = AVFileType("com.microsoft.waveform-audio")
    public static let caf = AVFileType("com.apple.coreaudio-format")
    public static let mp3 = AVFileType("public.mp3")
}

/// A video codec.
public struct AVVideoCodecType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let h264 = AVVideoCodecType("avc1")
    public static let hevc = AVVideoCodecType("hvc1")
    public static let hevcWithAlpha = AVVideoCodecType("muxa")
    public static let jpeg = AVVideoCodecType("jpeg")
    public static let proRes422 = AVVideoCodecType("apcn")
    public static let proRes4444 = AVVideoCodecType("ap4h")
}

public let AVVideoCodecKey = "AVVideoCodecKey"
public let AVVideoWidthKey = "AVVideoWidthKey"
public let AVVideoHeightKey = "AVVideoHeightKey"
public let AVVideoCompressionPropertiesKey = "AVVideoCompressionPropertiesKey"
public let AVVideoQualityKey = "AVVideoQualityKey"
public let AVVideoAverageBitRateKey = "AverageBitRate"
public let AVVideoScalingModeKey = "AVVideoScalingModeKey"

/// An AVFoundation error: its code, and what more it says.
public struct AVError: Error, CustomStringConvertible, @unchecked Sendable {
    public enum Code: Int, Sendable {
        case unknown = -11800
        case outOfMemory = -11801
        case sessionNotRunning = -11803
        case deviceAlreadyUsedByAnotherSession = -11804
        case noDataCaptured = -11805
        case sessionConfigurationChanged = -11806
        case diskFull = -11807
        case deviceWasDisconnected = -11808
        case mediaChanged = -11809
        case maximumDurationReached = -11810
        case maximumFileSizeReached = -11811
        case mediaDiscontinuity = -11812
        case maximumNumberOfSamplesForFileFormatReached = -11813
        case deviceNotConnected = -11814
        case deviceInUseByAnotherApplication = -11815
        case deviceLockedForConfigurationByAnotherProcess = -11817
        case sessionWasInterrupted = -11818
        case mediaServicesWereReset = -11819
        case operationNotSupportedForAsset = -11838
        case applicationIsNotAuthorizedToUseDevice = -11852
        case operationInterrupted = -11867
    }
    public let code: Code
    public let userInfo: [String: Any]
    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        self.userInfo = userInfo
    }
    public static var errorDomain: String { "AVFoundationErrorDomain" }
    public var errorCode: Int { code.rawValue }
    public var localizedDescription: String { description }
    public var description: String {
        switch code {
        case .applicationIsNotAuthorizedToUseDevice: return "The camera was not allowed."
        case .deviceNotConnected: return "There is no camera."
        case .sessionNotRunning: return "The capture session is not running."
        default: return "The operation could not be completed (\(Self.errorDomain) error \(code.rawValue).)"
        }
    }
    public static var unknown: Code { .unknown }
    public static var sessionNotRunning: Code { .sessionNotRunning }
    public static var deviceNotConnected: Code { .deviceNotConnected }
    public static var mediaServicesWereReset: Code { .mediaServicesWereReset }
    public static var applicationIsNotAuthorizedToUseDevice: Code { .applicationIsNotAuthorizedToUseDevice }
    public static var noDataCaptured: Code { .noDataCaptured }
}

public let AVErrorDeviceKey = "AVErrorDeviceKey"
public let AVErrorTimeKey = "AVErrorTimeKey"
public let AVErrorRecordingSuccessfullyFinishedKey = "AVErrorRecordingSuccessfullyFinishedKey"

// MARK: - Notifications

public let AVCaptureSessionErrorKey = "AVCaptureSessionErrorKey"
public let AVCaptureSessionInterruptionReasonKey = "AVCaptureSessionInterruptionReasonKey"
public let AVCaptureSessionInterruptionSystemPressureStateKey = "AVCaptureSessionInterruptionSystemPressureStateKey"

extension Notification.Name {
    public static let AVCaptureSessionRuntimeError = Notification.Name("AVCaptureSessionRuntimeErrorNotification")
    public static let AVCaptureSessionDidStartRunning = Notification.Name("AVCaptureSessionDidStartRunningNotification")
    public static let AVCaptureSessionDidStopRunning = Notification.Name("AVCaptureSessionDidStopRunningNotification")
    public static let AVCaptureSessionWasInterrupted = Notification.Name("AVCaptureSessionWasInterruptedNotification")
    public static let AVCaptureSessionInterruptionEnded = Notification.Name("AVCaptureSessionInterruptionEndedNotification")
    public static let AVCaptureDeviceWasConnected = Notification.Name("AVCaptureDeviceWasConnectedNotification")
    public static let AVCaptureDeviceWasDisconnected = Notification.Name("AVCaptureDeviceWasDisconnectedNotification")
    public static let AVCaptureDeviceSubjectAreaDidChange = Notification.Name("AVCaptureDeviceSubjectAreaDidChangeNotification")
    public static let AVCaptureInputPortFormatDescriptionDidChange = Notification.Name("AVCaptureInputPortFormatDescriptionDidChangeNotification")
}

/// Reports a change of `keyPath` to the object's key-value observers on wasm (WebFoundation's
/// key-value observing). Apple's needs `@objc` properties, which these are not, and Linux's
/// Foundation has none.
private func _reportChange<Object: NSObject, Value>(_ object: Object, _ keyPath: KeyPath<Object, Value>, _ change: () -> Void) {
    #if os(WASI)
    object.willChangeValue(for: keyPath)
    change()
    object.didChangeValue(for: keyPath)
    #else
    change()
    #endif
}

/// Whether a delegate queue is the main queue, where a delegate is called at once (the host's
/// callbacks are on the main thread). Linux's `DispatchQueue.main` is a new object each time.
private func _isMainQueue(_ queue: DispatchQueue) -> Bool {
    queue === DispatchQueue.main || queue.label == DispatchQueue.main.label
}

/// Runs on the main actor, after what is running now.
private func _onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
    Task { @MainActor in work() }
}

// MARK: - AVCaptureDevice

/// A camera or microphone.
open class AVCaptureDevice: NSObject, @unchecked Sendable {
    public struct DeviceType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let builtInWideAngleCamera = DeviceType("AVCaptureDeviceTypeBuiltInWideAngleCamera")
        public static let builtInUltraWideCamera = DeviceType("AVCaptureDeviceTypeBuiltInUltraWideCamera")
        public static let builtInTelephotoCamera = DeviceType("AVCaptureDeviceTypeBuiltInTelephotoCamera")
        public static let builtInDualCamera = DeviceType("AVCaptureDeviceTypeBuiltInDualCamera")
        public static let builtInDualWideCamera = DeviceType("AVCaptureDeviceTypeBuiltInDualWideCamera")
        public static let builtInTripleCamera = DeviceType("AVCaptureDeviceTypeBuiltInTripleCamera")
        public static let builtInTrueDepthCamera = DeviceType("AVCaptureDeviceTypeBuiltInTrueDepthCamera")
        public static let builtInLiDARDepthCamera = DeviceType("AVCaptureDeviceTypeBuiltInLiDARDepthCamera")
        public static let builtInMicrophone = DeviceType("AVCaptureDeviceTypeBuiltInMicrophone")
        public static let microphone = DeviceType("AVCaptureDeviceTypeMicrophone")
        public static let external = DeviceType("AVCaptureDeviceTypeExternal")
        public static let continuityCamera = DeviceType("AVCaptureDeviceTypeContinuityCamera")
        public static let deskViewCamera = DeviceType("AVCaptureDeviceTypeDeskViewCamera")
    }

    public enum Position: Int, Sendable { case unspecified = 0, back, front }
    public enum FlashMode: Int, Sendable { case off = 0, on, auto }
    public enum TorchMode: Int, Sendable { case off = 0, on, auto }
    public enum FocusMode: Int, Sendable { case locked = 0, autoFocus, continuousAutoFocus }
    public enum ExposureMode: Int, Sendable { case locked = 0, autoExpose, continuousAutoExposure, custom }
    public enum WhiteBalanceMode: Int, Sendable { case locked = 0, autoWhiteBalance, continuousAutoWhiteBalance }
    public enum AutoFocusRangeRestriction: Int, Sendable { case none = 0, near, far }
    public enum AutoFocusSystem: Int, Sendable { case none = 0, contrastDetection, phaseDetection }

    /// How hard the device is working (always nominal here).
    open class SystemPressureState: NSObject, @unchecked Sendable {
        public struct Level: RawRepresentable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }
            public static let nominal = Level(rawValue: "AVCaptureSystemPressureLevelNominal")
            public static let fair = Level(rawValue: "AVCaptureSystemPressureLevelFair")
            public static let serious = Level(rawValue: "AVCaptureSystemPressureLevelSerious")
            public static let critical = Level(rawValue: "AVCaptureSystemPressureLevelCritical")
            public static let shutdown = Level(rawValue: "AVCaptureSystemPressureLevelShutdown")
        }
        public struct Factors: OptionSet, Sendable {
            public let rawValue: UInt
            public init(rawValue: UInt) { self.rawValue = rawValue }
            public static let systemTemperature = Factors(rawValue: 1 << 0)
            public static let peakPower = Factors(rawValue: 1 << 1)
            public static let depthModuleTemperature = Factors(rawValue: 1 << 2)
            public static let cameraTemperature = Factors(rawValue: 1 << 3)
        }
        open var level: Level { .nominal }
        open var factors: Factors { [] }
    }

    /// One of the device's formats (the stream's).
    open class Format: NSObject, @unchecked Sendable {
        var dimensions: CMVideoDimensions
        var maxZoom: Double
        init(dimensions: CMVideoDimensions, maxZoom: Double) {
            self.dimensions = dimensions
            self.maxZoom = maxZoom
        }
        open var videoMaxZoomFactor: CGFloat { CGFloat(maxZoom) }
        open var videoZoomFactorUpscaleThreshold: CGFloat { 1 }
        open var videoFieldOfView: Float { 60 }
        open var isVideoHDRSupported: Bool { false }
        open var isVideoBinned: Bool { false }
        open var minISO: Float { 50 }
        open var maxISO: Float { 1600 }
        open var minExposureDuration: CMTime { CMTime(value: 1, timescale: 8000) }
        open var maxExposureDuration: CMTime { CMTime(value: 1, timescale: 3) }
        open var highResolutionStillImageDimensions: CMVideoDimensions { dimensions }
        open var supportedMaxPhotoDimensions: [CMVideoDimensions] { [dimensions] }
        open var formatDescriptionDimensions: CMVideoDimensions { dimensions }
        open var videoSupportedFrameRateRanges: [AVFrameRateRange] { [AVFrameRateRange()] }
        open var isMultiCamSupported: Bool { false }
        open func isVideoStabilizationModeSupported(_ videoStabilizationMode: AVCaptureVideoStabilizationMode) -> Bool {
            videoStabilizationMode == .off
        }
    }

    /// Finds the devices of the types, for the media and at the position.
    open class DiscoverySession: NSObject, @unchecked Sendable {
        public let deviceTypes: [DeviceType]
        let mediaType: AVMediaType?
        let position: Position
        public init(deviceTypes: [DeviceType], mediaType: AVMediaType?, position: Position) {
            self.deviceTypes = deviceTypes
            self.mediaType = mediaType
            self.position = position
        }
        open var devices: [AVCaptureDevice] {
            AVCaptureDevice._all.filter { device in
                deviceTypes.contains(device.deviceType) && (mediaType.map(device.hasMediaType) ?? true)
                    && (position == .unspecified || device.position == position)
            }
        }
        open var supportedMultiCamDeviceSets: [Set<AVCaptureDevice>] { [] }
    }

    public let uniqueID: String
    public let localizedName: String
    public let modelID: String
    public let deviceType: DeviceType
    public let position: Position
    let mediaType: AVMediaType
    let facing: _AVCaptureHost.Facing

    init(uniqueID: String, localizedName: String, deviceType: DeviceType, position: Position, mediaType: AVMediaType) {
        self.uniqueID = uniqueID
        self.localizedName = localizedName
        modelID = "Web Camera"
        self.deviceType = deviceType
        self.position = position
        self.mediaType = mediaType
        facing = position == .front ? .user : position == .back ? .environment : .any
    }

    // The devices: the back and front cameras the browser picks by facing, and the microphone.
    static let back = AVCaptureDevice(uniqueID: "com.apple.avfoundation.avcapturedevice.built-in_video:0",
                                                          localizedName: "Back Camera", deviceType: .builtInWideAngleCamera,
                                                          position: .back, mediaType: .video)
    static let front = AVCaptureDevice(uniqueID: "com.apple.avfoundation.avcapturedevice.built-in_video:1",
                                                           localizedName: "Front Camera", deviceType: .builtInWideAngleCamera,
                                                           position: .front, mediaType: .video)
    static let microphone = AVCaptureDevice(uniqueID: "com.apple.avfoundation.avcapturedevice.built-in_audio:0",
                                                                localizedName: "Microphone", deviceType: .microphone,
                                                                position: .unspecified, mediaType: .audio)

    /// What the browser has: two cameras when it reports two or more (or hasn't said yet), one
    /// (the back) when it reports one; the microphone when it reports one.
    static var _all: [AVCaptureDevice] {
        var devices: [AVCaptureDevice] = []
        let cameras = _AVCaptureHost.cameraCount
        if cameras != 0 { devices.append(back) }
        if cameras >= 2 || cameras < 0 { devices.append(front) }
        if _AVCaptureHost.microphoneCount != 0 { devices.append(microphone) }
        return devices
    }

    // MARK: Finding devices

    /// The default device for the media: the back camera, the microphone.
    open class func `default`(for mediaType: AVMediaType) -> AVCaptureDevice? {
        switch mediaType {
        case .video: return _AVCaptureHost.cameraCount != 0 ? back : nil
        case .audio: return _AVCaptureHost.microphoneCount != 0 ? microphone : nil
        default: return nil
        }
    }

    /// The device of the type at the position. The browser chooses among its cameras by facing,
    /// so a front or back camera is there whenever any camera is (on a computer, its webcam).
    open class func `default`(_ deviceType: DeviceType, for mediaType: AVMediaType?, position: Position) -> AVCaptureDevice? {
        if mediaType == .audio || deviceType == .builtInMicrophone || deviceType == .microphone {
            return deviceType == .builtInMicrophone || deviceType == .microphone ? `default`(for: .audio) : nil
        }
        guard _AVCaptureHost.cameraCount != 0, deviceType == .builtInWideAngleCamera else { return nil }
        return position == .front ? front : back
    }

    open class func devices() -> [AVCaptureDevice] { _all }
    open class func devices(for mediaType: AVMediaType) -> [AVCaptureDevice] { _all.filter { $0.mediaType == mediaType } }
    public convenience init?(uniqueID deviceUniqueID: String) { nil }
    open class func device(withUniqueID uniqueID: String) -> AVCaptureDevice? { _all.first { $0.uniqueID == uniqueID } }

    // MARK: Permission

    open class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVAuthorizationStatus(rawValue: mediaType == .audio ? _AVCaptureHost.audioAuthorization : _AVCaptureHost.videoAuthorization) ?? .notDetermined
    }

    /// Asks for the camera or microphone; the browser asks the person the first time.
    open class func requestAccess(for mediaType: AVMediaType, completionHandler handler: @escaping @Sendable (Bool) -> Void) {
        let video = mediaType != .audio
        if authorizationStatus(for: mediaType) == .authorized { handler(true); return }
        guard let request = _AVCaptureHost.requestAccess else {
            if video { _AVCaptureHost.videoAuthorization = AVAuthorizationStatus.denied.rawValue } else { _AVCaptureHost.audioAuthorization = AVAuthorizationStatus.denied.rawValue }
            handler(false)
            return
        }
        request(video) { granted in
            let status: AVAuthorizationStatus = granted ? .authorized : .denied
            if video { _AVCaptureHost.videoAuthorization = status.rawValue } else { _AVCaptureHost.audioAuthorization = status.rawValue }
            handler(granted)
        }
    }

    open class func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            requestAccess(for: mediaType) { continuation.resume(returning: $0) }
        }
    }

    // MARK: State

    var stream: (any _AVCaptureStream)?
    var started: _AVCaptureStarted?
    private var locked = false

    open var isConnected: Bool { true }
    open var isSuspended: Bool { false }
    open func hasMediaType(_ mediaType: AVMediaType) -> Bool { self.mediaType == mediaType }
    open var manufacturer: String { "Web" }

    open var formats: [Format] { [activeFormat] }
    open var activeFormat: Format {
        get {
            let size = started.map { CMVideoDimensions(width: Int32($0.width), height: Int32($0.height)) } ?? CMVideoDimensions(width: 1280, height: 720)
            return Format(dimensions: size, maxZoom: started?.maxZoom ?? 1)
        }
        set {}
    }
    open var activeVideoMinFrameDuration = CMTime.invalid
    open var activeVideoMaxFrameDuration = CMTime.invalid
    open var systemPressureState: SystemPressureState { SystemPressureState() }

    open func lockForConfiguration() throws { locked = true }
    open func unlockForConfiguration() { locked = false }

    // Flash and torch: the stream's torch where its camera has one (a phone's back camera in Chrome).
    open var hasFlash: Bool { false }
    open var isFlashAvailable: Bool { false }
    open func isFlashModeSupported(_ flashMode: FlashMode) -> Bool { flashMode == .off }
    open var flashMode: FlashMode = .off
    open var hasTorch: Bool { started?.hasTorch ?? false }
    open var isTorchAvailable: Bool { hasTorch }
    open func isTorchModeSupported(_ torchMode: TorchMode) -> Bool { torchMode == .off || (hasTorch && torchMode == .on) }
    open private(set) var torchLevel: Float = 0
    open private(set) var isTorchActive = false
    open var torchMode: TorchMode = .off {
        didSet { applyTorch(torchMode == .on ? 1 : 0) }
    }
    public static let maxAvailableTorchLevel: Float = 1
    open func setTorchModeOn(level torchLevel: Float) throws {
        torchMode = .on
        applyTorch(Double(torchLevel))
    }
    private func applyTorch(_ level: Double) {
        let on = level > 0 && hasTorch
        stream?.setTorch(on, level: level)
        torchLevel = on ? Float(level) : 0
        if on != isTorchActive { _reportChange(self, \.isTorchActive) { isTorchActive = on } }
    }

    // Focus and exposure: the point of interest goes to the stream (where the browser can aim).
    open func isFocusModeSupported(_ focusMode: FocusMode) -> Bool { focusMode == .continuousAutoFocus || focusMode == .autoFocus }
    open var focusMode: FocusMode = .continuousAutoFocus
    open var isFocusPointOfInterestSupported: Bool { stream != nil }
    open var focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) {
        didSet { stream?.setPointOfInterest(x: Double(focusPointOfInterest.x), y: Double(focusPointOfInterest.y)) }
    }
    open var isAdjustingFocus: Bool { false }
    open var autoFocusRangeRestriction: AutoFocusRangeRestriction = .none
    open var isAutoFocusRangeRestrictionSupported: Bool { false }
    open var isSmoothAutoFocusSupported: Bool { false }
    open var isSmoothAutoFocusEnabled = false
    open var lensPosition: Float { 0.5 }
    public static let currentLensPosition: Float = -1
    open func setFocusModeLocked(lensPosition: Float, completionHandler handler: (@Sendable (CMTime) -> Void)? = nil) {
        focusMode = .locked
        handler?(.invalid)
    }
    open var activePrimaryConstituentDevice: AVCaptureDevice? { nil }

    open func isExposureModeSupported(_ exposureMode: ExposureMode) -> Bool { exposureMode == .continuousAutoExposure || exposureMode == .autoExpose }
    open var exposureMode: ExposureMode = .continuousAutoExposure
    open var isExposurePointOfInterestSupported: Bool { stream != nil }
    open var exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) {
        didSet { stream?.setPointOfInterest(x: Double(exposurePointOfInterest.x), y: Double(exposurePointOfInterest.y)) }
    }
    open var isAdjustingExposure: Bool { false }
    open var exposureDuration: CMTime { CMTime(value: 1, timescale: 60) }
    open var iso: Float { 100 }
    open var exposureTargetBias: Float = 0
    open var minExposureTargetBias: Float { -8 }
    open var maxExposureTargetBias: Float { 8 }
    open var exposureTargetOffset: Float { 0 }
    public static let currentExposureDuration = CMTime.invalid
    public static let currentISO: Float = 0
    open func setExposureTargetBias(_ bias: Float, completionHandler handler: (@Sendable (CMTime) -> Void)? = nil) {
        exposureTargetBias = bias
        handler?(.invalid)
    }
    open func setExposureModeCustom(duration: CMTime, iso ISO: Float, completionHandler handler: (@Sendable (CMTime) -> Void)? = nil) {
        exposureMode = .custom
        handler?(.invalid)
    }

    open func isWhiteBalanceModeSupported(_ whiteBalanceMode: WhiteBalanceMode) -> Bool { whiteBalanceMode == .continuousAutoWhiteBalance }
    open var whiteBalanceMode: WhiteBalanceMode = .continuousAutoWhiteBalance
    open var isAdjustingWhiteBalance: Bool { false }

    open var isSubjectAreaChangeMonitoringEnabled = false
    open var isLowLightBoostSupported: Bool { false }
    open var isLowLightBoostEnabled: Bool { false }
    open var automaticallyEnablesLowLightBoostWhenAvailable = false
    open var isVideoHDREnabled = false
    open var automaticallyAdjustsVideoHDREnabled = true
    open var isGeometricDistortionCorrectionSupported: Bool { false }
    open var isGeometricDistortionCorrectionEnabled = false
    open var isCenterStageActive: Bool { false }

    // Zoom: the stream's zoom where the camera has one.
    open var minAvailableVideoZoomFactor: CGFloat { 1 }
    open var maxAvailableVideoZoomFactor: CGFloat { CGFloat(started?.maxZoom ?? 1) }
    open var videoZoomFactor: CGFloat = 1 {
        didSet {
            let clamped = min(max(videoZoomFactor, 1), max(maxAvailableVideoZoomFactor, 1))
            if clamped != videoZoomFactor { videoZoomFactor = clamped }
            stream?.setZoom(Double(videoZoomFactor))
        }
    }
    open var isRampingVideoZoom: Bool { false }
    open func ramp(toVideoZoomFactor factor: CGFloat, withRate rate: Float) { videoZoomFactor = factor }
    open func cancelVideoZoomRamp() {}
    open var virtualDeviceSwitchOverVideoZoomFactors: [NSNumber] { [] }
    open var constituentDevices: [AVCaptureDevice] { [] }
    open var isVirtualDevice: Bool { false }

    /// The session's stream went live on this device, or stopped.
    func attach(_ stream: (any _AVCaptureStream)?, _ started: _AVCaptureStarted?) {
        self.stream = stream
        self.started = started
        if stream != nil {
            if torchMode == .on { applyTorch(Double(max(torchLevel, 1))) }
            if videoZoomFactor != 1 { stream?.setZoom(Double(videoZoomFactor)) }
        } else if isTorchActive {
            _reportChange(self, \.isTorchActive) { isTorchActive = false }
        }
    }
}

/// A range of frame rates a format supports.
open class AVFrameRateRange: NSObject, @unchecked Sendable {
    override init() {}
    open var minFrameRate: Float64 { 1 }
    open var maxFrameRate: Float64 { 30 }
    open var minFrameDuration: CMTime { CMTime(value: 1, timescale: 30) }
    open var maxFrameDuration: CMTime { CMTime(value: 1, timescale: 1) }
}

public enum AVCaptureVideoStabilizationMode: Int, Sendable {
    case off = 0, standard, cinematic, cinematicExtended, previewOptimized, cinematicExtendedEnhanced
    case auto = -1
}

public enum AVCaptureVideoOrientation: Int, Sendable {
    case portrait = 1, portraitUpsideDown, landscapeRight, landscapeLeft
}

// MARK: - Inputs

/// What feeds a session.
open class AVCaptureInput: NSObject, @unchecked Sendable {
    override init() {}
}

/// A device as a session's input.
open class AVCaptureDeviceInput: AVCaptureInput, @unchecked Sendable {
    public let device: AVCaptureDevice
    public init(device: AVCaptureDevice) throws {
        self.device = device
        super.init()
    }
    open class func deviceInput(with device: AVCaptureDevice) throws -> AVCaptureDeviceInput { try AVCaptureDeviceInput(device: device) }
    open var unifiedAutoExposureDefaultsEnabled = false
    open var videoMinFrameDurationOverride = CMTime.invalid
}

// MARK: - Connections

/// A path from the session's input to an output or the preview layer.
open class AVCaptureConnection: NSObject, @unchecked Sendable {
    weak var session: AVCaptureSession?
    public private(set) weak var output: AVCaptureOutput?

    init(session: AVCaptureSession?, output: AVCaptureOutput?) {
        self.session = session
        self.output = output
    }

    open var isEnabled = true
    open var isActive: Bool { session?.videoDevice != nil }
    open var videoOrientation: AVCaptureVideoOrientation = .portrait
    open var isVideoOrientationSupported: Bool { true }
    open var videoRotationAngle: CGFloat = 90
    open func isVideoRotationAngleSupported(_ videoRotationAngle: CGFloat) -> Bool { true }
    open var isVideoMirroringSupported: Bool { true }
    /// On by itself for the front camera, as Apple's.
    open var automaticallyAdjustsVideoMirroring = true
    private var mirrored = false
    open var isVideoMirrored: Bool {
        get { automaticallyAdjustsVideoMirroring ? session?.videoDevice?.position == .front : mirrored }
        set { mirrored = newValue }
    }
    open var isVideoStabilizationSupported: Bool { false }
    open var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off
    open var activeVideoStabilizationMode: AVCaptureVideoStabilizationMode { .off }
    open var isCameraIntrinsicMatrixDeliverySupported: Bool { false }
    open var isCameraIntrinsicMatrixDeliveryEnabled = false
    open var videoMaxScaleAndCropFactor: CGFloat { 1 }
    open var videoScaleAndCropFactor: CGFloat = 1
    open var inputPorts: [AnyObject] { [] }
}

// MARK: - The session

/// Runs the flow from the camera to its outputs.
open class AVCaptureSession: NSObject, @unchecked Sendable {
    public struct Preset: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let photo = Preset("AVCaptureSessionPresetPhoto")
        public static let high = Preset("AVCaptureSessionPresetHigh")
        public static let medium = Preset("AVCaptureSessionPresetMedium")
        public static let low = Preset("AVCaptureSessionPresetLow")
        public static let cif352x288 = Preset("AVCaptureSessionPreset352x288")
        public static let vga640x480 = Preset("AVCaptureSessionPreset640x480")
        public static let hd1280x720 = Preset("AVCaptureSessionPreset1280x720")
        public static let hd1920x1080 = Preset("AVCaptureSessionPreset1920x1080")
        public static let hd4K3840x2160 = Preset("AVCaptureSessionPreset3840x2160")
        public static let iFrame960x540 = Preset("AVCaptureSessionPresetiFrame960x540")
        public static let iFrame1280x720 = Preset("AVCaptureSessionPresetiFrame1280x720")
        public static let inputPriority = Preset("AVCaptureSessionPresetInputPriority")

        /// The width to ask the browser for.
        var width: Int {
            switch self {
            case .low, .cif352x288: return 352
            case .medium, .vga640x480: return 640
            case .iFrame960x540: return 960
            case .hd1280x720, .iFrame1280x720: return 1280
            case .hd4K3840x2160: return 3840
            default: return 1920
            }
        }
    }

    public enum InterruptionReason: Int, Sendable {
        case videoDeviceNotAvailableInBackground = 1
        case audioDeviceInUseByAnotherClient
        case videoDeviceInUseByAnotherClient
        case videoDeviceNotAvailableWithMultipleForegroundApps
        case videoDeviceNotAvailableDueToSystemPressure
    }

    nonisolated(unsafe) private static var counter = 0
    /// The stream's name in the host.
    public let _identifier: Int

    public override init() {
        Self.counter += 1
        _identifier = Self.counter
        super.init()
    }

    open var sessionPreset: Preset = .high
    open func canSetSessionPreset(_ preset: Preset) -> Bool { true }
    open private(set) var inputs: [AVCaptureInput] = []
    open private(set) var outputs: [AVCaptureOutput] = []
    open private(set) var isRunning = false
    open private(set) var isInterrupted = false
    open var automaticallyConfiguresApplicationAudioSession = true
    open var usesApplicationAudioSession = true
    open var automaticallyConfiguresCaptureDeviceForWideColor = true
    open var isMultitaskingCameraAccessSupported: Bool { false }
    open var isMultitaskingCameraAccessEnabled = false
    open var connections: [AVCaptureConnection] { outputs.map { $0.connection } }
    open var hardwareCost: Float { 0 }

    var videoDevice: AVCaptureDevice? {
        inputs.lazy.compactMap { ($0 as? AVCaptureDeviceInput)?.device }.first { $0.hasMediaType(.video) }
    }
    private var hasAudioInput: Bool {
        inputs.contains { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }
    }

    // MARK: Configuration

    open func canAddInput(_ input: AVCaptureInput) -> Bool {
        guard !inputs.contains(where: { $0 === input }) else { return false }
        guard let device = (input as? AVCaptureDeviceInput)?.device else { return false }
        // One camera at a time, one microphone.
        return !inputs.contains { ($0 as? AVCaptureDeviceInput)?.device.mediaType == device.mediaType }
    }

    open func addInput(_ input: AVCaptureInput) {
        guard canAddInput(input) else { return }
        inputs.append(input)
        if configuring == 0 { reconfigure() }
    }

    open func removeInput(_ input: AVCaptureInput) {
        inputs.removeAll { $0 === input }
        if configuring == 0 { reconfigure() }
    }

    open func canAddOutput(_ output: AVCaptureOutput) -> Bool {
        !outputs.contains { $0 === output || type(of: $0) == type(of: output) } && output.session == nil
    }

    open func addOutput(_ output: AVCaptureOutput) {
        guard canAddOutput(output) else { return }
        outputs.append(output)
        output.session = self
        output.connection.session = self
        if configuring == 0 { armOutputs() }
    }

    open func removeOutput(_ output: AVCaptureOutput) {
        guard outputs.contains(where: { $0 === output }) else { return }
        outputs.removeAll { $0 === output }
        output.session = nil
        output.connection.session = nil
        if configuring == 0 { armOutputs() }
    }

    open func addInputWithNoConnections(_ input: AVCaptureInput) { addInput(input) }
    open func addOutputWithNoConnections(_ output: AVCaptureOutput) { addOutput(output) }
    open func canAddConnection(_ connection: AVCaptureConnection) -> Bool { false }
    open func addConnection(_ connection: AVCaptureConnection) {}
    open func removeConnection(_ connection: AVCaptureConnection) {}

    private var configuring = 0
    open func beginConfiguration() { configuring += 1 }
    open func commitConfiguration() {
        guard configuring > 0 else { return }
        configuring -= 1
        if configuring == 0 { reconfigure() }
    }

    // MARK: Running

    private var stream: (any _AVCaptureStream)?
    private var streamDevice: AVCaptureDevice?
    /// The stream once it is live.
    private(set) var live: _AVCaptureStarted?
    /// Whether the preview has a picture to show.
    public var _isLive: Bool { live != nil }
    private var previews: [_WeakPreview] = []

    /// Starts the camera. As on iOS the session reads as running at once; the picture follows
    /// when the browser has opened the camera (asking the person the first time), or a runtime
    /// error is posted when it can't.
    open func startRunning() {
        guard !isRunning else { return }
        isRunning = true
        open()
    }

    open func stopRunning() {
        guard isRunning else { return }
        close()
        isRunning = false
        NotificationCenter.default.post(name: .AVCaptureSessionDidStopRunning, object: self)
    }

    private func open() {
        guard let device = videoDevice else {
            // Audio alone: nothing to show.
            NotificationCenter.default.post(name: .AVCaptureSessionDidStartRunning, object: self)
            return
        }
        guard let open = _AVCaptureHost.open, _AVCaptureHost.cameraCount != 0 else {
            fail(.deviceNotConnected)
            return
        }
        streamDevice = device
        let opened = open(_identifier, device.facing, sessionPreset.width, hasAudioInput) { [weak self] started in
            guard let self, self.streamDevice === device else { return }
            guard let started else {
                self.fail(_AVCaptureHost.videoAuthorization == AVAuthorizationStatus.denied.rawValue ? .applicationIsNotAuthorizedToUseDevice : .deviceNotConnected)
                return
            }
            _AVCaptureHost.videoAuthorization = AVAuthorizationStatus.authorized.rawValue
            self.live = started
            if self.stream != nil { self.wentLive() }
        }
        guard let opened else {
            fail(.deviceNotConnected)
            return
        }
        stream = opened
        if live != nil { wentLive() }
    }

    private func wentLive() {
        streamDevice?.attach(stream, live)
        armOutputs()
        refreshPreviews()
        NotificationCenter.default.post(name: .AVCaptureSessionDidStartRunning, object: self)
    }

    private func close() {
        stream?.stop()
        streamDevice?.attach(nil, nil)
        stream = nil
        streamDevice = nil
        live = nil
        refreshPreviews()
    }

    private func fail(_ code: AVError.Code) {
        close()
        isRunning = false
        NotificationCenter.default.post(name: .AVCaptureSessionRuntimeError, object: self,
                                        userInfo: [AVCaptureSessionErrorKey: AVError(code)])
    }

    /// The inputs changed: a running session switches to the new camera.
    private func reconfigure() {
        if isRunning, streamDevice !== videoDevice {
            close()
            open()
        } else {
            armOutputs()
        }
        refreshPreviews()
    }

    /// Hands the stream what the outputs want: frames for a video data output's delegate, codes
    /// for a metadata output's.
    func armOutputs() {
        guard let stream, let live else { return }
        let frameOutputs = outputs.compactMap { $0 as? AVCaptureVideoDataOutput }.filter { $0.sampleBufferDelegate != nil }
        if frameOutputs.isEmpty {
            stream.deliverFrames(maxWidth: 0, fps: 0, nil)
        } else {
            let duration = streamDevice?.activeVideoMinFrameDuration.seconds ?? .nan
            let fps = duration.isFinite && duration > 0 ? min(1 / duration, 30) : 15
            stream.deliverFrames(maxWidth: min(live.width, 1280), fps: fps) { [weak self] width, height, bgra, time in
                guard let self else { return }
                let buffer = CMSampleBuffer(imageBuffer: CVPixelBuffer(width: width, height: height, bytes: bgra),
                                            presentationTimeStamp: CMTime(seconds: time))
                for output in self.outputs.compactMap({ $0 as? AVCaptureVideoDataOutput }) { output.deliver(buffer) }
            }
        }
        let codeOutputs = outputs.compactMap { $0 as? AVCaptureMetadataOutput }.filter { $0.delegate != nil && !$0.metadataObjectTypes.isEmpty }
        let formats = Array(Set(codeOutputs.flatMap { $0.metadataObjectTypes.compactMap(\._detectorFormat) })).sorted()
        if formats.isEmpty {
            stream.detectCodes(formats: [], nil)
        } else {
            stream.detectCodes(formats: formats) { [weak self] codes in
                guard let self else { return }
                for output in self.outputs.compactMap({ $0 as? AVCaptureMetadataOutput }) { output.deliver(codes) }
            }
        }
    }

    var activeStream: (any _AVCaptureStream)? { live != nil ? stream : nil }

    // MARK: Previews

    func addPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previews.removeAll { $0.layer == nil || $0.layer === layer }
        previews.append(_WeakPreview(layer))
    }

    func removePreview(_ layer: AVCaptureVideoPreviewLayer) {
        previews.removeAll { $0.layer == nil || $0.layer === layer }
    }

    /// The previews show what the session now has (on the next frame).
    private func refreshPreviews() {
        let previews = self.previews
        _onMain {
            for preview in previews { preview.layer?.setNeedsDisplay() }
        }
    }
}

final class _WeakPreview: @unchecked Sendable {
    weak var layer: AVCaptureVideoPreviewLayer?
    init(_ layer: AVCaptureVideoPreviewLayer) { self.layer = layer }
}

// MARK: - Outputs

/// Where a session sends what it captures.
open class AVCaptureOutput: NSObject, @unchecked Sendable {
    weak var session: AVCaptureSession?
    lazy var connection = AVCaptureConnection(session: session, output: self)

    override init() {}

    open var connections: [AVCaptureConnection] { session?.videoDevice != nil ? [connection] : [] }
    open func connection(with mediaType: AVMediaType) -> AVCaptureConnection? {
        mediaType == .video ? connections.first : nil
    }
    /// Metadata coordinates are the picture's already.
    open func transformedMetadataObject(for metadataObject: AVMetadataObject, connection: AVCaptureConnection) -> AVMetadataObject? { metadataObject }
    open func metadataOutputRectConverted(fromOutputRect rectInOutputCoordinates: CGRect) -> CGRect { rectInOutputCoordinates }
    open func outputRectConverted(fromMetadataOutputRect rectInMetadataOutputCoordinates: CGRect) -> CGRect { rectInMetadataOutputCoordinates }
}

/// The delegate of a video data output: each frame, as it comes.
public protocol AVCaptureVideoDataOutputSampleBufferDelegate: NSObjectProtocol {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
}

extension AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {}
}

/// Frames as pixel buffers (BGRA, whatever the video settings ask).
open class AVCaptureVideoDataOutput: AVCaptureOutput, @unchecked Sendable {
    public override init() { super.init() }

    open var videoSettings: [String: Any]! = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
    open var alwaysDiscardsLateVideoFrames = true
    open var automaticallyConfiguresOutputBufferDimensions = true
    open var deliversPreviewSizedOutputBuffers = false
    open var availableVideoPixelFormatTypes: [OSType] { [kCVPixelFormatType_32BGRA] }
    open var availableVideoCodecTypes: [AVVideoCodecType] { [] }
    open private(set) weak var sampleBufferDelegate: (any AVCaptureVideoDataOutputSampleBufferDelegate)?
    open private(set) var sampleBufferCallbackQueue: DispatchQueue?

    open func setSampleBufferDelegate(_ sampleBufferDelegate: (any AVCaptureVideoDataOutputSampleBufferDelegate)?, queue sampleBufferCallbackQueue: DispatchQueue?) {
        self.sampleBufferDelegate = sampleBufferDelegate
        self.sampleBufferCallbackQueue = sampleBufferDelegate == nil ? nil : sampleBufferCallbackQueue
        session?.armOutputs()
    }

    open func recommendedVideoSettingsForAssetWriter(writingTo outputFileType: AVFileType) -> [String: Any]? {
        [AVVideoCodecKey: AVVideoCodecType.h264.rawValue]
    }

    func deliver(_ buffer: CMSampleBuffer) {
        guard let delegate = sampleBufferDelegate, connection.isEnabled else { return }
        nonisolated(unsafe) let target = delegate
        let connection = self.connection
        guard let queue = sampleBufferCallbackQueue, !_isMainQueue(queue) else {
            target.captureOutput(self, didOutput: buffer, from: connection)
            return
        }
        queue.async { target.captureOutput(self, didOutput: buffer, from: connection) }
    }
}

// MARK: - Codes

/// Something a metadata output found in the picture.
open class AVMetadataObject: NSObject, @unchecked Sendable {
    public struct ObjectType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let qr = ObjectType("org.iso.QRCode")
        public static let microQR = ObjectType("org.iso.MicroQR")
        public static let ean8 = ObjectType("org.gs1.EAN-8")
        public static let ean13 = ObjectType("org.gs1.EAN-13")
        public static let upce = ObjectType("org.gs1.UPC-E")
        public static let code39 = ObjectType("org.iso.Code39")
        public static let code39Mod43 = ObjectType("org.iso.Code39Mod43")
        public static let code93 = ObjectType("com.intermec.Code93")
        public static let code128 = ObjectType("org.iso.Code128")
        public static let pdf417 = ObjectType("org.iso.PDF417")
        public static let microPDF417 = ObjectType("org.iso.MicroPDF417")
        public static let aztec = ObjectType("org.iso.Aztec")
        public static let dataMatrix = ObjectType("org.iso.DataMatrix")
        public static let interleaved2of5 = ObjectType("org.ansi.Interleaved2of5")
        public static let itf14 = ObjectType("org.gs1.ITF14")
        public static let codabar = ObjectType("com.intermec.Codabar")
        public static let gs1DataBar = ObjectType("org.gs1.GS1DataBar")
        public static let gs1DataBarExpanded = ObjectType("org.gs1.GS1DataBarExpanded")
        public static let gs1DataBarLimited = ObjectType("org.gs1.GS1DataBarLimited")
        public static let face = ObjectType("face")
        public static let humanBody = ObjectType("mdta/com.apple.quicktime.detected-human-body")
        public static let catBody = ObjectType("mdta/com.apple.quicktime.detected-cat-body")
        public static let dogBody = ObjectType("mdta/com.apple.quicktime.detected-dog-body")
        public static let salientObject = ObjectType("mdta/com.apple.quicktime.detected-salient-object")

        private static let detectorNames: [ObjectType: String] = [
            .qr: "qr_code", .ean8: "ean_8", .ean13: "ean_13", .upce: "upc_e", .code39: "code_39", .code93: "code_93",
            .code128: "code_128", .pdf417: "pdf417", .aztec: "aztec", .dataMatrix: "data_matrix", .itf14: "itf", .codabar: "codabar",
        ]
        /// The `BarcodeDetector` format that reads it.
        var _detectorFormat: String? { Self.detectorNames[self] }
        static func _fromDetector(_ format: String) -> ObjectType? {
            if format == "upc_a" { return .ean13 }   // Apple reports UPC-A as EAN-13 with a leading 0
            return detectorNames.first { $0.value == format }?.key
        }
    }

    public let type: ObjectType
    /// Where it is, 0 to 1 in the picture (or in a layer's points, transformed).
    public let bounds: CGRect
    public let time: CMTime
    public let duration: CMTime

    init(type: ObjectType, bounds: CGRect, time: CMTime = .invalid) {
        self.type = type
        self.bounds = bounds
        self.time = time
        duration = .invalid
    }
}

/// A code read in the picture: its text and corners.
open class AVMetadataMachineReadableCodeObject: AVMetadataObject, @unchecked Sendable {
    public let stringValue: String?
    public let corners: [CGPoint]

    init(type: ObjectType, stringValue: String?, corners: [CGPoint]) {
        self.stringValue = stringValue
        self.corners = corners
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let bounds = corners.isEmpty ? .zero : CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        super.init(type: type, bounds: bounds)
    }
}

/// The delegate of a metadata output: what it found.
public protocol AVCaptureMetadataOutputObjectsDelegate: NSObjectProtocol {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection)
}

extension AVCaptureMetadataOutputObjectsDelegate {
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {}
}

/// Codes in the picture, through the browser's `BarcodeDetector` where it has one.
open class AVCaptureMetadataOutput: AVCaptureOutput, @unchecked Sendable {
    public override init() { super.init() }

    /// The types it can find: none until it is in a session with a camera, as on iOS.
    open var availableMetadataObjectTypes: [AVMetadataObject.ObjectType] {
        guard session?.videoDevice != nil else { return [] }
        return _AVCaptureHost.codeFormats.compactMap(AVMetadataObject.ObjectType._fromDetector)
    }

    /// The types to find (those it can't find are left out).
    open var metadataObjectTypes: [AVMetadataObject.ObjectType]! = [] {
        didSet {
            let available = Set(availableMetadataObjectTypes)
            metadataObjectTypes = (metadataObjectTypes ?? []).filter { available.contains($0) }
            if oldValue != metadataObjectTypes { session?.armOutputs() }
        }
    }

    /// The part of the picture to look in, 0 to 1.
    open var rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    open private(set) weak var metadataObjectsDelegate: (any AVCaptureMetadataOutputObjectsDelegate)?
    var delegate: (any AVCaptureMetadataOutputObjectsDelegate)? { metadataObjectsDelegate }
    open private(set) var metadataObjectsCallbackQueue: DispatchQueue?

    open func setMetadataObjectsDelegate(_ objectsDelegate: (any AVCaptureMetadataOutputObjectsDelegate)?, queue objectsCallbackQueue: DispatchQueue?) {
        metadataObjectsDelegate = objectsDelegate
        metadataObjectsCallbackQueue = objectsDelegate == nil ? nil : objectsCallbackQueue
        session?.armOutputs()
    }

    func deliver(_ codes: [_AVCaptureCode]) {
        guard let delegate = metadataObjectsDelegate, connection.isEnabled else { return }
        let wanted = Set(metadataObjectTypes ?? [])
        let objects: [AVMetadataObject] = codes.compactMap { code in
            guard let type = AVMetadataObject.ObjectType._fromDetector(code.format), wanted.contains(type) else { return nil }
            var corners: [CGPoint] = []
            var i = 0
            while i + 1 < code.corners.count { corners.append(CGPoint(x: code.corners[i], y: code.corners[i + 1])); i += 2 }
            let object = AVMetadataMachineReadableCodeObject(type: type, stringValue: code.value, corners: corners)
            return rectOfInterest.intersects(object.bounds) || object.bounds.isEmpty ? object : nil
        }
        // Apple calls the delegate only when something is found.
        guard !objects.isEmpty else { return }
        nonisolated(unsafe) let target = delegate
        let found = objects
        let connection = self.connection
        guard let queue = metadataObjectsCallbackQueue, !_isMainQueue(queue) else {
            target.metadataOutput(self, didOutput: found, from: connection)
            return
        }
        queue.async { target.metadataOutput(self, didOutput: found, from: connection) }
    }
}

// MARK: - The preview layer

/// The camera's live picture: the host's video element where the layer is.
open class AVCaptureVideoPreviewLayer: CALayer, _UIHostElementProviding {
    private var shown: AVCaptureSession?
    /// The session whose picture the layer shows.
    open var session: AVCaptureSession? {
        get { shown }
        set { if let newValue { attach(newValue) } else { detach() } }
    }
    open var videoGravity: AVLayerVideoGravity = .resizeAspect { didSet { setNeedsDisplay() } }
    open private(set) var connection: AVCaptureConnection?
    open var isPreviewing: Bool { session?._isLive ?? false }

    public required init() { super.init() }
    public override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? AVCaptureVideoPreviewLayer {
            videoGravity = other.videoGravity
            if let session = other.session { attach(session) }
        }
    }

    public convenience init(session: AVCaptureSession) {
        self.init()
        attach(session)
    }

    public convenience init(sessionWithNoConnection session: AVCaptureSession) {
        self.init()
        attach(session)
    }

    open func setSessionWithNoConnection(_ session: AVCaptureSession) { attach(session) }

    private func attach(_ session: AVCaptureSession) {
        detach()
        shown = session
        connection = AVCaptureConnection(session: session, output: nil)
        session.addPreview(self)
        setNeedsDisplay()
    }

    private func detach() {
        shown?.removePreview(self)
        shown = nil
        connection = nil
        setNeedsDisplay()
    }

    public var _hostElementKind: HostElement.Kind? {
        guard let session else { return nil }
        return .camera(session: session._identifier, live: session._isLive, mirrored: connection?.isVideoMirrored ?? false,
                       gravity: videoGravity.rawValue)
    }

    // MARK: Converting points

    /// The rectangle the picture fills in the layer.
    private var pictureRect: CGRect {
        let bounds = self.bounds
        guard let live = session?.live, live.width > 0, live.height > 0, bounds.width > 0, bounds.height > 0,
              videoGravity != .resize else { return bounds }
        let aspect = CGFloat(live.width) / CGFloat(live.height)
        let fitWidth = videoGravity == .resizeAspectFill ? bounds.width / bounds.height < aspect : bounds.width / bounds.height > aspect
        let size = fitWidth ? CGSize(width: bounds.height * aspect, height: bounds.height) : CGSize(width: bounds.width, height: bounds.width / aspect)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    private var mirrored: Bool { connection?.isVideoMirrored ?? false }

    /// A point in the layer as a point in the picture (0 to 1 from its top left).
    open func captureDevicePointConverted(fromLayerPoint pointInLayer: CGPoint) -> CGPoint {
        let rect = pictureRect
        guard rect.width > 0, rect.height > 0 else { return .zero }
        var x = (pointInLayer.x - rect.minX) / rect.width
        if mirrored { x = 1 - x }
        return CGPoint(x: x, y: (pointInLayer.y - rect.minY) / rect.height)
    }

    /// A point in the picture as a point in the layer.
    open func layerPointConverted(fromCaptureDevicePoint captureDevicePointOfInterest: CGPoint) -> CGPoint {
        let rect = pictureRect
        let x = mirrored ? 1 - captureDevicePointOfInterest.x : captureDevicePointOfInterest.x
        return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + captureDevicePointOfInterest.y * rect.height)
    }

    open func metadataOutputRectConverted(fromLayerRect rectInLayerCoordinates: CGRect) -> CGRect {
        let a = captureDevicePointConverted(fromLayerPoint: CGPoint(x: rectInLayerCoordinates.minX, y: rectInLayerCoordinates.minY))
        let b = captureDevicePointConverted(fromLayerPoint: CGPoint(x: rectInLayerCoordinates.maxX, y: rectInLayerCoordinates.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    open func layerRectConverted(fromMetadataOutputRect rectInMetadataOutputCoordinates: CGRect) -> CGRect {
        let a = layerPointConverted(fromCaptureDevicePoint: CGPoint(x: rectInMetadataOutputCoordinates.minX, y: rectInMetadataOutputCoordinates.minY))
        let b = layerPointConverted(fromCaptureDevicePoint: CGPoint(x: rectInMetadataOutputCoordinates.maxX, y: rectInMetadataOutputCoordinates.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// The object with its bounds and corners in the layer's coordinates.
    open func transformedMetadataObject(for metadataObject: AVMetadataObject) -> AVMetadataObject? {
        if let code = metadataObject as? AVMetadataMachineReadableCodeObject {
            return AVMetadataMachineReadableCodeObject(type: code.type, stringValue: code.stringValue,
                                                       corners: code.corners.map(layerPointConverted(fromCaptureDevicePoint:)))
        }
        return AVMetadataObject(type: metadataObject.type, bounds: layerRectConverted(fromMetadataOutputRect: metadataObject.bounds),
                                time: metadataObject.time)
    }
}

// MARK: - Photos

/// What a photo capture asks for.
open class AVCapturePhotoSettings: NSObject, @unchecked Sendable {
    nonisolated(unsafe) private static var counter: Int64 = 0
    public let uniqueID: Int64
    public let format: [String: Any]?
    open var flashMode: AVCaptureDevice.FlashMode = .off
    open var isHighResolutionPhotoEnabled = false
    open var maxPhotoDimensions = CMVideoDimensions()
    open var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization = .balanced
    open var isAutoStillImageStabilizationEnabled = true
    open var isAutoRedEyeReductionEnabled = true
    open var isDepthDataDeliveryEnabled = false
    open var embedsDepthDataInPhoto = true
    open var isPortraitEffectsMatteDeliveryEnabled = false
    open var isCameraCalibrationDataDeliveryEnabled = false
    open var isAutoContentAwareDistortionCorrectionEnabled = false
    open var previewPhotoFormat: [String: Any]?
    open var embeddedThumbnailPhotoFormat: [String: Any]?
    open var livePhotoMovieFileURL: URL?
    open var metadata: [String: Any] = [:]
    open var processedFileType: AVFileType? { .jpg }
    open var rawFileType: AVFileType? { nil }
    open var rawPhotoPixelFormatType: OSType { 0 }
    open var availablePreviewPhotoPixelFormatTypes: [OSType] { [kCVPixelFormatType_32BGRA] }
    open var __availablePreviewPhotoPixelFormatTypes: [NSNumber] { availablePreviewPhotoPixelFormatTypes.map { NSNumber(value: $0) } }
    open var availableEmbeddedThumbnailPhotoCodecTypes: [AVVideoCodecType] { [.jpeg] }

    public override init() {
        Self.counter += 1
        uniqueID = Self.counter
        format = nil
        super.init()
    }

    public init(format: [String: Any]?) {
        Self.counter += 1
        uniqueID = Self.counter
        self.format = format
        super.init()
    }

    public convenience init(from photoSettings: AVCapturePhotoSettings) {
        self.init(format: photoSettings.format)
        flashMode = photoSettings.flashMode
        isHighResolutionPhotoEnabled = photoSettings.isHighResolutionPhotoEnabled
        maxPhotoDimensions = photoSettings.maxPhotoDimensions
        photoQualityPrioritization = photoSettings.photoQualityPrioritization
        previewPhotoFormat = photoSettings.previewPhotoFormat
    }

    public convenience init(rawPixelFormatType: OSType, processedFormat: [String: Any]?) {
        self.init(format: processedFormat)
    }

    /// How many photos the capture makes.
    var expectedCount: Int { 1 }
}

/// Bracketed stills' settings.
open class AVCaptureBracketedStillImageSettings: NSObject, @unchecked Sendable {
    override init() {}
}

open class AVCaptureAutoExposureBracketedStillImageSettings: AVCaptureBracketedStillImageSettings, @unchecked Sendable {
    public let exposureTargetBias: Float
    init(bias: Float) { exposureTargetBias = bias }
    open class func autoExposureSettings(exposureTargetBias: Float) -> AVCaptureAutoExposureBracketedStillImageSettings {
        AVCaptureAutoExposureBracketedStillImageSettings(bias: exposureTargetBias)
    }
}

open class AVCaptureManualExposureBracketedStillImageSettings: AVCaptureBracketedStillImageSettings, @unchecked Sendable {
    public let exposureDuration: CMTime
    public let iso: Float
    init(duration: CMTime, iso: Float) { exposureDuration = duration; self.iso = iso }
    open class func manualExposureSettings(exposureDuration duration: CMTime, iso ISO: Float) -> AVCaptureManualExposureBracketedStillImageSettings {
        AVCaptureManualExposureBracketedStillImageSettings(duration: duration, iso: ISO)
    }
}

/// A burst of photos at different exposures (here, each the same still).
open class AVCapturePhotoBracketSettings: AVCapturePhotoSettings, @unchecked Sendable {
    public let bracketedSettings: [AVCaptureBracketedStillImageSettings]
    open var isLensStabilizationEnabled = false

    public init(rawPixelFormatType: OSType, processedFormat: [String: Any]?, bracketedSettings: [AVCaptureBracketedStillImageSettings]) {
        self.bracketedSettings = bracketedSettings
        super.init(format: processedFormat)
    }

    override var expectedCount: Int { max(bracketedSettings.count, 1) }
}

/// What a capture turned out to be.
open class AVCaptureResolvedPhotoSettings: NSObject, @unchecked Sendable {
    public let uniqueID: Int64
    public let photoDimensions: CMVideoDimensions
    public let expectedPhotoCount: Int
    open var isFlashEnabled: Bool { false }
    open var isRedEyeReductionEnabled: Bool { false }
    open var isStillImageStabilizationEnabled: Bool { false }
    open var previewDimensions: CMVideoDimensions { photoDimensions }
    open var embeddedThumbnailDimensions: CMVideoDimensions { CMVideoDimensions() }
    open var rawPhotoDimensions: CMVideoDimensions { CMVideoDimensions() }
    open var livePhotoMovieDimensions: CMVideoDimensions { CMVideoDimensions() }
    open var photoProcessingTimeRange: (start: CMTime, duration: CMTime) { (.zero, .zero) }

    init(uniqueID: Int64, photoDimensions: CMVideoDimensions, expectedPhotoCount: Int) {
        self.uniqueID = uniqueID
        self.photoDimensions = photoDimensions
        self.expectedPhotoCount = expectedPhotoCount
    }
}

/// A still: its JPEG data and pixels.
open class AVCapturePhoto: NSObject, @unchecked Sendable {
    let jpeg: [UInt8]
    let rgba: [UInt8]
    let size: CMVideoDimensions
    public let resolvedSettings: AVCaptureResolvedPhotoSettings
    public let photoCount: Int
    public let timestamp: CMTime
    public let bracketSettings: AVCaptureBracketedStillImageSettings?
    public let sequenceCount: Int

    init(jpeg: [UInt8], rgba: [UInt8], size: CMVideoDimensions, resolvedSettings: AVCaptureResolvedPhotoSettings, photoCount: Int,
         bracketSettings: AVCaptureBracketedStillImageSettings?) {
        self.jpeg = jpeg
        self.rgba = rgba
        self.size = size
        self.resolvedSettings = resolvedSettings
        self.photoCount = photoCount
        self.bracketSettings = bracketSettings
        sequenceCount = photoCount
        timestamp = .zero
    }

    open var isRawPhoto: Bool { false }
    open var metadata: [String: Any] { [:] }
    open var pixelBuffer: CVPixelBuffer? {
        guard !rgba.isEmpty else { return nil }
        var bgra = rgba
        var i = 0
        while i + 3 < bgra.count { bgra.swapAt(i, i + 2); i += 4 }
        return CVPixelBuffer(width: Int(size.width), height: Int(size.height), bytes: bgra)
    }
    open var previewPixelBuffer: CVPixelBuffer? { pixelBuffer }
    open var embeddedThumbnailPhotoFormat: [String: Any]? { nil }
    open var lensStabilizationStatus: Int { 0 }

    /// The photo as a JPEG file.
    open func fileDataRepresentation() -> Data? { jpeg.isEmpty ? nil : Data(jpeg) }
    open func fileDataRepresentation(with customizer: Any) -> Data? { fileDataRepresentation() }

    /// The photo as an image.
    open func cgImageRepresentation() -> CGImage? {
        #if os(WASI) || !canImport(CoreGraphics)
        guard !rgba.isEmpty, let provider = CGDataProvider(data: Data(rgba)) else { return nil }
        return CGImage(width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(size.width) * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        #else
        return nil
        #endif
    }
    open func previewCGImageRepresentation() -> CGImage? { cgImageRepresentation() }
}

/// The delegate of a photo capture: the capture's steps, each with a do-nothing default.
public protocol AVCapturePhotoCaptureDelegate: NSObjectProtocol {
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings)
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings)
    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL,
                     resolvedSettings: AVCaptureResolvedPhotoSettings)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime,
                     photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?)
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?)
}

extension AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {}
    public func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {}
    public func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {}
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {}
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL,
                            resolvedSettings: AVCaptureResolvedPhotoSettings) {}
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime,
                            photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {}
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {}
}

/// Stills from the camera: the stream's picture at its size, as JPEG.
open class AVCapturePhotoOutput: AVCaptureOutput, @unchecked Sendable {
    public enum QualityPrioritization: Int, Sendable { case speed = 1, balanced, quality }

    public override init() { super.init() }

    open var isHighResolutionCaptureEnabled = false
    open var maxPhotoQualityPrioritization: QualityPrioritization = .quality
    open var maxPhotoDimensions = CMVideoDimensions()
    open var supportedFlashModes: [AVCaptureDevice.FlashMode] { [.off] }
    open var availablePhotoCodecTypes: [AVVideoCodecType] { [.jpeg] }
    open var availablePhotoFileTypes: [AVFileType] { [.jpg] }
    open var availableRawPhotoPixelFormatTypes: [OSType] { [] }
    open var availablePhotoPixelFormatTypes: [OSType] { [kCVPixelFormatType_32BGRA] }
    open var isAppleProRAWSupported: Bool { false }
    open var isAppleProRAWEnabled = false
    open var isLivePhotoCaptureSupported: Bool { false }
    open var isLivePhotoCaptureEnabled = false
    open var isLivePhotoAutoTrimmingEnabled = false
    open var isDepthDataDeliverySupported: Bool { false }
    open var isDepthDataDeliveryEnabled = false
    open var isPortraitEffectsMatteDeliverySupported: Bool { false }
    open var isPortraitEffectsMatteDeliveryEnabled = false
    open var isDualCameraDualPhotoDeliverySupported: Bool { false }
    open var isVirtualDeviceConstituentPhotoDeliverySupported: Bool { false }
    open var isVirtualDeviceConstituentPhotoDeliveryEnabled = false
    open var isCameraCalibrationDataDeliverySupported: Bool { false }
    open var isStillImageStabilizationSupported: Bool { false }
    open var isStillImageStabilizationScene: Bool { false }
    open var isFlashScene: Bool { false }
    open var isContentAwareDistortionCorrectionSupported: Bool { false }
    open var isContentAwareDistortionCorrectionEnabled = false
    open var isZeroShutterLagSupported: Bool { false }
    open var isZeroShutterLagEnabled = false
    open var isResponsiveCaptureSupported: Bool { false }
    open var isResponsiveCaptureEnabled = false
    open var isFastCapturePrioritizationSupported: Bool { false }
    open var isFastCapturePrioritizationEnabled = false
    open var maxBracketedCapturePhotoCount: Int { 3 }
    open var isLensStabilizationDuringBracketedCaptureSupported: Bool { false }
    open var photoSettingsForSceneMonitoring: AVCapturePhotoSettings?
    open private(set) var preparedPhotoSettingsArray: [AVCapturePhotoSettings] = []
    open func setPreparedPhotoSettingsArray(_ preparedPhotoSettingsArray: [AVCapturePhotoSettings],
                                            completionHandler: (@Sendable (Bool, (any Error)?) -> Void)? = nil) {
        self.preparedPhotoSettingsArray = preparedPhotoSettingsArray
        completionHandler?(true, nil)
    }
    open func supportedPhotoPixelFormatTypes(for fileType: AVFileType) -> [OSType] { [] }
    open func supportedPhotoCodecTypes(for fileType: AVFileType) -> [AVVideoCodecType] { fileType == .jpg ? [.jpeg] : [] }

    /// Takes a still and tells the delegate each step, on the main queue.
    open func capturePhoto(with settings: AVCapturePhotoSettings, delegate: any AVCapturePhotoCaptureDelegate) {
        let stream = session?.activeStream
        let live = session?.live
        let size = CMVideoDimensions(width: Int32(live?.width ?? 0), height: Int32(live?.height ?? 0))
        let resolved = AVCaptureResolvedPhotoSettings(uniqueID: settings.uniqueID, photoDimensions: size, expectedPhotoCount: settings.expectedCount)
        delegate.photoOutput(self, willBeginCaptureFor: resolved)
        guard let stream else {
            let error = AVError(.sessionNotRunning)
            delegate.photoOutput(self, didFinishProcessingPhoto: AVCapturePhoto(jpeg: [], rgba: [], size: size, resolvedSettings: resolved,
                                                                                photoCount: 1, bracketSettings: nil), error: error)
            delegate.photoOutput(self, didFinishCaptureFor: resolved, error: error)
            return
        }
        delegate.photoOutput(self, willCapturePhotoFor: resolved)
        let brackets = (settings as? AVCapturePhotoBracketSettings)?.bracketedSettings ?? []
        nonisolated(unsafe) let target = delegate
        stream.takePhoto { [self] jpeg, width, height, rgba in
            let size = CMVideoDimensions(width: Int32(width), height: Int32(height))
            let resolved = AVCaptureResolvedPhotoSettings(uniqueID: settings.uniqueID, photoDimensions: size,
                                                          expectedPhotoCount: settings.expectedCount)
            target.photoOutput(self, didCapturePhotoFor: resolved)
            let error: AVError? = jpeg.isEmpty ? AVError(.noDataCaptured) : nil
            for index in 0..<settings.expectedCount {
                let photo = AVCapturePhoto(jpeg: jpeg, rgba: rgba, size: size, resolvedSettings: resolved, photoCount: index + 1,
                                           bracketSettings: brackets.indices.contains(index) ? brackets[index] : nil)
                target.photoOutput(self, didFinishProcessingPhoto: photo, error: error)
            }
            target.photoOutput(self, didFinishCaptureFor: resolved, error: error)
        }
    }
}

// MARK: - Movies

/// The delegate of a file output's recording.
public protocol AVCaptureFileOutputRecordingDelegate: NSObjectProtocol {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection])
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?)
}

extension AVCaptureFileOutputRecordingDelegate {
    public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {}
}

/// Records to a file.
open class AVCaptureFileOutput: AVCaptureOutput, @unchecked Sendable {
    open private(set) var outputFileURL: URL?
    open private(set) var isRecording = false
    open var isRecordingPaused: Bool { false }
    open var maxRecordedDuration = CMTime.invalid
    open var maxRecordedFileSize: Int64 = 0
    open var minFreeDiskSpaceLimit: Int64 = 0
    open var recordedFileSize: Int64 { 0 }
    private var startedAt: Double?
    open var recordedDuration: CMTime {
        guard let startedAt else { return .zero }
        return CMTime(seconds: Date().timeIntervalSince1970 - startedAt)
    }
    private weak var recordingDelegate: (any AVCaptureFileOutputRecordingDelegate)?

    /// Starts recording what the camera sees (and hears, with a microphone input); the host
    /// records WebM or MP4, whichever the browser makes, whatever the file's extension says.
    open func startRecording(to outputFileURL: URL, recordingDelegate delegate: any AVCaptureFileOutputRecordingDelegate) {
        guard !isRecording else { return }
        self.outputFileURL = outputFileURL
        recordingDelegate = delegate
        guard let stream = session?.activeStream else {
            delegate.fileOutput(self, didFinishRecordingTo: outputFileURL, from: connections,
                                error: AVError(.sessionNotRunning, userInfo: [AVErrorRecordingSuccessfullyFinishedKey: false]))
            return
        }
        isRecording = true
        startedAt = Date().timeIntervalSince1970
        stream.startRecording()
        delegate.fileOutput(self, didStartRecordingTo: outputFileURL, from: connections)
    }

    open func stopRecording() {
        guard isRecording, let url = outputFileURL else { return }
        isRecording = false
        startedAt = nil
        let connections = self.connections
        nonisolated(unsafe) let delegate = recordingDelegate
        guard let stream = session?.activeStream else {
            delegate?.fileOutput(self, didFinishRecordingTo: url, from: connections, error: AVError(.sessionNotRunning))
            return
        }
        stream.stopRecording { [self] data, _ in
            var failure: (any Error)? = data.isEmpty ? AVError(.noDataCaptured, userInfo: [AVErrorRecordingSuccessfullyFinishedKey: false]) : nil
            if failure == nil {
                do { try Data(data).write(to: url) } catch { failure = error }
            }
            delegate?.fileOutput(self, didFinishRecordingTo: url, from: connections, error: failure)
        }
    }

    open func pauseRecording() {}
    open func resumeRecording() {}
}

/// Records movies.
open class AVCaptureMovieFileOutput: AVCaptureFileOutput, @unchecked Sendable {
    public override init() { super.init() }
    open var movieFragmentInterval = CMTime(seconds: 10)
    open var availableVideoCodecTypes: [AVVideoCodecType] { [.h264] }
    open func outputSettings(for connection: AVCaptureConnection) -> [String: Any] { [AVVideoCodecKey: AVVideoCodecType.h264.rawValue] }
    open func setOutputSettings(_ outputSettings: [String: Any]?, for connection: AVCaptureConnection) {}
    open func supportedOutputSettingsKeys(for connection: AVCaptureConnection) -> [String] { [AVVideoCodecKey] }
    open func recordsVideoOrientationAndMirroringChangesAsMetadataTrack(for connection: AVCaptureConnection) -> Bool { false }
}
