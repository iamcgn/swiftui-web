// UIKit members Mlem calls: a share-sheet activity's category, and a SwiftUI-style `Path(_:)` of
// a bezier path's `cgPath` (already the substrate's path) or of a CoreGraphics path.
import Testing
import UIKit
@testable import UIKitWebCore

@MainActor private final class OpenInBrowser: UIActivity {
    override class var activityCategory: UIActivity.Category { .share }
}

@Suite @MainActor struct MlemMembersTests {
    @Test func activitiesHaveCategories() {
        #expect(UIActivity.activityCategory == .action)
        #expect(OpenInBrowser.activityCategory == .share && UIActivity.Category(rawValue: 1) == .share)
    }

    @Test func pathsOfABezierPathAndACoreGraphicsPath() {
        let bezier = UIBezierPath(roundedRect: CGRect(x: 2, y: 3, width: 40, height: 20), cornerRadius: 6)
        #expect(Path(bezier.cgPath) == bezier.cgPath)
        let mutable = CGMutablePath()
        mutable.move(to: CGPoint(x: 0, y: 0))
        mutable.addLine(to: CGPoint(x: 10, y: 5))
        #expect(Path(mutable).boundingRect == CGRect(x: 0, y: 0, width: 10, height: 5))
    }
}
