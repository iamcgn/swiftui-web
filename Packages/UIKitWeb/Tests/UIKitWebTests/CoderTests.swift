// `init?(coder:)` (pf-nscoder): UIKit requires it of every view and controller subclass with an
// initializer of its own, so apps write it, usually calling `super.init(coder:)`. The web has
// no storyboards or nibs, so no archive ever reaches it; it still has to compile and behave.
import Testing
import UIKit
@testable import UIKitWebCore

/// The shape apps write: a designated initializer of its own, and the required one calling
/// `super.init(coder:)` with its setup after.
@MainActor private final class BadgeView: UIView {
    var setUp = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp = true
    }
}

@MainActor private final class DetailController: UIViewController {
    let item: String

    init(item: String) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        item = "archived"
        super.init(coder: coder)
    }
}

@MainActor @Suite struct CoderTests {
    @Test func appSubclassesBuildFromACoder() throws {
        let view = try #require(BadgeView(coder: NSCoder()))
        #expect(view.setUp)
        #expect(view.frame == .zero)
        view.frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        #expect(view.layer.bounds.size == CGSize(width: 40, height: 20))

        let controller = try #require(DetailController(coder: NSCoder()))
        #expect(controller.item == "archived")
        #expect(controller.view != nil)
        #expect(DetailController(item: "live").item == "live")
    }

    /// UIKit's own classes are built only from an archive this way, and there is none.
    @Test func uikitClassesHaveNoArchive() {
        #expect(UILabel(coder: NSCoder()) == nil)
        #expect(UIButton(coder: NSCoder()) == nil)
        #expect(UINavigationController(coder: NSCoder()) == nil)
    }
}
