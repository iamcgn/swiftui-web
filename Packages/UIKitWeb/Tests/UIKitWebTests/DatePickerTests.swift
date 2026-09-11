// UIDatePicker (Controls/UIDatePicker.swift): the compact capsules' strings, sizes and
// placement, the disabled look, and the wheels size.
import Testing
import UIKit
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

@Suite @MainActor struct DatePickerTests {
    private func fixedDate() -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 11; components.hour = 14; components.minute = 30
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test func compactCapsulesFormatAndSize() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.date = fixedDate()
        #expect(picker.datePickerStyle == .compact)
        picker.sizeToFit()
        #expect(picker.frame.size == CGSize(width: 212.5, height: 40))
        picker.datePickerMode = .date
        #expect(picker.sizeThatFits(.zero) == CGSize(width: 212.5, height: 38.5))
        picker.datePickerMode = .time
        #expect(picker.sizeThatFits(.zero).height == 40)
        var morning = DateComponents()
        morning.year = 2026; morning.month = 1; morning.day = 5; morning.hour = 0; morning.minute = 5
        picker.date = Calendar(identifier: .gregorian).date(from: morning)!
        picker.preferredDatePickerStyle = .wheels
        #expect(picker.sizeThatFits(.zero) == CGSize(width: 320, height: 216))
    }

    @Test func semanticsCarryTheFormattedDate() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.date = fixedDate()
        picker.sizeToFit()
        picker.frame.origin = CGPoint(x: 16, y: 16)
        root.view.addSubview(picker)
        scene.layout(in: CGSize(width: 320, height: 400))
        let node = scene.semanticsTree().first { $0.role == .button }
        #expect(node?.label == "Sep 11, 2026 2:30\u{202F}PM")
        #expect(node?.frame == CGRect(x: 16, y: 16, width: 212.5, height: 40))
        var morning = DateComponents()
        morning.year = 2026; morning.month = 1; morning.day = 5; morning.hour = 0; morning.minute = 5
        picker.date = Calendar(identifier: .gregorian).date(from: morning)!
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(scene.semanticsTree().first { $0.role == .button }?.label == "Jan 5, 2026 12:05\u{202F}AM")
    }
}

