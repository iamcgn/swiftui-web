// CloudKit in a browser: no iCloud account, so the container reports none and every request
// fails as on a signed-out device, while records, zones, queries and subscriptions build as
// values an app saves.
import Foundation
import Testing
import CloudKit

/// Collects what a callback hands over (the callbacks run before the call returns).
final class Box<T>: @unchecked Sendable {
    var value: T?
}

@Suite struct CloudKitTests {
    @Test func theContainerHasNoAccount() async throws {
        let container = CKContainer.default()
        #expect(container === CKContainer.default())
        #expect(try await container.accountStatus() == .noAccount)
        let status = Box<CKAccountStatus>()
        container.accountStatus { accountStatus, error in
            #expect(error == nil)
            status.value = accountStatus
        }
        #expect(status.value == .noAccount)
        #expect(CKAccountStatus.available.rawValue == 1)
        #expect(CKAccountStatus.noAccount.rawValue == 3)
        #expect(Notification.Name.CKAccountChanged.rawValue == "CKAccountChangedNotification")

        do {
            _ = try await container.userRecordID()
            Issue.record("expected an error")
        } catch let error as CKError {
            #expect(error.code == .notAuthenticated)
        }
        let custom = CKContainer(identifier: "iCloud.com.example.app")
        #expect(custom.containerIdentifier == "iCloud.com.example.app")
        #expect(custom.database(with: .private) === custom.privateCloudDatabase)
        #expect(custom.publicCloudDatabase.databaseScope == .public)
        #expect(custom.sharedCloudDatabase.databaseScope == .shared)
    }

    @Test func requestsFailSignedOut() async throws {
        let database = CKContainer(identifier: "iCloud.test").privateCloudDatabase
        let record = CKRecord(recordType: "Note")
        do {
            _ = try await database.save(record)
            Issue.record("expected an error")
        } catch CKError.notAuthenticated {
        } catch {
            Issue.record("unexpected \(error)")
        }
        await #expect(throws: CKError(.notAuthenticated)) {
            _ = try await database.records(matching: CKQuery(recordType: "Note", predicate: NSPredicate(value: true)))
        }
        await #expect(throws: CKError(.notAuthenticated)) { _ = try await database.allRecordZones() }

        let fetched = Box<any Error>()
        database.fetch(withRecordID: record.recordID) { _, error in fetched.value = error }
        #expect((fetched.value as? CKError)?.code == .notAuthenticated)
        #expect((fetched.value as? CKError)?.errorCode == 9)
        #expect(CKError.errorDomain == "CKErrorDomain")
    }

    @Test func operationsEndWithTheError() {
        let database = CKContainer(identifier: "iCloud.test").privateCloudDatabase
        let query = CKQueryOperation(query: CKQuery(recordType: "Note", predicate: NSPredicate(value: true)))
        let queryResult = Box<Result<CKQueryOperation.Cursor?, any Error>>()
        let matched = Box<Bool>()
        query.recordMatchedBlock = { _, _ in matched.value = true }
        query.queryResultBlock = { queryResult.value = $0 }
        database.add(query)
        #expect(query.database === database)
        #expect(query.isFinished)
        #expect(matched.value == nil)
        if case .failure(let error)? = queryResult.value {
            #expect((error as? CKError)?.code == .notAuthenticated)
        } else {
            Issue.record("expected a failure")
        }

        let modify = CKModifyRecordsOperation(recordsToSave: [CKRecord(recordType: "Note")], recordIDsToDelete: nil)
        let modified = Box<any Error>()
        modify.modifyRecordsCompletionBlock = { saved, deleted, error in
            #expect(saved == nil && deleted == nil)
            modified.value = error
        }
        modify.savePolicy = .changedKeys
        database.add(modify)
        #expect((modified.value as? CKError)?.code == .notAuthenticated)

        let changes = CKFetchDatabaseChangesOperation(previousServerChangeToken: nil)
        let changesError = Box<any Error>()
        changes.fetchDatabaseChangesCompletionBlock = { token, moreComing, error in
            #expect(token == nil && !moreComing)
            changesError.value = error
        }
        CKContainer(identifier: "iCloud.test").add(changes)
        #expect(changes.database?.databaseScope == .private)
        #expect(changesError.value != nil)

        let user = CKFetchRecordsOperation.fetchCurrentUserRecordOperation()
        #expect(user.recordIDs?.first?.recordName == CKCurrentUserDefaultName)
    }

    @Test func recordsHoldFields() {
        let zone = CKRecordZone(zoneName: "Notes")
        #expect(zone.zoneID.ownerName == CKCurrentUserDefaultName)
        #expect(zone.capabilities.contains(.fetchChanges))
        #expect(CKRecordZone.default().zoneID.zoneName == CKRecordZone.ID.defaultZoneName)
        #expect(CKRecordZone.ID.defaultZoneName == "_defaultZone")

        let record = CKRecord(recordType: "Note", recordID: CKRecord.ID(recordName: "n1", zoneID: zone.zoneID))
        record["title"] = "Groceries"
        record["count"] = 3
        record["tags"] = ["a", "b"]
        let due: Date? = Date(timeIntervalSince1970: 0)
        record["due"] = due
        #expect(record["title"] as? String == "Groceries")
        let count: Int? = record["count"]
        #expect(count == 3)
        #expect(record["tags"] as? [String] == ["a", "b"])
        #expect(record.allKeys() == ["title", "count", "tags", "due"])
        record["count"] = nil
        #expect(record.allKeys() == ["title", "tags", "due"])
        #expect(record.changedKeys().contains("count"))
        record.setValue("Errands", forKey: "title")
        #expect(record.value(forKey: "title") as? String == "Errands")
        #expect(record.creationDate == nil && record.recordChangeTag == nil)
        #expect(record.recordID.zoneID.zoneName == "Notes")

        let item = CKRecord(recordType: "Item")
        item["note"] = CKRecord.Reference(record: record, action: .deleteSelf)
        item.setParent(record)
        #expect((item["note"] as? CKRecord.Reference)?.recordID == record.recordID)
        #expect(item.parent?.recordID.recordName == "n1")

        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = "Shared notes"
        share.publicPermission = .readOnly
        #expect(share.recordType == "cloudkit.share")
        #expect(share.url == nil)
        #expect(share.owner.role == .owner)
        #expect(CKShare(recordZoneID: zone.zoneID).recordID.zoneID == zone.zoneID)
    }

    @Test func queriesAndSubscriptions() {
        let query = CKQuery(recordType: "Note", predicate: NSPredicate(value: true))
        #expect(query.recordType == "Note")
        #if !os(Linux)
        // swift-corelibs-foundation has no key-based sort descriptors (no key-value coding).
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        #expect(query.sortDescriptors?.count == 1)
        #endif
        #expect(CKQueryOperation.maximumResults == 0)

        let subscription = CKQuerySubscription(recordType: "Note", predicate: NSPredicate(value: true), subscriptionID: "notes",
                                               options: [.firesOnRecordCreation, .firesOnRecordUpdate])
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        #expect(subscription.subscriptionType == .query)
        #expect(subscription.querySubscriptionOptions.contains(.firesOnRecordUpdate))
        #expect(CKDatabaseSubscription(subscriptionID: "db").subscriptionType == .database)
        #expect(CKRecordZoneSubscription(zoneID: CKRecordZone.ID(zoneName: "Notes")).subscriptionType == .recordZone)
        #expect(CKNotification(fromRemoteNotificationDictionary: ["aps": ["content-available": 1]]) == nil)
    }
}
