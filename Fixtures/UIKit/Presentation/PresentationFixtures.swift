// Presentations (Docs/elements/UIKit/Presentation.md): an alert, an action sheet and a page sheet
// presented from a screen, captured with the whole window (they live beside the root controller's
// view), measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

@MainActor public final class PresentationModel {
    var presenter: UIViewController?
    var presented: UIViewController?
    public init() {}
}

final class PresentingController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Behind"
        label.font = .systemFont(ofSize: 17)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 16, y: 16)
        view.addSubview(label.probe("behind"))
    }
}

/// A screen with a button at a known place, the source of anchored presentations.
final class SourceController: UIViewController {
    let button = UIButton(type: .system)
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        button.setTitle("Options", for: .normal)
        button.frame = CGRect(x: 110, y: 300, width: 100, height: 44)
        view.addSubview(button.probe("source"))
    }
}

/// Lets a popover stay a popover on the iPhone (the default adapts it to a sheet).
final class PopoverKeeper: NSObject, UIPopoverPresentationControllerDelegate {
    static let shared = PopoverKeeper()
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
}

public enum PresentationFixtures {
    public static let all = [alert, actionSheet, pageSheet, alertField, alertFields, mediumSheet, anchoredSheet, popover, adaptedPopover]

    /// A presented controller at the medium detent with the grabber (uk-sheets).
    public static let mediumSheet = UIKitFixture("uikit/sheet/medium", size: CGSize(width: 320, height: 500),
                                                 model: { PresentationModel() },
                                                 steps: [UIKitFixtureStep("present") { model in
                                                             let presented = UIViewController()
                                                             presented.view.backgroundColor = .systemGroupedBackground
                                                             let label = UILabel()
                                                             label.text = "Presented"
                                                             label.font = .systemFont(ofSize: 17)
                                                             label.sizeToFit()
                                                             label.frame.origin = CGPoint(x: 16, y: 16)
                                                             presented.view.addSubview(label.probe("presentedLabel"))
                                                             if let sheet = presented.sheetPresentationController {
                                                                 sheet.detents = [.medium(), .large()]
                                                                 sheet.prefersGrabberVisible = true
                                                             }
                                                             model.presenter?.present(presented, animated: false)
                                                             model.presented = presented
                                                             presented.view.probe("presented")
                                                         }],
                                                 controller: { model in
        let controller = PresentingController()
        model.presenter = controller
        return controller
    }).capturesWindow()

    /// An action sheet anchored to a button (its popover presentation controller's source).
    public static let anchoredSheet = UIKitFixture("uikit/alert/anchored", size: CGSize(width: 320, height: 500),
                                                   model: { PresentationModel() },
                                                   steps: [UIKitFixtureStep("present") { model in
                                                               guard let source = model.presenter as? SourceController else { return }
                                                               let sheet = UIAlertController(title: "Share", message: nil, preferredStyle: .actionSheet)
                                                               sheet.addAction(UIAlertAction(title: "Copy Link", style: .default))
                                                               sheet.addAction(UIAlertAction(title: "Save Image", style: .default))
                                                               sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                                                               sheet.popoverPresentationController?.sourceView = source.button
                                                               sheet.popoverPresentationController?.sourceRect = source.button.bounds
                                                               source.present(sheet, animated: false)
                                                               model.presented = sheet
                                                               sheet.view.probe("sheet")
                                                           }],
                                                   controller: { model in
        let controller = SourceController()
        model.presenter = controller
        return controller
    }).capturesWindow()

    /// A popover kept a popover on the iPhone: an arrowed panel of its preferred content size.
    public static let popover = UIKitFixture("uikit/popover/basic", size: CGSize(width: 320, height: 500),
                                             model: { PresentationModel() },
                                             steps: [UIKitFixtureStep("present") { model in
                                                         guard let source = model.presenter as? SourceController else { return }
                                                         let presented = UIViewController()
                                                         presented.view.backgroundColor = .systemBackground
                                                         presented.preferredContentSize = CGSize(width: 240, height: 120)
                                                         presented.modalPresentationStyle = .popover
                                                         let label = UILabel()
                                                         label.text = "Popover"
                                                         label.font = .systemFont(ofSize: 17)
                                                         label.sizeToFit()
                                                         label.frame.origin = CGPoint(x: 16, y: 16)
                                                         presented.view.addSubview(label.probe("popoverLabel"))
                                                         presented.popoverPresentationController?.sourceView = source.button
                                                         presented.popoverPresentationController?.sourceRect = source.button.bounds
                                                         presented.popoverPresentationController?.permittedArrowDirections = .down
                                                         presented.popoverPresentationController?.delegate = PopoverKeeper.shared
                                                         source.present(presented, animated: false)
                                                         model.presented = presented
                                                         presented.view.probe("popover")
                                                     }],
                                             controller: { model in
        let controller = SourceController()
        model.presenter = controller
        return controller
    }).capturesWindow()

    /// A popover left to adapt on the iPhone (a sheet).
    public static let adaptedPopover = UIKitFixture("uikit/popover/adapted", size: CGSize(width: 320, height: 500),
                                                    model: { PresentationModel() },
                                                    steps: [UIKitFixtureStep("present") { model in
                                                                guard let source = model.presenter as? SourceController else { return }
                                                                let presented = UIViewController()
                                                                presented.view.backgroundColor = .systemBackground
                                                                presented.preferredContentSize = CGSize(width: 240, height: 120)
                                                                presented.modalPresentationStyle = .popover
                                                                let label = UILabel()
                                                                label.text = "Popover"
                                                                label.font = .systemFont(ofSize: 17)
                                                                label.sizeToFit()
                                                                label.frame.origin = CGPoint(x: 16, y: 16)
                                                                presented.view.addSubview(label.probe("popoverLabel"))
                                                                presented.popoverPresentationController?.sourceView = source.button
                                                                presented.popoverPresentationController?.sourceRect = source.button.bounds
                                                                source.present(presented, animated: false)
                                                                model.presented = presented
                                                                presented.view.probe("popover")
                                                            }],
                                                    controller: { model in
        let controller = SourceController()
        model.presenter = controller
        return controller
    }).capturesWindow()

    /// An alert with a title, a message, a cancel action and a destructive one.
    public static let alert = UIKitFixture("uikit/alert/basic", size: CGSize(width: 320, height: 500),
                                           model: { PresentationModel() },
                                           steps: [UIKitFixtureStep("present") { model in
                                                       let alert = UIAlertController(title: "Delete file?", message: "This cannot be undone.", preferredStyle: .alert)
                                                       alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                                                       alert.addAction(UIAlertAction(title: "Delete", style: .destructive))
                                                       model.presenter?.present(alert, animated: false)
                                                       model.presented = alert
                                                       alert.view.probe("alert")
                                                   },
                                                   UIKitFixtureStep("dismiss") { model in model.presented?.dismiss(animated: false) }],
                                           controller: { model in
        let controller = PresentingController()
        model.presenter = controller
        return controller
    }).capturesWindow()

    /// An alert with one text field (a rename prompt).
    public static let alertField = UIKitFixture("uikit/alert/textfield", size: CGSize(width: 320, height: 500),
                                                model: { PresentationModel() },
                                                steps: [UIKitFixtureStep("present") { model in
                                                            let alert = UIAlertController(title: "Rename", message: "Enter a new name for the file.", preferredStyle: .alert)
                                                            alert.addTextField { field in field.placeholder = "Name" }
                                                            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                                                            alert.addAction(UIAlertAction(title: "Save", style: .default))
                                                            model.presenter?.present(alert, animated: false)
                                                            model.presented = alert
                                                            alert.view.probe("alert")
                                                            alert.textFields?.first?.probe("field")
                                                        }],
                                                controller: { model in
        let controller = PresentingController()
        model.presenter = controller
        return controller
    }).capturesWindow()

    /// An alert with two text fields (a sign-in prompt), the second secure with text.
    public static let alertFields = UIKitFixture("uikit/alert/textfields", size: CGSize(width: 320, height: 500),
                                                 model: { PresentationModel() },
                                                 steps: [UIKitFixtureStep("present") { model in
                                                             let alert = UIAlertController(title: "Sign In", message: nil, preferredStyle: .alert)
                                                             alert.addTextField { field in field.placeholder = "Username"; field.text = "corey" }
                                                             alert.addTextField { field in field.placeholder = "Password"; field.isSecureTextEntry = true }
                                                             alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                                                             alert.addAction(UIAlertAction(title: "Sign In", style: .default))
                                                             alert.addAction(UIAlertAction(title: "Forgot Password", style: .default))
                                                             model.presenter?.present(alert, animated: false)
                                                             model.presented = alert
                                                             alert.view.probe("alert")
                                                             alert.textFields?[0].probe("username")
                                                             alert.textFields?[1].probe("password")
                                                         }],
                                                 controller: { model in
        let controller = PresentingController()
        model.presenter = controller
        return controller
    }).capturesWindow()

    /// An action sheet with two actions and cancel.
    public static let actionSheet = UIKitFixture("uikit/alert/sheet", size: CGSize(width: 320, height: 500),
                                                 model: { PresentationModel() },
                                                 steps: [UIKitFixtureStep("present") { model in
                                                             let sheet = UIAlertController(title: "Share", message: nil, preferredStyle: .actionSheet)
                                                             sheet.addAction(UIAlertAction(title: "Copy Link", style: .default))
                                                             sheet.addAction(UIAlertAction(title: "Save Image", style: .default))
                                                             sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                                                             model.presenter?.present(sheet, animated: false)
                                                             model.presented = sheet
                                                             sheet.view.probe("sheet")
                                                         }],
                                                 controller: { model in
        let controller = PresentingController()
        model.presenter = controller
        return controller
    }).capturesWindow()

    /// A view controller presented as a page sheet (the iPhone default).
    public static let pageSheet = UIKitFixture("uikit/sheet/page", size: CGSize(width: 320, height: 500),
                                               model: { PresentationModel() },
                                               steps: [UIKitFixtureStep("present") { model in
                                                           let presented = UIViewController()
                                                           presented.view.backgroundColor = .systemGroupedBackground
                                                           let label = UILabel()
                                                           label.text = "Presented"
                                                           label.font = .systemFont(ofSize: 17)
                                                           label.sizeToFit()
                                                           label.frame.origin = CGPoint(x: 16, y: 16)
                                                           presented.view.addSubview(label.probe("presentedLabel"))
                                                           model.presenter?.present(presented, animated: false)
                                                           model.presented = presented
                                                           presented.view.probe("presented")
                                                       }],
                                               controller: { model in
        let controller = PresentingController()
        model.presenter = controller
        return controller
    }).capturesWindow()
}
#endif
