// uk-pasteboard (App/UIPasteboard.swift, the responder edit actions): the general pasteboard
// holds strings, URLs, images and colours as typed items, counts its changes, hands its text to
// the host's clipboard writer and a hosting runtime's pasteboard, reads the runtime's text when
// that copied more recently, and the text controls copy, cut and paste through it.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct PasteboardTests {
    private func reset() -> UIKitScene {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 300), scale: 2)
        scene.clipboardWriter = nil
        scene.pasteboardSource = nil
        scene.pasteboardSink = nil
        UIPasteboard.general.items = []
        return scene
    }

    @Test func generalBoardValuesChangesAndClipboard() {
        let scene = reset()
        var written: [String] = []
        scene.clipboardWriter = { written.append($0) }
        let board = UIPasteboard.general
        let count = board.changeCount
        #expect(!board.hasStrings && board.numberOfItems == 0 && board.name == .general)
        board.string = "Hello"
        #expect(board.string == "Hello" && board.strings == ["Hello"] && board.hasStrings && board.numberOfItems == 1)
        #expect(board.changeCount == count + 1 && written == ["Hello"])
        #expect(board.pasteboardTypes() == ["public.utf8-plain-text"] && board.contains(pasteboardTypes: ["public.text", "public.utf8-plain-text"]))
        #expect(board.data(forPasteboardType: "public.utf8-plain-text").map { String(decoding: $0, as: UTF8.self) } == "Hello")
        board.strings = ["One", "Two"]
        #expect(board.numberOfItems == 2 && board.string == "One" && board.itemSet(withPasteboardTypes: ["public.utf8-plain-text"])?.count == 2)
        board.url = URL(string: "https://example.com")!
        #expect(board.hasURLs && board.url?.absoluteString == "https://example.com" && !board.hasStrings && board.string == nil)
        board.color = .systemRed
        #expect(board.hasColors && board.color == .systemRed && board.urls == nil)
        board.image = UIImage(systemName: "star")
        #expect(board.hasImages && board.images?.count == 1)
        board.setValue("custom", forPasteboardType: "com.example.custom")
        #expect(board.value(forPasteboardType: "com.example.custom") as? String == "custom" && board.hasImages)   // added to the first item
        board.setObjects(["Text", URL(string: "https://a.b")!])
        #expect(board.string == "Text" && board.urls?.count == 1 && board.numberOfItems == 2)
        board.addItems([["public.utf8-plain-text": "More"]])
        #expect(board.strings == ["Text", "More"] && written.last == "Text")
        #expect(board.itemProviders.count >= 1)
        board.items = []
        #expect(board.numberOfItems == 0 && board.changeCount > count + 5)
    }

    @Test func namedBoardsAreSeparate() {
        _ = reset()
        #expect(UIPasteboard(name: UIPasteboard.Name("com.example.missing"), create: false) == nil)
        let mine = UIPasteboard(name: UIPasteboard.Name("com.example.mine"), create: true)!
        mine.string = "Private"
        #expect(mine.string == "Private" && UIPasteboard.general.string == nil && !mine.isPersistent)
        let again = UIPasteboard(name: UIPasteboard.Name("com.example.mine"), create: false)!
        #expect(again.string == "Private")
        let unique = UIPasteboard.withUniqueName()
        #expect(unique.name != mine.name && unique.string == nil)
        UIPasteboard.remove(withName: mine.name)
        #expect(UIPasteboard(name: mine.name, create: false) == nil)
    }

    @Test func textControlsEditThroughTheBoard() {
        _ = reset()
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 34))
        field.text = "Field text"
        var edits = 0
        field.addAction(UIAction { _ in edits += 1 }, for: .editingChanged)
        field.copy(nil)
        #expect(UIPasteboard.general.string == "Field text")
        field.cut(nil)
        #expect(field.text == "" && edits == 1)
        field.paste(nil)
        #expect(field.text == "Field text" && edits == 2)
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        view.text = "Hello world"
        view.selectedRange = NSRange(location: 6, length: 5)
        view.copy(nil)
        #expect(UIPasteboard.general.string == "world")
        view.cut(nil)
        #expect(view.text == "Hello " && view.selectedRange == NSRange(location: 6, length: 0))
        view.paste(nil)
        view.paste(nil)
        #expect(view.text == "Hello worldworld" && view.selectedRange.location == 16)
        view.selectAll(nil)
        #expect(view.selectedRange == NSRange(location: 0, length: 16))
        view.delete(nil)
        #expect(view.text == "")
        view.isEditable = false
        view.paste(nil)
        #expect(view.text == "")   // not editable: nothing pastes
    }

    @Test func hostingRuntimeBridge() {
        let scene = reset()
        var runtimeText: String? = nil
        var generation = 0
        scene.pasteboardSource = { (generation, runtimeText) }
        scene.pasteboardSink = { runtimeText = $0; generation += 1 }
        UIPasteboard.general.string = "From UIKit"
        #expect(runtimeText == "From UIKit" && UIPasteboard.general.string == "From UIKit")
        // The runtime copies later: the general board reads its text.
        runtimeText = "From SwiftUI"
        generation += 1
        #expect(UIPasteboard.general.string == "From SwiftUI" && UIPasteboard.general.hasStrings)
        // UIKit copies again: its own text wins until the runtime copies once more.
        UIPasteboard.general.string = "UIKit again"
        #expect(UIPasteboard.general.string == "UIKit again" && runtimeText == "UIKit again")
    }
}
