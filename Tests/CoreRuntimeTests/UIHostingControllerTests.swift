// UIHostingController (Sources/SwiftUIWebUIKit/UIHostingController.swift): a SwiftUI view inside
// a UIKit window. The content lays out in the controller's view, paints into the scene's display
// list, sizes to fit, takes UIKit touches as pointer input, joins the scene's semantics tree and
// updates when its model changes.
#if !os(WASI)
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import Foundation

@Suite @MainActor struct UIHostingControllerTests {
    @Observable final class Model {
        var count = 0
    }

    struct Content: View {
        let model: Model
        var body: some View {
            VStack(spacing: 10) {
                Text("Count \(model.count)")
                Button("Tap") { model.count += 1 }
            }
            .padding(10)
        }
    }

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let body = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body)
        for word in ["Count 0", "Count 1", "Count 2", "Count 5", "Tap"] {
            entries[RecordedTextEngine.key(font: body, width: nil, string: word)] = .init(width: 50, height: 24.5, firstBaseline: 18.5, lastBaseline: 18.5)
        }
        return RecordedTextEngine(entries: entries, fonts: [body.key: .init(lineHeight: 24.5, spacingBelow: 8, spacingAbove: 8, textToText: 2)])
    }

    private func window(_ model: Model) -> (UIWindow, UIHostingController<Content>) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = engine()
        scene.configureScreen(size: CGSize(width: 300, height: 300), scale: 2)
        let controller = UIHostingController(rootView: Content(model: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 300))
        return (window, controller)
    }

    private func commands() -> [String] {
        UIKitScene.shared.layout(in: CGSize(width: 300, height: 300))
        return UIKitScene.shared.render(scale: 2, background: false).commands.map(\.description)
    }

    @Test func contentFillsTheControllerViewAndPaints() {
        let model = Model()
        let (window, controller) = window(model)
        #expect(controller.view.frame == window.bounds)
        let painted = commands()
        // The hosting view's white ground, then the SwiftUI content offset by nothing (it fills the window).
        #expect(painted.contains { $0.hasPrefix("fillRect(0, 0, 300, 300)") })
        #expect(painted.contains { $0.contains("drawText(\"Count 0\"") })
        #expect(painted.contains { $0.contains("drawText(\"Tap\"") })
    }

    @Test func sizesToFitAndUpdates() {
        let model = Model()
        let (_, controller) = window(model)
        // Two 24.5 pt lines 10 apart in 10 pt padding: 79 tall, the wider text plus padding across.
        let ideal = controller.sizeThatFits(in: UIView.layoutFittingExpandedSize)
        #expect(ideal.height == 79)
        #expect(ideal.width == 70)
        model.count = 5
        #expect(commands().contains { $0.contains("drawText(\"Count 5\"") })
    }

    /// ios/representable/hostingsafearea: a hosting controller under a navigation bar lays its
    /// content out below the bar, and a view ignoring the safe area extends under it; with
    /// `safeAreaRegions` empty the content fills the view (hostingsafearea-none).
    @Test func aContainersBarsAreTheContentsSafeArea() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = engine()
        scene.configureScreen(size: CGSize(width: 300, height: 300), scale: 2)
        let controller = UIHostingController(rootView: ZStack { Color.red.ignoresSafeArea(); Color.blue })
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        var painted = commands()
        // The bar ends 64 pt down (uikit/nav/basic): red everywhere, blue below the bar.
        #expect(painted.contains("fillRect(0, 0, 300, 300) #FF383C"), "\(painted)")
        #expect(painted.contains("fillRect(0, 64, 300, 236) #0088FF"), "\(painted)")
        controller.safeAreaRegions = []
        painted = commands()
        #expect(painted.contains("fillRect(0, 0, 300, 300) #0088FF"), "\(painted)")
    }

    /// ios/representable/hostingcollection: list cells hosting 20, 60 and 100 pt colours size
    /// themselves to 56 (the floor), 90 and 130 (15 pt margins above and below) and stack.
    @Test func hostedCollectionCellsSelfSize() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = engine()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let layout = UICollectionViewCompositionalLayout.list(using: UICollectionLayoutListConfiguration(appearance: .plain))
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: layout)
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, _, height in
            cell.contentConfiguration = UIHostingConfiguration { Color.green.frame(height: CGFloat(height)) }.background(Color.yellow)
        }
        let source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collection) { collection, indexPath, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([20, 60, 100])
        source.apply(snapshot, animatingDifferences: false)
        window.addSubview(collection)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 300))
        scene.layout(in: CGSize(width: 320, height: 300))
        let frames = (0..<3).map { collection.cellForItem(at: IndexPath(item: $0, section: 0))?.frame ?? .null }
        #expect(frames.map(\.minY) == [0, 56, 146], "\(frames)")
        #expect(frames.map(\.height) == [56, 90, 130], "\(frames)")
        #expect(collection.contentSize.height == 276)
    }

    struct Screen: View {
        let model: Model
        var body: some View {
            VStack { Text("Count \(model.count)") }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Tap") { model.count += 1 } }
                    ToolbarItem(placement: .topBarLeading) { Button("Count 0") { model.count += 10 } }
                }
        }
    }

    /// ios/representable/hostingnav: the content's navigation title and toolbar items become
    /// the controller's navigation item, titled bar buttons whose taps run the SwiftUI actions.
    @Test func navigationTitleAndToolbarDriveTheNavigationItem() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = engine()
        scene.configureScreen(size: CGSize(width: 300, height: 300), scale: 2)
        let model = Model()
        let controller = UIHostingController(rootView: Screen(model: model))
        let navigation = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 300))
        #expect(controller.navigationItem.title == "Settings")
        #expect(controller.navigationItem.rightBarButtonItems?.map(\.title) == ["Tap"])
        #expect(controller.navigationItem.leftBarButtonItems?.map(\.title) == ["Count 0"])
        // The bar items are the scene's buttons: activating them runs the SwiftUI actions.
        scene.layout(in: CGSize(width: 300, height: 300))
        let elements = scene.semanticsTree()
        let tap = elements.first { $0.role == .button && $0.label == "Tap" }
        #expect(tap != nil, "\(elements.map(\.label))")
        if let tap { scene.activate(semanticsIdentifier: tap.identifier) }
        #expect(model.count == 1)
        if let left = elements.first(where: { $0.role == .button && $0.label == "Count 0" }) { scene.activate(semanticsIdentifier: left.identifier) }
        #expect(model.count == 11)
        // (The bar's own labels need UIKit font metrics the headless engine here lacks; the
        // pixels are ios/representable/hostingnav's.)
    }

    /// A root view set inside `withAnimation` tweens, as a state change would; the sizing
    /// options keep the preferred size current and invalidate the intrinsic size on change.
    @Test func rootViewChangesAnimateAndSizingOptionsFollowContent() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = engine()
        scene.configureScreen(size: CGSize(width: 300, height: 300), scale: 2)
        let controller = UIHostingController(rootView: AnyView(Color.red.frame(width: 100, height: 40)))
        controller.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 300))
        #expect(controller.preferredContentSize == CGSize(width: 100, height: 40))
        #expect(controller.view.intrinsicContentSize == CGSize(width: 100, height: 40))
        withAnimation(.linear(duration: 1)) { controller.rootView = AnyView(Color.red.frame(width: 200, height: 40)) }
        scene.layout(in: CGSize(width: 300, height: 300))
        _ = scene.advanceFrame(elapsed: 0.5)
        let painted = commands()
        // Half way: 150 wide, centred in the 300 pt window.
        #expect(painted.contains("fillRect(75, 130, 150, 40) #FF383C"), "\(painted.filter { $0.hasPrefix("fillRect") })")
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(commands().contains("fillRect(50, 130, 200, 40) #FF383C"))
        #expect(controller.preferredContentSize == CGSize(width: 200, height: 40))
        #expect(controller.view.intrinsicContentSize == CGSize(width: 200, height: 40))
    }

    @Test func touchesReachTheContentAndSemanticsJoinTheScene() {
        let model = Model()
        let (_, _) = window(model)
        let semantics = UIKitScene.shared.semanticsTree()
        let button = semantics.first { $0.role == .button && $0.label == "Tap" }
        #expect(button != nil, "\(semantics)")
        guard let button else { return }
        // The button sits under the text, centred in the window.
        #expect(button.frame.midX == 150)
        #expect(button.frame.minY > 100)
        UIKitScene.shared.pointerDown(at: CGPoint(x: button.frame.midX, y: button.frame.midY), type: .touch, time: 1)
        UIKitScene.shared.pointerUp(at: CGPoint(x: button.frame.midX, y: button.frame.midY), time: 1.1)
        #expect(model.count == 1)
        // The accessibility route through the scene reaches it too.
        UIKitScene.shared.activate(semanticsIdentifier: button.identifier)
        #expect(model.count == 2)
    }
}
#endif
