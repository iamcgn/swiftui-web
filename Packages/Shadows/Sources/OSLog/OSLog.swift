// Apple's `OSLog` module for wasm (Docs/coverage.md: 6 apps): on iOS it re-exports `os`, where
// `Logger` lives, and adds reading the log store back. Apple's also re-exports Foundation, so a
// file that imports only OSLog (and Combine) names `ProcessInfo` and formats a `String` as a
// `CVarArg` (the Composable Architecture's Logger and SignpostReducer).
// A page is one process, so its store, whichever scope an app asks for, holds the messages the
// page itself has written through `Logger` and `os_log`, newest last (the newest few thousand,
// as `os` keeps them). An app's debug screen reads them back as Harbour's does: from a position,
// matching a predicate on the entries' subsystem, category or message (with the `CoreData`
// trait, which brings `NSPredicate`), as `OSLogEntryLog`s with their level and date.
#if os(WASI)
@_exported import os
@_exported import Foundation

// MARK: Entries

/// An entry in the log store.
open class OSLogEntry: @unchecked Sendable {
    /// Where an entry is kept, by how long the system keeps it.
    public enum StoreCategory: Int, Sendable {
        case undefined = 0, metadata, shortTerm, longTermAuto, longTerm1, longTerm3, longTerm7, longTerm14, longTerm30
    }

    /// The message with its arguments in place.
    public let composedMessage: String
    /// When the entry was written.
    public let date: Date
    public var storeCategory: StoreCategory { .shortTerm }

    init(composedMessage: String, date: Date) {
        self.composedMessage = composedMessage
        self.date = date
    }
}

/// A message written to a log: the subsystem and category it was filed under, and its level.
public final class OSLogEntryLog: OSLogEntry, @unchecked Sendable {
    /// A message's level, as the store reports it.
    public enum Level: Int, Sendable {
        case undefined = 0, debug, info, notice, error, fault
    }

    public let level: Level
    public let subsystem: String
    public let category: String
    /// The format string the message was written with (an `os_log` call's), or the message.
    public let formatString: String
    /// The page's one process.
    public var process: String { ProcessInfo.processInfo.processName }
    public var processIdentifier: Int32 { ProcessInfo.processInfo.processIdentifier }
    public var sender: String { process }
    public var threadIdentifier: UInt64 { 1 }

    init(_ record: _OSLogRecord) {
        switch record.type {
        case .debug: level = .debug
        case .info: level = .info
        case .error: level = .error
        case .fault: level = .fault
        default: level = .notice
        }
        subsystem = record.subsystem
        category = record.category
        formatString = record.format
        super.init(composedMessage: record.message, date: Date(timeIntervalSince1970: record.time))
    }
}

// MARK: The store

/// A place in the store that reading entries starts from.
public final class OSLogPosition: @unchecked Sendable {
    /// Seconds since 1970: entries written at or after it are read.
    let time: Double
    init(time: Double) { self.time = time }
}

/// How a store's entries are enumerated.
public enum OSLogEnumerator {
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        /// Newest first.
        public static let reverse = Options(rawValue: 1)
    }
}

/// The messages the page has logged, read back.
public final class OSLogStore: @unchecked Sendable {
    /// Which process's messages a store reads: on a page, either one is the page's own.
    public enum Scope: Int, Sendable {
        case system = 0, currentProcessIdentifier = 1
    }

    public let scope: Scope

    public init(scope: Scope) throws { self.scope = scope }

    /// The store of the page's own messages.
    public static func local() throws -> OSLogStore { try OSLogStore(scope: .system) }

    /// The position at a date.
    public func position(date: Date) -> OSLogPosition {
        OSLogPosition(time: date.timeIntervalSince1970)
    }

    /// The position the interval before the newest entry.
    public func position(timeIntervalSinceEnd interval: TimeInterval) -> OSLogPosition {
        OSLogPosition(time: (_OSLogRecords.records.last?.time ?? _OSLogRecords.now()) - interval)
    }

    /// The position the interval after the page started (its process's launch).
    public func position(timeIntervalSinceLatestBoot interval: TimeInterval) -> OSLogPosition {
        OSLogPosition(time: _OSLogRecords.now() - ProcessInfo.processInfo.systemUptime + interval)
    }

    /// The entries from the position on, oldest first (newest first with `.reverse`).
    public func getEntries(with options: OSLogEnumerator.Options = [], at position: OSLogPosition? = nil) throws -> AnySequence<OSLogEntry> {
        try entries(options, position) { _ in true }
    }

    func entries(_ options: OSLogEnumerator.Options, _ position: OSLogPosition?, _ keep: (OSLogEntryLog) -> Bool) throws -> AnySequence<OSLogEntry> {
        let start = position?.time ?? -.infinity
        var read: [OSLogEntry] = []
        for record in _OSLogRecords.records where record.time >= start {
            let entry = OSLogEntryLog(record)
            if keep(entry) { read.append(entry) }
        }
        if options.contains(.reverse) { read.reverse() }
        return AnySequence(read)
    }
}

#if CoreData
// A predicate reads an entry's subsystem, category, message, level and date by name, as Apple's
// store matches them.
extension OSLogEntry: _CDKeyValueCoding {
    public func value(forKey key: String) -> Any? {
        let log = self as? OSLogEntryLog
        switch key {
        case "composedMessage": return composedMessage
        case "date": return date
        case "subsystem": return log?.subsystem
        case "category": return log?.category
        case "level": return log?.level.rawValue
        case "formatString": return log?.formatString
        case "process", "sender": return log?.process
        case "processIdentifier": return log?.processIdentifier
        default: return nil
        }
    }
}

extension OSLogStore {
    /// The entries from the position on that match the predicate.
    public func getEntries(with options: OSLogEnumerator.Options = [], at position: OSLogPosition? = nil,
                           matching predicate: NSPredicate?) throws -> AnySequence<OSLogEntry> {
        try entries(options, position) { predicate?.evaluate(with: $0) ?? true }
    }
}
#endif
#endif
