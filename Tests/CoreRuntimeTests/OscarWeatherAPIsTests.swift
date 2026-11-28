// OscarWeather's APIs outside its map and shaders: the App Intents that open its URLs, a chart
// annotation fitted inside the chart, the widget rendering mode its widget previews set, and the
// Watch Connectivity session it syncs units with (a page has no paired watch).
import Testing
import Foundation
import SwiftUI
import SwiftUIWebCore
import AppIntents
import Charts
import WidgetKit
import WatchConnectivity
#if os(Linux)
import WebFoundation   // LocalizedStringResource
#endif

#if !os(WASI)
private struct OpenRadarIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Radar" }
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "oscar://radar")!))
    }
}

@MainActor private final class Opened {
    var urls: [URL] = []
}

private final class SyncDelegate: NSObject, WCSessionDelegate, @unchecked Sendable {
    var finished: ((WCSessionActivationState, (any Error)?) -> Void)?
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        finished?(state, error)
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {}
}

@Suite @MainActor struct OscarWeatherAPIsTests {
    @Test func anOpenURLIntentHandsItsURLToThePagesOpener() async throws {
        let opened = Opened()
        let previous = OpenURLAction.systemHandler
        OpenURLAction.systemHandler = { opened.urls.append($0) }
        defer { OpenURLAction.systemHandler = previous }
        let url = try #require(URL(string: "oscar://place/1"))
        let intent = OpenURLIntent(url)
        #expect(intent.url == url && OpenURLIntent.openAppWhenRun)
        // The intent opens on the main actor without suspending first, so no other test's
        // opener (LinkTests sets its own) can take the URL.
        _ = try await intent.perform()
        #expect(opened.urls == [url])
        _ = try await OpenRadarIntent().perform()
    }

    @Test func anAnnotationFitsInsideTheBoundaryItNames() {
        let resolution = AnnotationOverflowResolution(x: .fit(to: .chart), y: .fit)
        #expect(resolution.x == .fit(to: .chart) && resolution.x != .fit(to: .plot))
        #expect(resolution.y == .fit(to: .automatic) && AnnotationOverflowResolution.automatic.x == .automatic)
        _ = RuleMark(y: .value("Rain", 2)).annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .padScale)) {
            Text("Rain")
        }
    }

    @Test func aWidgetViewReadsASmallFullColorWidgetsEnvironment() {
        var values = EnvironmentValues()
        #expect(values.widgetFamily == .systemSmall && values.widgetRenderingMode == .fullColor)
        #expect(values.showsWidgetContainerBackground && values.widgetContentMargins == EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        values.widgetRenderingMode = .accented
        values.widgetFamily = .accessoryRectangular
        #expect(values.widgetRenderingMode == .accented && values.widgetRenderingMode.description == "accented")
        #expect(values.widgetFamily == .accessoryRectangular)
        _ = Text("12°").widgetAccentable().environment(\.widgetRenderingMode, .vibrant)
    }

    @Test func aPageHasNoPairedWatchToSyncWith() async throws {
        #expect(!WCSession.isSupported())
        let session = WCSession.default
        #expect(session.activationState == .notActivated && !session.isPaired && !session.isWatchAppInstalled && !session.isReachable)
        let delegate = SyncDelegate()
        session.delegate = delegate
        let (state, code): (WCSessionActivationState, WCError.Code?) = await withCheckedContinuation { continuation in
            delegate.finished = { state, error in continuation.resume(returning: (state, (error as? WCError)?.code)) }
            session.activate()
        }
        #expect(state == .notActivated && code == .sessionNotSupported)
        var failure: WCError.Code?
        session.sendMessage(["unit": "celsius"], replyHandler: nil) { failure = ($0 as? WCError)?.code }
        #expect(failure == .notReachable)
        #expect(throws: WCError.self) { try session.updateApplicationContext(["unit": "celsius"]) }
        #expect(WCErrorDomain == "WCErrorDomain" && WCError(.notReachable).errorCode == 7007)
    }
}
#endif
