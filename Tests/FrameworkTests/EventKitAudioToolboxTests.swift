// EventKit and AudioToolbox on the web: the event store answers as a person who declined access
// (not granted, no calendar, a save throws), and system sounds play silently and complete.
import Testing
import EventKit
import AudioToolbox
import WebFoundation

@Suite struct EventKitAudioToolboxTests {
    final class Answers: @unchecked Sendable { var granted: [Bool] = [] }

    @Test func eventStoreDeclinesAndSavingThrows() async throws {
        let store = EKEventStore()
        let answers = Answers()
        store.requestWriteOnlyAccessToEvents { granted, error in answers.granted.append(granted); #expect(error == nil) }
        store.requestAccess(to: .event) { granted, _ in answers.granted.append(granted) }
        #expect(answers.granted == [false, false])
        #expect(try await store.requestFullAccessToEvents() == false)
        #expect(EKEventStore.authorizationStatus(for: .event) == .denied)
        #expect(store.defaultCalendarForNewEvents == nil && store.calendars(for: .event).isEmpty)

        let event = EKEvent(eventStore: store)
        event.title = "Focus"
        event.startDate = Date(timeIntervalSince1970: 0)
        event.endDate = Date(timeIntervalSince1970: 1500)
        event.isAllDay = false
        event.calendar = store.defaultCalendarForNewEvents
        #expect(event.title == "Focus" && event.endDate.timeIntervalSince(event.startDate) == 1500)
        #expect(throws: EKError.self) { try store.save(event, span: .thisEvent) }

        // A query for a range of events (Shift's day view) matches none without access.
        let query = store.predicateForEvents(withStart: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400), calendars: nil)
        #expect(store.events(matching: query).isEmpty)
        var visited = 0
        store.enumerateEvents(matching: query) { _, _ in visited += 1 }
        #expect(visited == 0)
    }

    @Test func systemSoundsCompleteSilently() {
        final class Done: @unchecked Sendable { var count = 0 }
        let done = Done()
        AudioServicesPlaySystemSound(SystemSoundID(1002))
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSoundWithCompletion(1104) { done.count += 1 }
        AudioServicesPlayAlertSoundWithCompletion(1005) { done.count += 1 }
        #expect(done.count == 2 && kSystemSoundID_Vibrate == 4095)
    }
}
