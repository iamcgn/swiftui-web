// CloudKit's errors and account status. A page has no iCloud account (the browser signs in to
// no Apple ID), so the default container answers `.noAccount` and every request to a database
// fails with `CKError.notAuthenticated`, the error CloudKit gives a device signed out of
// iCloud. Apps already handle that case: they keep their data on the device and offer sync
// once an account appears, which on the web it never does.
@_exported import WebFoundation

/// Whether the user's iCloud account can be used.
public enum CKAccountStatus: Int, Sendable, Hashable {
    case couldNotDetermine = 0
    case available = 1
    case restricted = 2
    case noAccount = 3
    case temporarilyUnavailable = 4
}

extension Notification.Name {
    /// Posted when the user's iCloud account changes (never on the web: there is no account).
    public static let CKAccountChanged = Notification.Name("CKAccountChangedNotification")
}

/// The domain of CloudKit errors.
public let CKErrorDomain = "CKErrorDomain"
/// The user info key for the seconds to wait before retrying.
public let CKErrorRetryAfterKey = "CKRetryAfter"
/// The user info key for the errors of each item of a partial failure.
public let CKPartialErrorsByItemIDKey = "CKPartialErrors"
/// The user info keys for the records of a `serverRecordChanged` error.
public let CKRecordChangedErrorServerRecordKey = "ServerRecord"
public let CKRecordChangedErrorClientRecordKey = "ClientRecord"
public let CKRecordChangedErrorAncestorRecordKey = "AncestorRecord"
/// The user info key set when the user reset their encrypted data.
public let CKErrorUserDidResetEncryptedDataKey = "CKErrorUserDidResetEncryptedDataKey"

/// An error from CloudKit.
public struct CKError: CustomNSError, LocalizedError, Hashable, @unchecked Sendable {
    public enum Code: Int, Hashable, Sendable {
        case internalError = 1
        case partialFailure = 2
        case networkUnavailable = 3
        case networkFailure = 4
        case badContainer = 5
        case serviceUnavailable = 6
        case requestRateLimited = 7
        case missingEntitlement = 8
        case notAuthenticated = 9
        case permissionFailure = 10
        case unknownItem = 11
        case invalidArguments = 12
        case resultsTruncated = 13
        case serverRecordChanged = 14
        case serverRejectedRequest = 15
        case assetFileNotFound = 16
        case assetFileModified = 17
        case incompatibleVersion = 18
        case constraintViolation = 19
        case operationCancelled = 20
        case changeTokenExpired = 21
        case batchRequestFailed = 22
        case zoneBusy = 23
        case badDatabase = 24
        case quotaExceeded = 25
        case zoneNotFound = 26
        case limitExceeded = 27
        case userDeletedZone = 28
        case tooManyParticipants = 29
        case alreadyShared = 30
        case referenceViolation = 31
        case managedAccountRestricted = 32
        case participantMayNeedVerification = 33
        case serverResponseLost = 34
        case assetNotAvailable = 35
        case accountTemporarilyUnavailable = 36
    }

    public let code: Code
    /// What CloudKit said about the error, as Foundation's `userInfo`.
    public let userInfo: [String: Any]

    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        self.userInfo = userInfo
    }

    public static var errorDomain: String { CKErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { userInfo }
    public var errorDescription: String? {
        if let description = userInfo["NSLocalizedDescription"] as? String { return description }
        switch code {
        case .notAuthenticated: return "This request requires an authenticated account"
        case .networkUnavailable: return "The network is unavailable"
        case .unknownItem: return "Record not found"
        case .operationCancelled: return "Operation cancelled"
        default: return "CloudKit error \(code.rawValue)"
        }
    }

    /// The seconds to wait before retrying, for a rate limit or a busy service.
    public var retryAfterSeconds: Double? {
        (userInfo[CKErrorRetryAfterKey] as? Double) ?? (userInfo[CKErrorRetryAfterKey] as? Int).map(Double.init)
    }
    /// The error of each item that failed, for a partial failure.
    public var partialErrorsByItemID: [AnyHashable: any Error]? { userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error] }
    /// The record on the server, for a `serverRecordChanged` error.
    public var serverRecord: CKRecord? { userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord }
    /// The record the app tried to save, for a `serverRecordChanged` error.
    public var clientRecord: CKRecord? { userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord }
    /// The record both started from, for a `serverRecordChanged` error.
    public var ancestorRecord: CKRecord? { userInfo[CKRecordChangedErrorAncestorRecordKey] as? CKRecord }

    public static func == (lhs: CKError, rhs: CKError) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }

    public static var internalError: Code { .internalError }
    public static var partialFailure: Code { .partialFailure }
    public static var networkUnavailable: Code { .networkUnavailable }
    public static var networkFailure: Code { .networkFailure }
    public static var badContainer: Code { .badContainer }
    public static var serviceUnavailable: Code { .serviceUnavailable }
    public static var requestRateLimited: Code { .requestRateLimited }
    public static var missingEntitlement: Code { .missingEntitlement }
    public static var notAuthenticated: Code { .notAuthenticated }
    public static var permissionFailure: Code { .permissionFailure }
    public static var unknownItem: Code { .unknownItem }
    public static var invalidArguments: Code { .invalidArguments }
    public static var resultsTruncated: Code { .resultsTruncated }
    public static var serverRecordChanged: Code { .serverRecordChanged }
    public static var serverRejectedRequest: Code { .serverRejectedRequest }
    public static var assetFileNotFound: Code { .assetFileNotFound }
    public static var assetFileModified: Code { .assetFileModified }
    public static var incompatibleVersion: Code { .incompatibleVersion }
    public static var constraintViolation: Code { .constraintViolation }
    public static var operationCancelled: Code { .operationCancelled }
    public static var changeTokenExpired: Code { .changeTokenExpired }
    public static var batchRequestFailed: Code { .batchRequestFailed }
    public static var zoneBusy: Code { .zoneBusy }
    public static var badDatabase: Code { .badDatabase }
    public static var quotaExceeded: Code { .quotaExceeded }
    public static var zoneNotFound: Code { .zoneNotFound }
    public static var limitExceeded: Code { .limitExceeded }
    public static var userDeletedZone: Code { .userDeletedZone }
    public static var tooManyParticipants: Code { .tooManyParticipants }
    public static var alreadyShared: Code { .alreadyShared }
    public static var referenceViolation: Code { .referenceViolation }
    public static var managedAccountRestricted: Code { .managedAccountRestricted }
    public static var participantMayNeedVerification: Code { .participantMayNeedVerification }
    public static var serverResponseLost: Code { .serverResponseLost }
    public static var assetNotAvailable: Code { .assetNotAvailable }
    public static var accountTemporarilyUnavailable: Code { .accountTemporarilyUnavailable }

    /// The error every request gets here: no iCloud account is signed in.
    static var _signedOut: CKError {
        CKError(.notAuthenticated, userInfo: ["NSLocalizedDescription": "No iCloud account is signed in in the browser"])
    }
}

/// Matches an error against a CloudKit error code (`catch CKError.notAuthenticated`).
public func ~= (code: CKError.Code, error: any Error) -> Bool {
    (error as? CKError)?.code == code
}
