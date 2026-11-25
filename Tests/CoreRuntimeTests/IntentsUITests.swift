// Intents and IntentsUI (Sources/Intents, Sources/IntentsUI): Clendar's Siri shortcut screen
// compiles and runs: its Add to Siri button hands the controller the add sheet, the sheet keeps
// the phrase and reports it, the button then shows the phrase and hands over the edit sheet,
// which changes and deletes it. Siri itself is out of a page's reach, so authorization is
// denied and donations go nowhere. WidgetKit's preview context rides along.
import Testing
import SwiftUI
import WidgetKit
@testable import Intents
@testable import IntentsUI

@Suite @MainActor struct IntentsUITests {
    // Clendar's shape: a controller that owns the button and presents the sheets it is handed.
    final class SiriUIViewController: UIViewController {
        let shortcut: INShortcut
        let button = INUIAddVoiceShortcutButton(style: .blackOutline)
        var added: [INVoiceShortcut] = [], updated: [INVoiceShortcut] = [], deleted: [UUID] = []
        var cancels = 0

        init(shortcut: INShortcut) {
            self.shortcut = shortcut
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            button.shortcut = shortcut
            button.delegate = self
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
        }
    }

    private func activity(_ type: String, phrase: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type)
        activity.isEligibleForSearch = true
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(type)
        activity.title = "Add Event"
        activity.suggestedInvocationPhrase = phrase
        return activity
    }

    @Test func theButtonAddsEditsAndDeletesAPhrase() throws {
        let shortcut = INShortcut(userActivity: activity("com.example.add-event", phrase: "Add event"))
        #expect(shortcut.userActivity?.suggestedInvocationPhrase == "Add event" && shortcut.intent == nil)
        let controller = SiriUIViewController(shortcut: shortcut)
        controller.loadViewIfNeeded()
        #expect(controller.button.currentTitle == "Add to Siri" && controller.button.style == .blackOutline)
        #expect(controller.button.layer.borderWidth == 1)

        // No phrase yet: the button hands over the add sheet, prefilled with the suggestion.
        controller.button._pressed()
        let adder = try #require(controller.presentedViewController as? INUIAddVoiceShortcutViewController)
        #expect(adder.modalPresentationStyle == .formSheet && adder._sheet.phraseField.text == "Add event")
        adder.loadViewIfNeeded()
        #expect(adder._sheet.navigation?.viewControllers.first === adder._sheet && adder.children.count == 1)
        #expect(adder._sheet.navigationItem.rightBarButtonItem?.title == "Add" && adder._sheet.deleteButton.isHidden)
        adder._add()
        let added = try #require(controller.added.first)
        #expect(added.invocationPhrase == "Add event" && added.shortcut == shortcut)
        #expect(controller.presentedViewController == nil)
        #expect(controller.button.currentTitle == "\u{201C}Add event\u{201D}")
        var listed: [INVoiceShortcut] = []
        INVoiceShortcutCenter.shared.getAllVoiceShortcuts { shortcuts, _ in listed = shortcuts ?? [] }
        #expect(listed.contains { $0.identifier == added.identifier })

        // A phrase: the button hands over the edit sheet, which renames and then deletes it.
        controller.button._pressed()
        let editor = try #require(controller.presentedViewController as? INUIEditVoiceShortcutViewController)
        editor.loadViewIfNeeded()
        #expect(editor._sheet.phraseField.text == "Add event" && !editor._sheet.deleteButton.isHidden)
        editor._sheet.phraseField.text = "New event"
        editor._update()
        #expect(controller.updated.first?.invocationPhrase == "New event" && controller.updated.first?.identifier == added.identifier)
        #expect(controller.button.currentTitle == "\u{201C}New event\u{201D}")

        controller.button._pressed()
        let again = try #require(controller.presentedViewController as? INUIEditVoiceShortcutViewController)
        again._sheet.onCancel()
        #expect(controller.cancels == 1)
        controller.button._pressed()
        (controller.presentedViewController as? INUIEditVoiceShortcutViewController)?._delete()
        #expect(controller.deleted == [added.identifier] && controller.button.currentTitle == "Add to Siri")
        #expect(INVoiceShortcutCenter.shared._voiceShortcut(for: shortcut) == nil)
    }

    @Test func siriIsOutOfReachAndDonationsGoNowhere() throws {
        #expect(INPreferences.siriAuthorizationStatus() == .denied)
        var status: INSiriAuthorizationStatus?
        INPreferences.requestSiriAuthorization { status = $0 }
        #expect(status == .denied)

        let intent = INIntent()
        intent.suggestedInvocationPhrase = "Open settings"
        let shortcut = try #require(INShortcut(intent: intent))
        #expect(shortcut.intent === intent && shortcut._suggestedPhrase == "Open settings")
        #expect(shortcut == INShortcut(intent: intent) && shortcut != INShortcut(intent: INIntent()))
        var donated = false
        INInteraction(intent: intent, response: nil).donate { error in donated = error == nil }
        #expect(donated && intent.identifier != nil)
        INVoiceShortcutCenter.shared.setShortcutSuggestions([shortcut])
        #expect(INVoiceShortcutCenter.shared._suggestions == [shortcut])
    }

    @Test func widgetPreviewsNameTheirFamily() {
        let context = WidgetPreviewContext(family: .systemMedium)
        #expect(context.family == .systemMedium)
        _ = Text("Today").previewContext(WidgetPreviewContext(family: .systemSmall)).previewDisplayName("Small")
    }
}

extension IntentsUITests.SiriUIViewController: INUIAddVoiceShortcutButtonDelegate {
    func present(_ addVoiceShortcutViewController: INUIAddVoiceShortcutViewController, for addVoiceShortcutButton: INUIAddVoiceShortcutButton) {
        addVoiceShortcutViewController.delegate = self
        addVoiceShortcutViewController.modalPresentationStyle = .formSheet
        present(addVoiceShortcutViewController, animated: false, completion: nil)
    }

    func present(_ editVoiceShortcutViewController: INUIEditVoiceShortcutViewController, for addVoiceShortcutButton: INUIAddVoiceShortcutButton) {
        editVoiceShortcutViewController.delegate = self
        editVoiceShortcutViewController.modalPresentationStyle = .formSheet
        present(editVoiceShortcutViewController, animated: false, completion: nil)
    }
}

extension IntentsUITests.SiriUIViewController: INUIAddVoiceShortcutViewControllerDelegate {
    func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?) {
        if let voiceShortcut { added.append(voiceShortcut) }
        controller.dismiss(animated: false, completion: nil)
    }

    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
        cancels += 1
        controller.dismiss(animated: false, completion: nil)
    }
}

extension IntentsUITests.SiriUIViewController: INUIEditVoiceShortcutViewControllerDelegate {
    func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didUpdate voiceShortcut: INVoiceShortcut?, error: Error?) {
        if let voiceShortcut { updated.append(voiceShortcut) }
        controller.dismiss(animated: false, completion: nil)
    }

    func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didDeleteVoiceShortcutWithIdentifier deletedVoiceShortcutIdentifier: UUID) {
        deleted.append(deletedVoiceShortcutIdentifier)
        controller.dismiss(animated: false, completion: nil)
    }

    func editVoiceShortcutViewControllerDidCancel(_ controller: INUIEditVoiceShortcutViewController) {
        cancels += 1
        controller.dismiss(animated: false, completion: nil)
    }
}
