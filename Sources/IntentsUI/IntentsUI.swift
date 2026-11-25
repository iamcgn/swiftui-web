// IntentsUI on the web (Docs/support.json, "IntentsUI"): the Add to Siri button and the sheets
// it asks the app to present, as UIKit views and controllers built from UIKitWeb's. A page has
// no Siri, so the add sheet says the phrase can't be spoken to Siri here; Add keeps it with
// Intents' `INVoiceShortcutCenter` for as long as the page is open, and the delegate calls are
// Apple's, so the app's flow finishes and its button shows the phrase. Apple's framework
// re-exports Intents and UIKit, so a file importing only it names `INShortcut` and `UIButton`.
@_exported import Intents
@_exported import UIKit

// MARK: - Add to Siri button

/// The Add to Siri button's look.
public enum INUIAddVoiceShortcutButtonStyle: UInt, Sendable {
    case white = 0, whiteOutline, black, blackOutline, automatic, automaticOutline
}

@MainActor public protocol INUIAddVoiceShortcutButtonDelegate: AnyObject {
    /// The button was pressed for a shortcut without a phrase: present the add sheet.
    func present(_ addVoiceShortcutViewController: INUIAddVoiceShortcutViewController, for addVoiceShortcutButton: INUIAddVoiceShortcutButton)
    /// The button was pressed for a shortcut with a phrase: present the edit sheet.
    func present(_ editVoiceShortcutViewController: INUIEditVoiceShortcutViewController, for addVoiceShortcutButton: INUIAddVoiceShortcutButton)
}

/// "Add to Siri", or the recorded phrase once the shortcut has one. Pressing it hands the
/// delegate the add or the edit sheet for the shortcut.
open class INUIAddVoiceShortcutButton: UIButton {
    open var shortcut: INShortcut? { didSet { _refresh() } }
    open weak var delegate: (any INUIAddVoiceShortcutButtonDelegate)?
    public private(set) var style: INUIAddVoiceShortcutButtonStyle
    open var cornerRadius: CGFloat = 8 { didSet { layer.cornerRadius = cornerRadius } }

    public init(style: INUIAddVoiceShortcutButtonStyle) {
        self.style = style
        super.init(type: .custom)
        layer.cornerRadius = cornerRadius
        contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        addAction(UIAction { [weak self] _ in self?._pressed() }, for: .primaryActionTriggered)
        _restyle()
        _refresh()
    }

    public required init?(coder: NSCoder) { return nil }

    open func setStyle(_ style: INUIAddVoiceShortcutButtonStyle) {
        self.style = style
        _restyle()
    }

    /// The phrase the shortcut was recorded with, if it was.
    var _voiceShortcut: INVoiceShortcut? { shortcut.flatMap(INVoiceShortcutCenter.shared._voiceShortcut(for:)) }

    func _refresh() {
        if let phrase = _voiceShortcut?.invocationPhrase {
            setTitle("\u{201C}\(phrase)\u{201D}", for: .normal)
            accessibilityHint = "Edits the phrase"
        } else {
            setTitle("Add to Siri", for: .normal)
            accessibilityHint = nil
        }
        invalidateIntrinsicContentSize()
    }

    func _restyle() {
        let dark: Bool = switch style {
        case .black, .blackOutline: true
        case .white, .whiteOutline: false
        case .automatic, .automaticOutline: traitCollection.userInterfaceStyle == .dark
        }
        let outlined = style == .whiteOutline || style == .blackOutline || style == .automaticOutline
        backgroundColor = dark ? .black : .white
        setTitleColor(dark ? .white : .black, for: .normal)
        layer.borderWidth = outlined ? 1 : 0
        layer.borderColor = (dark ? UIColor.white : UIColor.black).cgColor
    }

    func _pressed() {
        guard let shortcut else { return }
        if let voiceShortcut = _voiceShortcut {
            let editor = INUIEditVoiceShortcutViewController(voiceShortcut: voiceShortcut)
            editor._button = self
            delegate?.present(editor, for: self)
        } else {
            let adder = INUIAddVoiceShortcutViewController(shortcut: shortcut)
            adder._button = self
            delegate?.present(adder, for: self)
        }
    }
}

// MARK: - Add sheet

@MainActor public protocol INUIAddVoiceShortcutViewControllerDelegate: AnyObject {
    func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: (any Error)?)
    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController)
}

/// Records a phrase for a shortcut: the phrase in a field, prefilled with the app's suggestion,
/// a line saying Siri can't hear it on this page, and Cancel and Add.
open class INUIAddVoiceShortcutViewController: UIViewController {
    open weak var delegate: (any INUIAddVoiceShortcutViewControllerDelegate)?
    public let _shortcut: INShortcut
    let _sheet = _PhraseSheet()
    weak var _button: INUIAddVoiceShortcutButton?

    public init(shortcut: INShortcut) {
        _shortcut = shortcut
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        _sheet.title = "Add to Siri"
        _sheet.phraseField.text = shortcut._suggestedPhrase
        _sheet.confirmTitle = "Add"
        _sheet.onCancel = { [weak self] in self?._cancel() }
        _sheet.onConfirm = { [weak self] in self?._add() }
    }

    public required init?(coder: NSCoder) { return nil }

    open override func viewDidLoad() {
        super.viewDidLoad()
        _sheet.embed(in: self)
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _sheet.navigation?.view.frame = view.bounds
    }

    func _add() {
        let phrase = (_sheet.phraseField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        let added = INVoiceShortcutCenter.shared._add(phrase, for: _shortcut)
        _button?._refresh()
        delegate?.addVoiceShortcutViewController(self, didFinishWith: added, error: nil)
    }

    func _cancel() { delegate?.addVoiceShortcutViewControllerDidCancel(self) }
}

// MARK: - Edit sheet

@MainActor public protocol INUIEditVoiceShortcutViewControllerDelegate: AnyObject {
    func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didUpdate voiceShortcut: INVoiceShortcut?, error: (any Error)?)
    func editVoiceShortcutViewController(_ controller: INUIEditVoiceShortcutViewController, didDeleteVoiceShortcutWithIdentifier deletedVoiceShortcutIdentifier: UUID)
    func editVoiceShortcutViewControllerDidCancel(_ controller: INUIEditVoiceShortcutViewController)
}

/// Changes or deletes a recorded phrase: the phrase in a field, Delete Phrase, Cancel and Done.
open class INUIEditVoiceShortcutViewController: UIViewController {
    open weak var delegate: (any INUIEditVoiceShortcutViewControllerDelegate)?
    public let _voiceShortcut: INVoiceShortcut
    let _sheet = _PhraseSheet()
    weak var _button: INUIAddVoiceShortcutButton?

    public init(voiceShortcut: INVoiceShortcut) {
        _voiceShortcut = voiceShortcut
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        _sheet.title = "Edit Phrase"
        _sheet.phraseField.text = voiceShortcut.invocationPhrase
        _sheet.confirmTitle = "Done"
        _sheet.deleteButton.isHidden = false
        _sheet.onCancel = { [weak self] in self?._cancel() }
        _sheet.onConfirm = { [weak self] in self?._update() }
        _sheet.onDelete = { [weak self] in self?._delete() }
    }

    public required init?(coder: NSCoder) { return nil }

    open override func viewDidLoad() {
        super.viewDidLoad()
        _sheet.embed(in: self)
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        _sheet.navigation?.view.frame = view.bounds
    }

    func _update() {
        let phrase = (_sheet.phraseField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        let updated = INVoiceShortcutCenter.shared._add(phrase, for: _voiceShortcut.shortcut)
        _button?._refresh()
        delegate?.editVoiceShortcutViewController(self, didUpdate: updated, error: nil)
    }

    func _delete() {
        INVoiceShortcutCenter.shared._remove(_voiceShortcut.identifier)
        _button?._refresh()
        delegate?.editVoiceShortcutViewController(self, didDeleteVoiceShortcutWithIdentifier: _voiceShortcut.identifier)
    }

    func _cancel() { delegate?.editVoiceShortcutViewControllerDidCancel(self) }
}

// MARK: - The sheets' form

/// The add and edit sheets' content: a navigation bar with Cancel and the confirm button over
/// the phrase field, the line about Siri and, for the edit sheet, Delete Phrase.
@MainActor final class _PhraseSheet: UIViewController {
    let phraseField = UITextField()
    let note = UILabel()
    let deleteButton = UIButton(type: .system)
    var confirmTitle = "Add" { didSet { _setConfirmItem() } }
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}
    var onDelete: () -> Void = {}
    /// The navigation controller the sheet sits in, which the presented controller owns.
    private(set) weak var navigation: UINavigationController?
    private lazy var stack = UIStackView(arrangedSubviews: [phraseField, note, deleteButton])

    /// Puts the sheet, in its navigation controller, inside the presented controller.
    func embed(in parent: UIViewController) {
        let navigation = UINavigationController(rootViewController: self)
        self.navigation = navigation
        parent.addChild(navigation)
        parent.view.addSubview(navigation.view)
        navigation.view.frame = parent.view.bounds
        navigation.didMove(toParent: parent)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        phraseField.borderStyle = .roundedRect
        phraseField.placeholder = "Phrase"
        phraseField.clearButtonMode = .whileEditing
        note.text = "Siri isn't available in this browser, so this phrase is kept for the app while the page is open."
        note.font = .systemFont(ofSize: 13)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        deleteButton.setTitle("Delete Phrase", for: .normal)
        deleteButton.setTitleColor(.systemRed, for: .normal)
        deleteButton.addAction(UIAction { [weak self] _ in self?.onDelete() }, for: .primaryActionTriggered)
        stack.axis = .vertical
        stack.spacing = 12
        view.addSubview(stack)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let area = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 20, dy: 20)
        let fitted = stack.systemLayoutSizeFitting(CGSize(width: area.width, height: 0),
                                                   withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: area.minX, y: area.minY, width: area.width, height: min(fitted.height, area.height))
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        deleteButton.isHidden = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.onCancel()
        })
        _setConfirmItem()
    }

    private func _setConfirmItem() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: confirmTitle, primaryAction: UIAction { [weak self] _ in
            self?.onConfirm()
        })
    }

    required init?(coder: NSCoder) { return nil }
}
