// EventKitUI on the web (Docs/support.json, "EventKitUI"): the system's event viewer, event
// editor and calendar chooser as UIKit controllers built from UIKitWeb's views, with the delegate
// calls Apple's make. A page's event store reaches no calendars (Sources/EventKit), so the
// chooser lists none, and the editor's Add asks the store to save, which refuses: the editor says
// so and stays open, as one for an app without access does. Apple's framework re-exports EventKit
// and UIKit, so a file importing only it names `EKEvent` and `UIViewController`.
@_exported import EventKit
@_exported import UIKit

// MARK: - Event viewer

/// What ended an event viewer.
public enum EKEventViewAction: Int, Sendable {
    case done = 0, responded, deleted
}

@MainActor public protocol EKEventViewDelegate: AnyObject {
    func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction)
}

/// Shows an event: its title, when it is, where, its calendar and its notes, with a Done button
/// that reports `.done` to the delegate.
open class EKEventViewController: UIViewController {
    open var event: EKEvent! { didSet { if isViewLoaded { _reload() } } }
    open var allowsEditing = true
    open var allowsCalendarPreview = false
    open weak var delegate: (any EKEventViewDelegate)?

    let titleLabel = UILabel(), timeLabel = UILabel(), locationLabel = UILabel()
    let calendarLabel = UILabel(), notesLabel = UILabel()
    private lazy var stack = UIStackView(arrangedSubviews: [titleLabel, timeLabel, locationLabel, calendarLabel, notesLabel])

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.font = .boldSystemFont(ofSize: 22)
        for label in [titleLabel, timeLabel, locationLabel, calendarLabel, notesLabel] { label.numberOfLines = 0 }
        for label in [timeLabel, locationLabel, calendarLabel] { label.textColor = .secondaryLabel }
        stack.axis = .vertical
        stack.spacing = 8
        view.addSubview(stack)
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?._finish(.done)
        })
        _reload()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let area = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 20, dy: 16)
        let fitted = stack.systemLayoutSizeFitting(CGSize(width: area.width, height: 0),
                                                   withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: area.minX, y: area.minY, width: area.width, height: min(fitted.height, area.height))
    }

    func _reload() {
        titleLabel.text = event?.title
        timeLabel.text = event.map(_EventText.when)
        locationLabel.text = event?.structuredLocation?.title ?? event?.location
        locationLabel.isHidden = locationLabel.text?.isEmpty ?? true
        calendarLabel.text = event?.calendar?.title
        calendarLabel.isHidden = calendarLabel.text?.isEmpty ?? true
        notesLabel.text = event?.notes
        notesLabel.isHidden = !(event?.hasNotes ?? false)
        view.setNeedsLayout()
    }

    func _finish(_ action: EKEventViewAction) {
        delegate?.eventViewController(self, didCompleteWith: action)
    }
}

/// The line under an event's title: its day and times, or its days when it is all day.
enum _EventText {
    static func when(_ event: EKEvent) -> String {
        let day = DateFormatter()
        day.dateStyle = .medium
        guard let start = event.startDate else { return "" }
        if event.isAllDay { return day.string(from: start) }
        let time = DateFormatter()
        time.timeStyle = .short
        guard let end = event.endDate else { return "\(day.string(from: start)), \(time.string(from: start))" }
        return "\(day.string(from: start)), \(time.string(from: start)) to \(time.string(from: end))"
    }
}

// MARK: - Event editor

/// What ended an event editor.
public enum EKEventEditViewAction: Int, Sendable {
    case canceled = 0, saved, deleted
}

@MainActor public protocol EKEventEditViewDelegate: AnyObject {
    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction)
    /// The calendar a new event goes in.
    func eventEditViewControllerDefaultCalendar(forNewEvents controller: EKEventEditViewController) -> EKCalendar
}

extension EKEventEditViewDelegate {
    public func eventEditViewControllerDefaultCalendar(forNewEvents controller: EKEventEditViewController) -> EKCalendar {
        let store = controller.eventStore ?? EKEventStore()
        return store.defaultCalendarForNewEvents ?? EKCalendar(for: .event, eventStore: store)
    }
}

/// Edits an event, or a new one when none is set, in a navigation controller: title, location,
/// all day, start, end and notes, with Cancel and Add (Done for an existing event). Add writes
/// the fields into the event and saves it to the store, then reports `.saved`; when the store
/// refuses, as a page's does, an alert says so and the editor stays.
open class EKEventEditViewController: UINavigationController {
    open var eventStore: EKEventStore!
    open var event: EKEvent? { didSet { form.load(event) } }
    open weak var editViewDelegate: (any EKEventEditViewDelegate)?
    let form = _EventForm()

    public override init(nibName: String? = nil, bundle: Bundle? = nil) {
        super.init(nibName: nibName, bundle: bundle)
        form.editor = self
        setViewControllers([form], animated: false)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        form.editor = self
        setViewControllers([form], animated: false)
    }

    public convenience init() { self.init(nibName: nil, bundle: nil) }

    /// Ends editing without saving, reporting `.canceled`.
    open func cancelEditing() { _finish(.canceled) }

    func _save() {
        let store = eventStore ?? EKEventStore()
        let target = event ?? EKEvent(eventStore: store)
        // A refused save keeps the draft in the form but leaves the caller's event as it was.
        let before = _EventFields(target)
        form.write(into: target)
        if target.calendar == nil, let delegate = editViewDelegate {
            target.calendar = delegate.eventEditViewControllerDefaultCalendar(forNewEvents: self)
        }
        do {
            try store.save(target, span: .thisEvent)
            event = target
            _finish(.saved)
        } catch {
            before.restore(into: target)
            let alert = UIAlertController(title: "Can't Save Event", message: "This page can't reach your calendars.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            present(alert, animated: true)
        }
    }

    func _finish(_ action: EKEventEditViewAction) {
        editViewDelegate?.eventEditViewController(self, didCompleteWith: action)
    }
}

/// The properties the editor's form writes, kept so a refused save can put them back.
struct _EventFields {
    let title: String?, location: String?, notes: String?
    let isAllDay: Bool
    let startDate: Date?, endDate: Date?
    let calendar: EKCalendar?

    init(_ event: EKEvent) {
        title = event.title; location = event.location; notes = event.notes
        isAllDay = event.isAllDay
        startDate = event.startDate; endDate = event.endDate
        calendar = event.calendar
    }

    func restore(into event: EKEvent) {
        event.title = title; event.location = location; event.notes = notes
        event.isAllDay = isAllDay
        event.startDate = startDate; event.endDate = endDate
        event.calendar = calendar
    }
}

/// The editor's form: one field per property, in a vertical stack.
final class _EventForm: UIViewController {
    weak var editor: EKEventEditViewController?
    let titleField = UITextField(), locationField = UITextField()
    let allDaySwitch = UISwitch(), startPicker = UIDatePicker(), endPicker = UIDatePicker()
    let notesView = UITextView()
    private var isNew = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        titleField.placeholder = "Title"
        locationField.placeholder = "Location"
        let allDayLabel = UILabel()
        allDayLabel.text = "All-day"
        let allDay = UIStackView(arrangedSubviews: [allDayLabel, allDaySwitch])
        allDaySwitch.addAction(UIAction { [weak self] _ in self?.allDayChanged() }, for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [titleField, locationField, allDay, startPicker, endPicker, notesView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.tag = 1
        view.addSubview(stack)
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.editor?.cancelEditing()
        })
        load(editor?.event)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let stack = view.viewWithTag(1) else { return }
        stack.frame = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 16, dy: 16)
    }

    func load(_ event: EKEvent?) {
        isNew = event == nil
        titleField.text = event?.title
        locationField.text = event?.location
        allDaySwitch.isOn = event?.isAllDay ?? false
        let start = event?.startDate ?? Date()
        startPicker.date = start
        endPicker.date = event?.endDate ?? start.addingTimeInterval(3600)
        notesView.text = event?.notes ?? ""
        allDayChanged()
        updateTitle()
    }

    func write(into event: EKEvent) {
        event.title = titleField.text ?? ""
        event.location = (locationField.text?.isEmpty ?? true) ? nil : locationField.text
        event.isAllDay = allDaySwitch.isOn
        event.startDate = startPicker.date
        event.endDate = max(endPicker.date, startPicker.date)
        event.notes = notesView.text.isEmpty ? nil : notesView.text
    }

    private func allDayChanged() {
        let mode: UIDatePicker.Mode = allDaySwitch.isOn ? .date : .dateAndTime
        startPicker.datePickerMode = mode
        endPicker.datePickerMode = mode
    }

    private func updateTitle() {
        title = isNew ? "New Event" : "Edit Event"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: isNew ? "Add" : "Done", primaryAction: UIAction { [weak self] _ in
            self?.editor?._save()
        })
    }
}

// MARK: - Calendar chooser

extension EKCalendarChooser {
    /// Whether the person picks one calendar or several.
    public enum SelectionStyle: Int, Sendable { case single = 0, multiple }
    /// Which calendars the chooser lists.
    public enum DisplayStyle: Int, Sendable { case allCalendars = 0, writableCalendarsOnly }
}

public typealias EKCalendarChooserSelectionStyle = EKCalendarChooser.SelectionStyle
public typealias EKCalendarChooserDisplayStyle = EKCalendarChooser.DisplayStyle

@MainActor public protocol EKCalendarChooserDelegate: AnyObject {
    func calendarChooserSelectionDidChange(_ calendarChooser: EKCalendarChooser)
    func calendarChooserDidFinish(_ calendarChooser: EKCalendarChooser)
    func calendarChooserDidCancel(_ calendarChooser: EKCalendarChooser)
}

extension EKCalendarChooserDelegate {
    public func calendarChooserSelectionDidChange(_ calendarChooser: EKCalendarChooser) {}
    public func calendarChooserDidFinish(_ calendarChooser: EKCalendarChooser) {}
    public func calendarChooserDidCancel(_ calendarChooser: EKCalendarChooser) {}
}

/// Lists the store's calendars with a checkmark on each selected one; a tap selects (single) or
/// toggles (multiple) and reports the change, and Done and Cancel, when shown, report to the
/// delegate. A page's store has no calendars, so the list is empty.
open class EKCalendarChooser: UIViewController {
    public let selectionStyle: SelectionStyle
    public let displayStyle: DisplayStyle
    public let entityType: EKEntityType
    let eventStore: EKEventStore?
    open var selectedCalendars: Set<EKCalendar> = [] { didSet { if list.isViewLoaded { list.tableView.reloadData() } } }
    open var showsDoneButton = false { didSet { updateButtons() } }
    open var showsCancelButton = false { didSet { updateButtons() } }
    open weak var delegate: (any EKCalendarChooserDelegate)?
    let list = _CalendarList(style: .insetGrouped)

    public init(selectionStyle style: SelectionStyle, displayStyle: DisplayStyle, entityType: EKEntityType = .event, eventStore: EKEventStore) {
        selectionStyle = style
        self.displayStyle = displayStyle
        self.entityType = entityType
        self.eventStore = eventStore
        super.init(nibName: nil, bundle: nil)
        list.chooser = self
    }

    public override init(nibName: String? = nil, bundle: Bundle? = nil) {
        selectionStyle = .single
        displayStyle = .allCalendars
        entityType = .event
        eventStore = nil
        super.init(nibName: nibName, bundle: bundle)
        list.chooser = self
    }

    public required init?(coder: NSCoder) {
        selectionStyle = .single
        displayStyle = .allCalendars
        entityType = .event
        eventStore = nil
        super.init(coder: coder)
        list.chooser = self
    }

    /// The calendars the list shows: the store's, or only those that take changes.
    var calendars: [EKCalendar] {
        let all = eventStore?.calendars(for: entityType) ?? []
        return displayStyle == .writableCalendarsOnly ? all.filter(\.allowsContentModifications) : all
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        addChild(list)
        view.addSubview(list.view)
        list.didMove(toParent: self)
        updateButtons()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        list.view.frame = view.bounds
    }

    func _select(_ calendar: EKCalendar) {
        if selectionStyle == .single {
            selectedCalendars = [calendar]
        } else if selectedCalendars.contains(calendar) {
            selectedCalendars.remove(calendar)
        } else {
            selectedCalendars.insert(calendar)
        }
        delegate?.calendarChooserSelectionDidChange(self)
    }

    private func updateButtons() {
        navigationItem.rightBarButtonItem = showsDoneButton ? UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.calendarChooserDidFinish(self)
        }) : nil
        navigationItem.leftBarButtonItem = showsCancelButton ? UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.calendarChooserDidCancel(self)
        }) : nil
    }
}

/// The chooser's table: one row per calendar, checked when selected.
final class _CalendarList: UITableViewController {
    weak var chooser: EKCalendarChooser?

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { chooser?.calendars.count ?? 0 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        guard let chooser, indexPath.row < chooser.calendars.count else { return cell }
        let calendar = chooser.calendars[indexPath.row]
        cell.textLabel?.text = calendar.title
        cell.accessoryType = chooser.selectedCalendars.contains(calendar) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let chooser, indexPath.row < chooser.calendars.count else { return }
        chooser._select(chooser.calendars[indexPath.row])
    }
}
