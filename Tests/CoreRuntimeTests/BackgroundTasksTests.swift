// BackgroundTasks' scheduler over the app's state: requests launch their tasks when the app goes
// to the background (the page hidden), not before their earliest begin date; an app refresh task
// expires after its time, a processing task when the app comes back; SwiftUI's
// `backgroundTask(.appRefresh(_:))` action runs as the task's launch handler. ActivityKit reads as
// a device without Live Activities.
#if !os(WASI)
import ActivityKit
import BackgroundTasks
import BackgroundTasksHost
import Foundation
import SwiftUI
import Testing

/// Polls until `condition` holds (or two seconds pass).
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

private struct Delivery: ActivityAttributes {
    struct ContentState: Codable, Hashable { var minutesLeft: Int }
    var orderNumber: Int
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

@Suite(.serialized) @MainActor
struct BackgroundTasksTests {
    init() {
        _BackgroundTasksHost._reset()
        BGTaskScheduler._reset()
    }

    @Test func anAppKeepsOneRefreshRequestAndTenProcessingRequests() async throws {
        let scheduler = BGTaskScheduler.shared
        try scheduler.submit(BGAppRefreshTaskRequest(identifier: "refresh"))
        // The same identifier replaces the pending request.
        let again = BGAppRefreshTaskRequest(identifier: "refresh")
        again.earliestBeginDate = Date(timeIntervalSinceNow: 900)
        try scheduler.submit(again)
        #expect(await scheduler.pendingTaskRequests().count == 1)
        #expect(await scheduler.pendingTaskRequests().first === again)
        #expect(throws: BGTaskScheduler.Error.self) { try scheduler.submit(BGAppRefreshTaskRequest(identifier: "other")) }
        do {
            try scheduler.submit(BGAppRefreshTaskRequest(identifier: "other"))
            Issue.record("a second refresh request was taken")
        } catch BGTaskScheduler.Error.tooManyPendingTaskRequests {
        } catch {
            Issue.record("unexpected \(error)")
        }
        for index in 0..<10 { try scheduler.submit(BGProcessingTaskRequest(identifier: "processing\(index)")) }
        #expect(throws: BGTaskScheduler.Error.self) { try scheduler.submit(BGProcessingTaskRequest(identifier: "processing10")) }
        scheduler.cancel(taskRequestWithIdentifier: "processing0")
        #expect(await scheduler.pendingTaskRequests().count == 10)
        var listed: [BGTaskRequest] = []
        scheduler.getPendingTaskRequests { listed = $0 }
        #expect(listed.count == 10)
        scheduler.cancelAllTaskRequests()
        #expect(await scheduler.pendingTaskRequests().isEmpty)
    }

    @Test func aRefreshTaskLaunchesWhenTheAppGoesToTheBackground() async throws {
        let scheduler = BGTaskScheduler.shared
        let launched = Box<[BGTask]>([])
        #expect(scheduler.register(forTaskWithIdentifier: "refresh", using: nil) { launched.value.append($0) })
        #expect(!scheduler.register(forTaskWithIdentifier: "refresh", using: nil) { _ in })
        try scheduler.submit(BGAppRefreshTaskRequest(identifier: "refresh"))
        // In the foreground, nothing runs.
        #expect(launched.value.isEmpty)
        _BackgroundTasksHost.setInBackground(true)
        #expect(launched.value.count == 1)
        let task = try #require(launched.value.first)
        #expect(task is BGAppRefreshTask)
        #expect(task.identifier == "refresh")
        #expect(await scheduler.pendingTaskRequests().isEmpty)
        task.setTaskCompleted(success: true)
        // A request launches once: going back and forth again runs nothing.
        _BackgroundTasksHost.setInBackground(false)
        _BackgroundTasksHost.setInBackground(true)
        #expect(launched.value.count == 1)
    }

    @Test func aRequestWaitsForItsEarliestBeginDate() async throws {
        let scheduler = BGTaskScheduler.shared
        let launched = Box<[String]>([])
        scheduler.register(forTaskWithIdentifier: "later", using: nil) { launched.value.append($0.identifier); $0.setTaskCompleted(success: true) }
        scheduler.register(forTaskWithIdentifier: "past", using: nil) { launched.value.append($0.identifier); $0.setTaskCompleted(success: true) }
        let later = BGProcessingTaskRequest(identifier: "later")
        later.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        let past = BGProcessingTaskRequest(identifier: "past")
        past.earliestBeginDate = Date(timeIntervalSinceNow: -60)
        try scheduler.submit(later)
        try scheduler.submit(past)
        _BackgroundTasksHost.setInBackground(true)
        #expect(launched.value == ["past"])
        #expect(await scheduler.pendingTaskRequests().map(\.identifier) == ["later"])
        scheduler.cancelAllTaskRequests()
    }

    @Test func aRequestSubmittedInTheBackgroundLaunchesRightAway() throws {
        let scheduler = BGTaskScheduler.shared
        let launched = Box(0)
        scheduler.register(forTaskWithIdentifier: "now", using: nil) { launched.value += 1; $0.setTaskCompleted(success: true) }
        _BackgroundTasksHost.setInBackground(true)
        try scheduler.submit(BGAppRefreshTaskRequest(identifier: "now"))
        #expect(launched.value == 1)
    }

    @Test func aRefreshTaskExpiresAfterItsTime() async throws {
        BGTaskScheduler._reset(refreshSeconds: 0.05)
        let scheduler = BGTaskScheduler.shared
        let expired = Box(false)
        scheduler.register(forTaskWithIdentifier: "slow", using: nil) { task in
            task.expirationHandler = { expired.value = true }
        }
        try scheduler.submit(BGAppRefreshTaskRequest(identifier: "slow"))
        _BackgroundTasksHost.setInBackground(true)
        #expect(await eventually { expired.value })
    }

    @Test func aProcessingTaskExpiresWhenTheAppComesBack() throws {
        let scheduler = BGTaskScheduler.shared
        let expired = Box(false)
        let launched = Box<[String]>([])
        scheduler.register(forTaskWithIdentifier: "maintenance", using: nil) { task in
            launched.value.append(task.identifier)
            #expect(task is BGProcessingTask)
            task.expirationHandler = { expired.value = true }
        }
        scheduler.register(forTaskWithIdentifier: "charging", using: nil) { task in launched.value.append(task.identifier) }
        let maintenance = BGProcessingTaskRequest(identifier: "maintenance")
        maintenance.requiresNetworkConnectivity = true
        let charging = BGProcessingTaskRequest(identifier: "charging")
        charging.requiresExternalPower = true
        try scheduler.submit(maintenance)
        try scheduler.submit(charging)
        _BackgroundTasksHost.setInBackground(true)
        // A page cannot tell whether the computer is plugged in: that request waits.
        #expect(launched.value == ["maintenance"])
        #expect(!expired.value)
        _BackgroundTasksHost.setInBackground(false)
        #expect(expired.value)
        scheduler.cancelAllTaskRequests()
    }

    @Test func aUIKitAppsBackgroundNotificationLaunchesTheTasks() throws {
        let scheduler = BGTaskScheduler.shared
        let launched = Box(0)
        scheduler.register(forTaskWithIdentifier: "uikit", using: nil) { launched.value += 1; $0.setTaskCompleted(success: true) }
        try scheduler.submit(BGAppRefreshTaskRequest(identifier: "uikit"))
        NotificationCenter.default.post(name: Notification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil)
        #expect(launched.value == 1)
        NotificationCenter.default.post(name: Notification.Name("UIApplicationWillEnterForegroundNotification"), object: nil)
        #expect(!_BackgroundTasksHost.inBackground)
    }

    @Test func swiftUIsAppRefreshActionRunsAsTheTask() async throws {
        let ran = Box(0)
        let scene = WindowGroup { Text("Inbox") }
            .backgroundTask(.appRefresh("fetchReplies")) { ran.value += 1 }
        _ = scene
        #expect(_BackgroundTasksHost.appRefreshActions["fetchReplies"] != nil)
        try BGTaskScheduler.shared.submit(BGAppRefreshTaskRequest(identifier: "fetchReplies"))
        _BackgroundTasksHost.setInBackground(true)
        #expect(await eventually { ran.value == 1 })
        // The URL session tasks a page never has take their actions and run nothing.
        _ = WindowGroup { Text("Inbox") }
            .backgroundTask(.urlSession("downloads")) {}
            .backgroundTask(.urlSession) { _ in }
        #expect(_BackgroundTasksHost.appRefreshActions.count == 1)
    }

    @Test func aPageIsADeviceWithoutLiveActivities() async {
        let info = ActivityAuthorizationInfo()
        #expect(!info.areActivitiesEnabled && !info.frequentPushesEnabled)
        let content = ActivityContent(state: Delivery.ContentState(minutesLeft: 12), staleDate: Date(timeIntervalSinceNow: 600), relevanceScore: 50)
        #expect(content == ActivityContent(state: Delivery.ContentState(minutesLeft: 12), staleDate: content.staleDate, relevanceScore: 50))
        #expect(throws: ActivityAuthorizationError.unsupported) {
            try Activity<Delivery>.request(attributes: Delivery(orderNumber: 7), content: content, pushType: .token)
        }
        #expect(throws: ActivityAuthorizationError.unsupported) {
            try Activity<Delivery>.request(attributes: Delivery(orderNumber: 7), content: content, pushType: nil, style: .transient)
        }
        #expect(Activity<Delivery>.activities.isEmpty)
        #expect(Activity<Delivery>.pushToStartToken == nil)
        #expect(ActivityUIDismissalPolicy.after(Date(timeIntervalSince1970: 0)) != .immediate)
        #expect(PushType.channel("weather") != .token)
        let alert = AlertConfiguration(title: "Your order", body: "Arriving soon", sound: .named("chime.caf"))
        #expect(alert.sound == .named("chime.caf"))
    }
}

#endif
