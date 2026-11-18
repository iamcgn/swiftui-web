// Core Spotlight and user activities (Sources/CoreSpotlight, WebFoundation's NSUserActivity,
// SwiftUI's `userActivity`): an index keeps what the app indexes and deletes by identifier and by
// domain, an activity carries what it says about itself to search with a typed payload written
// into its user info, and a view advertises its activity while active, as Harbour's container
// and stack screens do.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import CoreSpotlight

@MainActor private final class Log { var entries: [String] = [] }

private struct NavigationItem: Codable, Equatable {
    let id: String
    let endpointID: Int?
    enum CodingKeys: String, CodingKey { case id, endpointID }
}

@Suite @MainActor struct SpotlightActivityTests {
    private func item(_ id: String, domain: String?) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = id
        attributes.keywords = [id]
        return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain, attributeSet: attributes)
    }

    @Test func anIndexKeepsItemsByIdentifierAndDomain() async throws {
        let index = CSSearchableIndex(name: "tests")
        #expect(CSSearchableIndex.isIndexingAvailable())
        try await index.indexSearchableItems([item("a", domain: "container"), item("b", domain: "container.web"),
                                              item("c", domain: "stack"), item("d", domain: "containers")])
        #expect(Set(index._items.keys) == ["a", "b", "c", "d"])
        #expect(index._items["a"]?.attributeSet.contentType == UTType.url.identifier)
        // A domain takes its subdomains with it, not a domain that only starts with its name.
        try await index.deleteSearchableItems(withDomainIdentifiers: ["container"])
        #expect(Set(index._items.keys) == ["c", "d"])
        try await index.deleteSearchableItems(withIdentifiers: ["c"])
        #expect(Set(index._items.keys) == ["d"])
        var errors: [Bool] = []
        index.deleteAllSearchableItems { errors.append($0 == nil) }
        #expect(errors == [true])
        #expect(index._items.isEmpty)
        // An item with no identifier gets one.
        #expect(!CSSearchableItem(uniqueIdentifier: nil, domainIdentifier: nil, attributeSet: CSSearchableItemAttributeSet()).uniqueIdentifier.isEmpty)
    }

    @Test func aBatchRecordsItsClientState() async throws {
        let index = CSSearchableIndex(name: "batch")
        await #expect(throws: CSIndexError.self) { try await index.endBatch(withClientState: Data([1])) }
        index.beginBatch()
        index.indexSearchableItems([item("a", domain: nil)], completionHandler: nil)
        try await index.endBatch(withClientState: Data([7, 8]))
        #expect(try await index.fetchLastClientState() == Data([7, 8]))
    }

    @Test func continuationsMatchApplesActivityTypesAndKeys() {
        #expect(CSSearchableItemActionType == "com.apple.corespotlightitem")
        #expect(CSSearchableItemActivityIdentifier == "kCSSearchableItemActivityIdentifier")
        #expect(CSQueryContinuationActionType == "com.apple.corespotlightquerycontinuation")
        #expect(CSSearchQueryString == "kCSSearchQueryString")
    }

    #if !canImport(Darwin)
    @Test func aTypedPayloadLivesInTheUserInfo() throws {
        let activity = NSUserActivity(activityType: "com.example.container")
        activity.userInfo = ["other": "kept"]
        try activity.setTypedPayload(NavigationItem(id: "web", endpointID: 2))
        #expect(activity.userInfo?["id"] as? String == "web")
        #expect(activity.userInfo?["other"] as? String == "kept")
        activity.requiredUserInfoKeys = [NavigationItem.CodingKeys.id.stringValue]
        #expect(try activity.typedPayload(NavigationItem.self) == NavigationItem(id: "web", endpointID: 2))
        let empty = NSUserActivity(activityType: "com.example.none")
        #expect(throws: (any Error).self) { try empty.typedPayload(NavigationItem.self) }
    }

    @Test func anActivityCarriesWhatItSaysToSearch() {
        let activity = NSUserActivity(activityType: "com.example.container")
        #expect(!activity.isEligibleForSearch)
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.keywords = ["web", "nginx"]
        activity.persistentIdentifier = "containerDetails"
        activity.targetContentIdentifier = "containerDetails.2.web"
        let attributes = CSSearchableItemAttributeSet()
        attributes.title = "web"
        activity.contentAttributeSet = attributes
        #expect(activity.contentAttributeSet === attributes)
        #expect(activity.keywords == ["web", "nginx"])
        activity.addUserInfoEntries(from: ["a": 1])
        activity.addUserInfoEntries(from: ["a": 2, "b": 3])
        #expect(activity.userInfo?["a"] as? Int == 2)
        #expect(Set([activity, activity]).count == 1)
    }
    #endif

    // The runtime tests measure text with ChartsTests' engine, which wasm's test build leaves out.
    #if !os(WASI)
    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        _ = runtime.render(scale: 2)
        return runtime
    }

    @Test func aViewAdvertisesItsActivityWhileActive() throws {
        let log = Log()
        struct Screen: View {
            let log: Log
            @State var active = true
            var body: some View {
                Text("Detail")
                    .userActivity("com.example.detail", isActive: active) { activity in
                        activity.title = "Detail"
                        log.entries.append(activity.activityType)
                    }
                Button("Leave") { active = false }
            }
        }
        let runtime = runtime(VStack { Screen(log: log) })
        let current = runtime.currentUserActivity(ofType: "com.example.detail")
        #expect(current?.title == "Detail")
        #expect(log.entries.first == "com.example.detail")
        #expect(runtime.currentUserActivity(ofType: "com.example.other") == nil)
        let leave = try #require(runtime.semanticsTree().first { $0.label == "Leave" })
        runtime.activate(semanticsIdentifier: leave.identifier)
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.currentUserActivity(ofType: "com.example.detail") == nil)
    }

    @Test func anElementActivityFollowsItsElement() {
        let runtime = runtime(VStack {
            Text("A").userActivity("com.example.item", element: "web") { element, activity in activity.title = element }
            Text("B").userActivity("com.example.none", element: String?.none) { element, activity in activity.title = element }
        })
        #expect(runtime.currentUserActivity(ofType: "com.example.item")?.title == "web")
        #expect(runtime.currentUserActivity(ofType: "com.example.none") == nil)
    }
    #endif
}
