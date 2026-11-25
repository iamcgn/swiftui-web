// Coordinate spaces (Views/UICoordinateSpace.swift), an input view's controller and a symbol's
// configuration applied over its own, as Mlem uses them: a keyboard accessory's frame on the
// screen, a markdown toolbar's controller, and an avatar's symbol at a font's size.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct CoordinateSpaceTests {
    @Test func aViewConvertsIntoTheScreensSpace() {
        UIKitScene.shared.configureScreen(size: CGSize(width: 320, height: 480), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let container = UIView(frame: CGRect(x: 20, y: 100, width: 200, height: 200))
        let accessory = UIView(frame: CGRect(x: 10, y: 30, width: 50, height: 40))
        window.addSubview(container)
        container.addSubview(accessory)

        let screen = UIScreen.main.coordinateSpace
        #expect(screen.bounds == CGRect(x: 0, y: 0, width: 320, height: 480))
        #expect(UIScreen.main.fixedCoordinateSpace.bounds == screen.bounds)
        #expect(accessory.convert(accessory.bounds, to: screen) == CGRect(x: 30, y: 130, width: 50, height: 40))
        #expect(accessory.convert(CGPoint(x: 30, y: 130), from: screen) == .zero)
        #expect(screen.convert(CGPoint(x: 30, y: 130), to: accessory) == .zero)
        #expect(screen.convert(CGRect(x: 0, y: 0, width: 5, height: 5), from: container) == CGRect(x: 20, y: 100, width: 5, height: 5))

        // A view taken as a coordinate space converts as the view itself does.
        let space: any UICoordinateSpace = container
        #expect(accessory.convert(CGPoint.zero, to: space) == CGPoint(x: 10, y: 30))
        #expect(accessory.convert(CGPoint.zero, to: container) == CGPoint(x: 10, y: 30))
        #expect(container.convert(CGRect(x: 1, y: 1, width: 2, height: 2), from: space) == CGRect(x: 1, y: 1, width: 2, height: 2))
    }

    @Test func anInputViewController() {
        #expect(UIResponder().inputViewController == nil)
        #expect(UIResponder().inputAccessoryViewController == nil)
        let controller = UIInputViewController()
        #expect(controller.inputView == nil)
        let keys = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 216), inputViewStyle: .keyboard)
        controller.inputView = keys
        #expect(controller.inputView === keys)
        #expect(!controller.needsInputModeSwitchKey && !controller.hasFullAccess)
        controller.addChild(UIViewController())
        #expect(controller.children.count == 1)
        controller.advanceToNextInputMode()
        controller.dismissKeyboard()
    }

    @Test func applyingASymbolConfiguration() throws {
        let star = try #require(UIImage(systemName: "star", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)))
        let sized = try #require(star.applyingSymbolConfiguration(UIImage.SymbolConfiguration(font: .systemFont(ofSize: 24))))
        #expect(sized.configuration?.pointSize == 24)
        #expect(sized.configuration?.weight == .bold)
        #expect(sized.size.width == 30)
    }
}
