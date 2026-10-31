// UIDevice (App/UIDevice.swift): the idiom, model and orientation come from the screen the host
// gives; the vendor identifier stays the same; alternate icons are unsupported.
import Testing
import UIKit

@Suite @MainActor struct DeviceTests {
    @MainActor final class Observer {
        var changes = 0
    }

    @Test func deviceFollowsTheScreen() {
        let scene = UIKitScene.shared
        let device = UIDevice.current
        scene.configureScreen(size: CGSize(width: 390, height: 844), scale: 3)
        #expect(device.userInterfaceIdiom == .phone && device.model == "iPhone" && device.systemName == "iOS")
        #expect(device.orientation == .portrait && device.orientation.isPortrait && !device.orientation.isFlat)

        let observer = Observer()
        let token = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { observer.changes += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        device.beginGeneratingDeviceOrientationNotifications()
        scene.configureScreen(size: CGSize(width: 1180, height: 820), scale: 2)
        #expect(device.userInterfaceIdiom == .pad && device.model == "iPad")
        #expect(device.orientation.isLandscape && device.orientation.isValidInterfaceOrientation && observer.changes == 1)
        device.endGeneratingDeviceOrientationNotifications()
        scene.configureScreen(size: CGSize(width: 390, height: 844), scale: 3)
        #expect(device.orientation == .portrait && observer.changes == 1)

        let id = device.identifierForVendor
        #expect(id != nil && device.identifierForVendor == id)
        #expect(device.batteryLevel == -1 && device.batteryState == .unknown && !device.systemVersion.isEmpty)
    }

    @Test func alternateIconsAreUnsupported() async {
        let application = UIApplication.shared
        #expect(!application.supportsAlternateIcons && application.alternateIconName == nil)
        var failed = false
        application.setAlternateIconName("Dark") { error in failed = error != nil }
        #expect(failed)
        await #expect(throws: (any Error).self) { try await application.setAlternateIconName("Dark") }
        await #expect(throws: Never.self) { try await application.setAlternateIconName(nil) }
    }
}
