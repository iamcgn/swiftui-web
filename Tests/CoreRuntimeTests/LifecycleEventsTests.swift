// Phase 8 step 6, sw-lifecycle: onReceive over the Combine-free publishers, the scene phase
// from the host's visibility and focus, onOpenURL and onContinueUserActivity, appear order
// (Docs/elements/Lifecycle.md).
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Log { var entries: [String] = [] }

private final class Counter: ObservableObject {
    @Published var count = 0
}

@Suite @MainActor struct LifecycleEventsTests {
    private static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for word in ["active", "inactive", "background", "Hi"] {
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: 40, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Test func onReceiveDeliversSubjectsNotificationsAndPublishedValues() async {
        let log = Log()
        let subject = PassthroughSubject<Int, Never>()
        let current = CurrentValueSubject<String, Never>("a")
        let counter = Counter()
        let name = Notification.Name("swiftuiweb.test")
        let runtime = runtime(Text("Hi")
            .onReceive(subject) { log.entries.append("subject \($0)") }
            .onReceive(current) { log.entries.append("current \($0)") }
            .onReceive(Just(7)) { log.entries.append("just \($0)") }
            .onReceive(NotificationCenter.default.publisher(for: name)) { log.entries.append("note \($0.name.rawValue)") }
            .onReceive(counter.$count) { log.entries.append("count \($0)") }
            .onReceive(counter.objectWillChange) { _ in log.entries.append("will change") })
        // Subscriptions are made after the mount: the current value and the Just arrive at once.
        #expect(log.entries.contains("current a") && log.entries.contains("just 7") && log.entries.contains("count 0"))
        subject.send(3)
        current.send("b")
        NotificationCenter.default.post(name: name, object: nil)
        counter.count = 5
        await Task.yield()
        await Task.yield()
        #expect(log.entries.contains("subject 3") && log.entries.contains("current b") && log.entries.contains("note swiftuiweb.test"))
        #expect(log.entries.contains("will change") && log.entries.contains("count 5"))
        // Unmounting ends the subscriptions.
        runtime.mount(Text("Hi"))
        runtime.layout(in: CGSize(width: 200, height: 100))
        let before = log.entries.count
        subject.send(4)
        #expect(log.entries.count == before)
    }

    @Test func timersPublishDates() async {
        let log = Log()
        // The runtime stays alive: unmounting cancels the subscription.
        let runtime = runtime(Text("Hi").onReceive(Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()) { _ in log.entries.append("tick") })
        // The main actor may be busy with other suites: wait up to two seconds for two ticks.
        for _ in 0..<50 where log.entries.count < 2 { try? await Task.sleep(nanoseconds: 40_000_000) }
        #expect(log.entries.count >= 2 && runtime.root.isMounted)
    }

    @Test func scenePhaseFollowsVisibilityAndFocus() {
        struct Phase: View {
            @Environment(\.scenePhase) private var phase
            var body: some View { Text(phase == .active ? "active" : phase == .inactive ? "inactive" : "background") }
        }
        let runtime = runtime(Phase())
        func shown() -> String? {
            runtime.render(scale: 2).commands.map(\.description).first { $0.hasPrefix("drawText(") }?.split(separator: "\"").dropFirst().first.map(String.init)
        }
        #expect(shown() == "active")
        runtime.hostIsFocused = false
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(shown() == "inactive" && runtime.scenePhase == .inactive)
        runtime.hostIsVisible = false
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(shown() == "background")
        runtime.hostIsVisible = true
        runtime.hostIsFocused = true
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(shown() == "active")
    }

    @Test func urlsAndActivitiesReachTheirHandlers() {
        let log = Log()
        let runtime = runtime(VStack {
            Text("Hi").onOpenURL { log.entries.append("outer \($0.absoluteString)") }
            Text("Hi").onOpenURL { log.entries.append("inner \($0.absoluteString)") }
                .onContinueUserActivity("com.example.view") { log.entries.append("activity \($0.activityType)") }
        })
        runtime.handleOpenURL("https://example.com/#detail")
        #expect(log.entries == ["outer https://example.com/#detail", "inner https://example.com/#detail"])
        let activity = NSUserActivity(activityType: "com.example.view")
        #expect(runtime.continueUserActivity(activity))
        #expect(!runtime.continueUserActivity(NSUserActivity(activityType: "com.example.other")))
        #expect(log.entries.last == "activity com.example.view")
    }

    @Test func childrenAppearBeforeTheirParents() {
        let log = Log()
        _ = runtime(VStack {
            Text("Hi").onAppear { log.entries.append("child") }
        }.onAppear { log.entries.append("parent") })
        #expect(log.entries == ["child", "parent"])
    }
}
#endif
