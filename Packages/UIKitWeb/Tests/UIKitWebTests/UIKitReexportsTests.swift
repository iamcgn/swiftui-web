// Apple's UIKit brings UserNotifications with it: Harbour's app delegate imports only UIKit and
// sets `UNUserNotificationCenter.current().delegate`. This file imports nothing else.
import Testing
import UIKit

@Suite @MainActor struct UIKitReexportsTests {
    final class NotificationsDelegate: UNUserNotificationCenterDelegate {}

    @Test func importingUIKitNamesTheNotificationCentre() {
        let center = UNUserNotificationCenter.current()
        #expect(center === UNUserNotificationCenter.current())
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        #expect(options.contains(.badge) && !options.contains(.provisional))
        let delegate = NotificationsDelegate()
        let previous = center.delegate
        center.delegate = delegate
        #expect(center.delegate === delegate)
        center.delegate = previous
    }
}
