// EventKitUI (Sources/EventKitUI): the event viewer, editor and calendar chooser report to their
// delegates as Apple's do, the editor writes its fields into the event and keeps it when the
// page's store refuses to save, and the subclass shapes Clendar uses compile. EventKit's
// recurrence rules and structured locations ride along on the event.
import Testing
import CoreLocation
@testable import EventKitUI

@Suite @MainActor struct EventKitUITests {
    @MainActor final class Recorder: NSObject, EKEventEditViewDelegate, EKEventViewDelegate, EKCalendarChooserDelegate {
        var edits: [EKEventEditViewAction] = []
        var views: [EKEventViewAction] = []
        var changes = 0, finishes = 0, cancels = 0
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { edits.append(action) }
        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) { views.append(action) }
        func calendarChooserSelectionDidChange(_ calendarChooser: EKCalendarChooser) { changes += 1 }
        func calendarChooserDidFinish(_ calendarChooser: EKCalendarChooser) { finishes += 1 }
        func calendarChooserDidCancel(_ calendarChooser: EKCalendarChooser) { cancels += 1 }
    }

    // Clendar's shapes: a viewer with its own `init()`, an editor with its own designated
    // initializer, and a chooser that overrides UIKit's `init(nibName:bundle:)`.
    final class Viewer: EKEventViewController {
        init() { super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        convenience init(event: EKEvent) {
            self.init()
            self.event = event
        }
    }

    final class Editor: EKEventEditViewController {
        init(eventStore: EKEventStore, delegate: EKEventEditViewDelegate?) {
            super.init(nibName: nil, bundle: nil)
            self.eventStore = eventStore
            editViewDelegate = delegate
        }
        required init?(coder aDecoder: NSCoder) { super.init(coder: aDecoder) }
    }

    final class Chooser: EKCalendarChooser, EKCalendarChooserDelegate {
        var finished = false
        init(eventStore: EKEventStore) {
            super.init(selectionStyle: .multiple, displayStyle: .allCalendars, entityType: .event, eventStore: eventStore)
            delegate = self
        }
        override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
            super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        func calendarChooserDidFinish(_ calendarChooser: EKCalendarChooser) { finished = true }
    }

    private func event(_ store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = "Standup"
        event.startDate = Date(timeIntervalSince1970: 3600)
        event.endDate = Date(timeIntervalSince1970: 5400)
        event.notes = "Bring the numbers"
        let place = EKStructuredLocation(title: "Room 4")
        place.geoLocation = CLLocation(latitude: 42.13, longitude: -87.83)
        event.structuredLocation = place
        return event
    }

    @Test func theViewerShowsTheEventAndReportsDone() {
        let recorder = Recorder()
        let viewer = Viewer(event: event(EKEventStore()))
        viewer.delegate = recorder
        viewer.loadViewIfNeeded()
        #expect(viewer.titleLabel.text == "Standup")
        #expect(viewer.locationLabel.text == "Room 4" && !viewer.locationLabel.isHidden)
        #expect(viewer.notesLabel.text == "Bring the numbers" && !viewer.notesLabel.isHidden)
        #expect(viewer.calendarLabel.isHidden && !(viewer.timeLabel.text ?? "").isEmpty)
        #expect(viewer.navigationItem.rightBarButtonItem != nil)
        viewer._finish(.done)
        #expect(recorder.views == [.done])
    }

    @Test func theEditorWritesItsFieldsAndKeepsTheEventWhenTheStoreRefuses() {
        let recorder = Recorder()
        let store = EKEventStore()
        let editor = Editor(eventStore: store, delegate: recorder)
        let existing = event(store)
        editor.event = existing
        #expect(editor.form.titleField.text == "Standup" && (editor.form.locationField.text ?? "").isEmpty)
        #expect(editor.viewControllers.first === editor.form)

        editor.form.loadViewIfNeeded()
        #expect(editor.form.title == "Edit Event" && editor.form.navigationItem.leftBarButtonItem != nil)
        editor.form.titleField.text = "Planning"
        editor.form.allDaySwitch.isOn = true
        editor.form.write(into: existing)
        #expect(existing.title == "Planning" && existing.isAllDay && existing.notes == "Bring the numbers")

        // The page's store refuses to save, so the delegate hears nothing yet.
        editor._save()
        #expect(recorder.edits.isEmpty && editor.event === existing)
        #expect((editor.presentedViewController as? UIAlertController)?.title == "Can't Save Event")
        editor.dismiss(animated: false)
        editor.cancelEditing()
        #expect(recorder.edits == [.canceled])

        // A new event: the form starts empty, an hour long, and the delegate names its calendar.
        let blank = EKEventEditViewController()
        blank.eventStore = store
        blank.form.loadViewIfNeeded()
        #expect(blank.form.title == "New Event" && (blank.form.titleField.text ?? "").isEmpty)
        #expect(blank.form.endPicker.date.timeIntervalSince(blank.form.startPicker.date) == 3600)
        #expect(recorder.eventEditViewControllerDefaultCalendar(forNewEvents: blank).allowedEntityTypes == .event)
    }

    @Test func theChooserSelectsAndReports() {
        let store = EKEventStore()
        let chooser = Chooser(eventStore: store)
        #expect(chooser.calendars.isEmpty && chooser.selectionStyle == .multiple)
        let work = EKCalendar(for: .event, eventStore: store), home = EKCalendar(for: .event, eventStore: store)
        chooser._select(work)
        chooser._select(home)
        #expect(chooser.selectedCalendars == [work, home])
        chooser._select(work)
        #expect(chooser.selectedCalendars == [home])

        let recorder = Recorder()
        let single = EKCalendarChooser(selectionStyle: .single, displayStyle: .writableCalendarsOnly, entityType: .event, eventStore: store)
        single.delegate = recorder
        single.selectedCalendars = [work]
        single._select(home)
        #expect(single.selectedCalendars == [home] && recorder.changes == 1)
        single.showsDoneButton = true
        single.showsCancelButton = true
        #expect(single.navigationItem.rightBarButtonItem != nil && single.navigationItem.leftBarButtonItem != nil)
        single.loadViewIfNeeded()
        #expect(single.list.tableView.numberOfRows(inSection: 0) == 0)
        _ = Chooser(nibName: nil, bundle: nil)
    }

    @Test func eventsRepeatAndHavePlaces() {
        let event = event(EKEventStore())
        #expect(!event.hasRecurrenceRules)
        let weekly = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 10))
        event.addRecurrenceRule(weekly)
        #expect(event.hasRecurrenceRules && event.recurrenceRules?.first?.recurrenceEnd?.occurrenceCount == 10)
        event.removeRecurrenceRule(weekly)
        #expect(!event.hasRecurrenceRules)
        #expect(event.structuredLocation?.geoLocation?.coordinate.latitude == 42.13)
        #expect((event as NSObject).isEqual(event) && Notification.Name.EKEventStoreChanged.rawValue == "EKEventStoreChangedNotification")
    }
}
