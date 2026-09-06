// The classic counter in UIKit. This file must stay valid UIKit source, apart from two things
// there is no Objective-C runtime for: `#selector` has no equivalent (UIKitWeb accepts
// `UIAction`, the iOS 14 form), and `main()` creates the delegate with `init()`, which a
// non-final class can only promise with `required init()`, so the delegate is `final`.
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = CounterViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class CounterViewController: UIViewController {
    private var count = 0 {
        didSet { label.text = "Count: \(count)" }
    }
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.text = "Count: 0"
        label.font = .preferredFont(forTextStyle: .title1)
        label.textAlignment = .center

        let minus = UIButton(type: .system, primaryAction: UIAction(title: "−") { [weak self] _ in self?.count -= 1 })
        let plus = UIButton(type: .system, primaryAction: UIAction(title: "+") { [weak self] _ in self?.count += 1 })
        let buttons = UIStackView(arrangedSubviews: [minus, plus])
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [label, buttons])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        view.addSubview(stack)
        self.stack = stack
    }

    private var stack: UIStackView?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let stack else { return }
        let size = stack.sizeThatFits(view.bounds.size)
        stack.frame = CGRect(x: (view.bounds.width - size.width) / 2, y: (view.bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
}
