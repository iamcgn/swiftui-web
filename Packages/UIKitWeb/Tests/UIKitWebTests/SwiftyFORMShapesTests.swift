// UIKit shapes SwiftyFORM and WhatsNewKit use: a collection cell whose own `init(frame:)` isn't
// `required` (with the Objective-C runtime, as UIKit's isn't), a table cell with a `style` of its
// own, storyboards and nibs that hold nothing, and a struct that stores an attributed string and
// synthesizes Hashable. No `@testable` import here: a subclass must see only UIKit's surface.
import Testing
import UIKit

#if canImport(ObjectiveC)
/// SwiftyFORM's slider cells' shape: an `override init(frame:)` with no `required`.
@MainActor private final class SliderCell: UICollectionViewCell {
    var madeWithOwnInitializer = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        madeWithOwnInitializer = true
    }
    required init?(coder: NSCoder) { nil }
}

@MainActor private final class SliderHeader: UICollectionReusableView {
    var madeWithOwnInitializer = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        madeWithOwnInitializer = true
    }
    required init?(coder: NSCoder) { nil }
}
#endif

/// SwiftyFORM's precision slider cell's shape: a `style` of its own, which UIKit's cell lacks.
@MainActor private final class StyledCell: UITableViewCell {
    enum Style { case plain, precise }
    var style: Style = .precise
}

/// WhatsNewKit's `WhatsNew.Text` shape: Hashable, synthesized over an attributed string.
private struct Text: Hashable {
    var attributedString: NSAttributedString
}

@Suite @MainActor struct SwiftyFORMShapesTests {
    #if canImport(ObjectiveC)
    @Test func registeredCollectionViewsRunTheirOwnFrameInitializers() throws {
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), collectionViewLayout: UICollectionViewFlowLayout())
        collection.register(SliderCell.self, forCellWithReuseIdentifier: "slider")
        let cell = try #require(collection.dequeueReusableCell(withReuseIdentifier: "slider", for: IndexPath(item: 0, section: 0)) as? SliderCell)
        #expect(cell.madeWithOwnInitializer)
        #expect(cell.contentView.superview === cell && cell.reuseIdentifier == "slider")

        collection.register(SliderHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        let header = try #require(collection.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header", for: IndexPath(item: 0, section: 0)) as? SliderHeader)
        #expect(header.madeWithOwnInitializer)

        // UIKit's own classes still register and dequeue.
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "plain")
        let plain = collection.dequeueReusableCell(withReuseIdentifier: "plain", for: IndexPath(item: 1, section: 0))
        #expect(type(of: plain) == UICollectionViewCell.self && plain.contentView.superview === plain)
    }
    #endif

    @Test func aTableCellSubclassDeclaresAStyleOfItsOwn() {
        let cell = StyledCell(style: .subtitle, reuseIdentifier: "styled")
        #expect(cell.style == .precise && cell.detailTextLabel != nil && cell.reuseIdentifier == "styled")
    }

    @Test func storyboardsAndNibsHoldNothing() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        #expect(storyboard.instantiateInitialViewController() == nil)
        #expect(Bundle.main.loadNibNamed("Cell", owner: nil, options: nil) == nil)
        #expect(UINib(nibName: "Cell", bundle: nil).instantiate(withOwner: nil, options: nil).isEmpty)
        #expect(UIViewController().storyboard == nil)
    }

    @Test func aStructStoringAnAttributedStringIsHashable() {
        let a = Text(attributedString: NSAttributedString(string: "New"))
        let b = Text(attributedString: NSAttributedString(string: "New"))
        let c = Text(attributedString: NSAttributedString(string: "Old"))
        #expect(a == a && Set([a, a]).count == 1)
        #if os(WASI) || canImport(Darwin)
        // Equal by content, as Apple's are and the web's are. Linux's host tests run on
        // swift-corelibs-foundation, whose attributed strings hash by identity.
        #expect(a == b && a.hashValue == b.hashValue && a != c)
        #expect(Set([a, b, c]).count == 2)
        #endif
    }
}
