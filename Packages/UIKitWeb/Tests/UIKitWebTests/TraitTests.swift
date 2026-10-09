// uk-traits (Values/UITraitCollection.swift, UIView.propagateTraitChange): a view's
// overrideUserInterfaceStyle reaches its subtree's traitCollectionDidChange, the owning view
// controller and registered observers; the window's override and the host's scheme too; the
// size classes follow the host's size and fire the observers that watch them.
import Testing
import UIKit
@testable import UIKitWebCore

@MainActor private final class Watcher: UIView {
    var changes: [UIUserInterfaceStyle] = []
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        changes.append(traitCollection.userInterfaceStyle)
    }
}

@MainActor private final class Screen: UIViewController {
    var previous: [UIUserInterfaceStyle?] = []
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        previous.append(previousTraitCollection?.userInterfaceStyle)
    }
}

@Suite @MainActor struct TraitTests {
    @Test func overridesPropagateAndObserversFire() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.hostColorScheme = .light
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        #expect(UIScreen.main.traitCollection.horizontalSizeClass == .compact && UIScreen.main.traitCollection.verticalSizeClass == .regular)
        let screen = Screen()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = screen
        window.makeKeyAndVisible()
        let island = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let leaf = Watcher(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        leaf.backgroundColor = .systemBackground
        island.addSubview(leaf)
        screen.view.addSubview(island)
        scene.layout(in: CGSize(width: 320, height: 480))

        var seen: [(UIUserInterfaceStyle, UIUserInterfaceStyle?)] = []
        let registration = leaf.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { view, previous in
            seen.append((view.traitCollection.userInterfaceStyle, previous.userInterfaceStyle))
        }
        var sizeChanges = 0
        screen.registerForTraitChanges([UITraitVerticalSizeClass.self, UITraitHorizontalSizeClass.self]) { _, _ in sizeChanges += 1 }

        island.overrideUserInterfaceStyle = .dark
        #expect(leaf.traitCollection.userInterfaceStyle == .dark && leaf.changes == [.dark])
        #expect(seen.count == 1 && seen[0].0 == .dark && seen[0].1 == .light)
        #expect(leaf.layer.backgroundColor.flatMap { RGBA(cgColor: $0) } == UIColor.systemBackground.rgba(for: .dark))
        #expect(screen.previous.isEmpty)   // the controller's own view did not change
        island.traitOverrides.layoutDirection = .rightToLeft   // not a style change: the style observer stays quiet
        #expect(seen.count == 1 && leaf.changes.count == 2)
        leaf.unregisterForTraitChanges(registration)
        island.overrideUserInterfaceStyle = .unspecified
        #expect(leaf.traitCollection.userInterfaceStyle == .light && seen.count == 1 && leaf.changes.last == .light)

        // The window's override and the host's scheme reach the same callbacks.
        window.overrideUserInterfaceStyle = .dark
        #expect(leaf.changes.last == .dark && screen.previous.last == .light)
        window.overrideUserInterfaceStyle = .unspecified
        scene.hostColorScheme = .dark
        #expect(leaf.traitCollection.userInterfaceStyle == .dark && leaf.changes.last == .dark)
        scene.hostColorScheme = .light

        // A shorter host turns the vertical size class compact; the controller's observer hears it.
        scene.layout(in: CGSize(width: 320, height: 380))
        #expect(sizeChanges == 1 && screen.traitCollection.verticalSizeClass == .compact)
        scene.layout(in: CGSize(width: 800, height: 400))
        #expect(sizeChanges == 2 && screen.traitCollection.horizontalSizeClass == .regular && UIScreen.main.traitCollection.userInterfaceIdiom == .pad)
        scene.layout(in: CGSize(width: 320, height: 480))
        scene.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
    }
}
