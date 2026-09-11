// A settings screen in plain UIKit: a navigation controller over an inset grouped table with a
// switch and a slider row, a row that pushes a detail screen with a segmented control and a
// stepper, and a tab bar underneath. This file stays valid UIKit source apart from the two
// things UIKitWeb cannot offer without an Objective-C runtime (`#selector`, so actions are
// `UIAction`s, and `main()` creating the delegate with `init()`, so it is `final`).
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gear"), tag: 0)
        let about = UINavigationController(rootViewController: AboutViewController())
        about.tabBarItem = UITabBarItem(title: "About", image: UIImage(systemName: "info.circle"), tag: 1)
        let tabs = UITabBarController()
        tabs.viewControllers = [settings, about]
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class Preferences {
    var notifications = true
    var brightness: Float = 0.6
    var appearance = 0
    var fontSize = 3
}

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let preferences = Preferences()
    private var table: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Reset", primaryAction: UIAction { [weak self] _ in self?.confirmReset() })
        table = UITableView(frame: view.bounds, style: .insetGrouped)
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self
        view.addSubview(table)
    }

    /// An alert before the preferences go back to their defaults.
    private func confirmReset() {
        let alert = UIAlertController(title: "Reset settings?", message: "Every preference returns to its default.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            guard let self else { return }
            preferences.notifications = true
            preferences.brightness = 0.6
            preferences.appearance = 0
            preferences.fontSize = 3
            table.reloadData()
        })
        present(alert, animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 2 : 2 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "General" : "Display" }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { section == 1 ? "Brightness applies to this device only." : nil }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Notifications"
            let toggle = UISwitch()
            toggle.isOn = preferences.notifications
            toggle.addAction(UIAction { [weak self] action in self?.preferences.notifications = (action.sender as? UISwitch)?.isOn ?? true }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
            return cell
        case (0, 1):
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Appearance"
            cell.detailTextLabel?.text = ["Automatic", "Light", "Dark"][preferences.appearance]
            cell.accessoryType = .disclosureIndicator
            return cell
        case (1, 0):
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Brightness"
            let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 120, height: 34))
            slider.value = preferences.brightness
            slider.addAction(UIAction { [weak self] action in self?.preferences.brightness = (action.sender as? UISlider)?.value ?? 0 }, for: .valueChanged)
            cell.accessoryView = slider
            cell.selectionStyle = .none
            return cell
        default:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "Text Size"
            cell.detailTextLabel?.text = "\(preferences.fontSize)"
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath == IndexPath(row: 1, section: 0) {
            navigationController?.pushViewController(AppearanceViewController(preferences: preferences), animated: true)
        } else if indexPath == IndexPath(row: 1, section: 1) {
            navigationController?.pushViewController(TextSizeViewController(preferences: preferences), animated: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        table?.reloadData()
    }
}

final class AppearanceViewController: UIViewController {
    let preferences: Preferences
    init(preferences: Preferences) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
        title = "Appearance"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let control = UISegmentedControl(items: ["Automatic", "Light", "Dark"])
        control.selectedSegmentIndex = preferences.appearance
        control.addAction(UIAction { [weak self] action in self?.preferences.appearance = (action.sender as? UISegmentedControl)?.selectedSegmentIndex ?? 0 }, for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            control.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
    }
}

final class TextSizeViewController: UIViewController {
    let preferences: Preferences
    private let label = UILabel()
    init(preferences: Preferences) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
        title = "Text Size"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        let stepper = UIStepper()
        stepper.minimumValue = 1
        stepper.maximumValue = 7
        stepper.value = Double(preferences.fontSize)
        stepper.addAction(UIAction { [weak self] action in
            guard let self, let stepper = action.sender as? UIStepper else { return }
            self.preferences.fontSize = Int(stepper.value)
            self.label.text = "Size \(self.preferences.fontSize)"
        }, for: .valueChanged)
        label.text = "Size \(preferences.fontSize)"
        label.font = .preferredFont(forTextStyle: .title2)
        for control in [stepper, label] as [UIView] { control.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(control) }
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stepper.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stepper.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
        ])
    }
}

final class AboutViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "About"
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "UIKitWeb runs unmodified UIKit source in the browser."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
