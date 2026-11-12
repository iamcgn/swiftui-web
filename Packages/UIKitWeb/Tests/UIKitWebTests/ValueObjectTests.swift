// UIKit's value classes as objects (UIObjectBase.swift): colours, fonts and images compare and
// hash by what they show on every platform, and with the Objective-C runtime they are
// NSObjects (decision 0023), so an `@objc` protocol can return them, as CVCalendar's
// appearance delegate does.
import Testing
import UIKit
@testable import UIKitWebCore

#if canImport(ObjectiveC)
/// CVCalendar's appearance delegate (CVCalendarViewAppearanceDelegate.swift), cut down: optional
/// `@objc` requirements that take and return colours, fonts and images.
@objc protocol AppearanceDelegate {
    @objc optional func dayLabelWeekdayInTextColor() -> UIColor
    @objc optional func dayLabelFont(by weekDay: Int, status: Int, present: Int) -> UIFont
    @objc optional func markerImage() -> UIImage?
    @objc optional func spotlight(color: UIColor, font: UIFont)
}

final class Appearance: NSObject, AppearanceDelegate {
    func dayLabelWeekdayInTextColor() -> UIColor { .systemRed }
    func dayLabelFont(by weekDay: Int, status: Int, present: Int) -> UIFont { .boldSystemFont(ofSize: 14) }
}
#endif

@Suite struct ValueObjectTests {
    @Test func coloursFontsAndImagesCompareByWhatTheyShow() {
        #expect(UIColor(red: 1, green: 0, blue: 0, alpha: 1) == UIColor(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(UIColor(red: 1, green: 0, blue: 0, alpha: 1) != UIColor(white: 0, alpha: 1))
        #expect(Set([UIColor(white: 1, alpha: 1), UIColor(white: 1, alpha: 1), .black]).count == 2)
        #expect(UIFont.systemFont(ofSize: 12) == UIFont.systemFont(ofSize: 12))
        #expect(UIFont.systemFont(ofSize: 12) != UIFont.systemFont(ofSize: 13))
        #expect(Set([UIFont.systemFont(ofSize: 12), .systemFont(ofSize: 12)]).count == 1)
        func symbol(_ name: String) -> UIImage { UIImage(name: name, isSystemSymbol: true, size: CGSize(width: 20, height: 20)) }
        let star = symbol("star")
        #expect(star == symbol("star") && star != symbol("heart"))
        #expect(Set([star, symbol("star")]).count == 1)
        #expect((star.copy() as? UIImage) === star)
        let optional: UIColor? = .black
        #expect(optional == .black)
    }

    #if canImport(ObjectiveC)
    @Test func theyAreObjectiveCObjects() {
        let color: NSObject = UIColor.systemBlue
        #expect(color.isEqual(UIColor.systemBlue) && !color.isEqual(UIColor.systemRed) && !color.isEqual("blue"))
        #expect(color.hash == UIColor.systemBlue.hash)
        let font: NSObject = UIFont.systemFont(ofSize: 15)
        #expect(font.isEqual(UIFont.systemFont(ofSize: 15)) && font.hash == UIFont.systemFont(ofSize: 15).hash)
        let image: NSObject = UIImage()
        #expect(image.isEqual(UIImage()) && image.copy() as AnyObject === image)
        #expect(UIImage().responds(to: #selector(NSCopying.copy(with:))))
    }

    @Test func anObjectiveCProtocolReturnsThem() {
        let delegate: AppearanceDelegate = Appearance()
        #expect(delegate.dayLabelWeekdayInTextColor?() == .systemRed)
        #expect(delegate.dayLabelFont?(by: 1, status: 0, present: 0) == .boldSystemFont(ofSize: 14))
        #expect(delegate.markerImage?() == nil)
        // Sent by selector, as the calendar asks a delegate that may not implement it.
        let object = Appearance()
        let sent = object.perform(#selector(AppearanceDelegate.dayLabelWeekdayInTextColor))?.takeUnretainedValue() as? UIColor
        #expect(sent == .systemRed)
        #expect(!object.responds(to: #selector(AppearanceDelegate.spotlight(color:font:))))
    }
    #endif
}
