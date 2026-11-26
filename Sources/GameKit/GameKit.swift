// GameKit on the web (OldOS's Game Center app): a page has no Game Center account, so the local
// player never authenticates. Setting `authenticateHandler` calls it once with no view
// controller and a `notSupported` error, as Game Center answers on a device where it isn't
// available; loading friends, achievements and leaderboards fails with `notAuthenticated`, and
// reporting progress or scores does too. Players and achievements an app makes keep what they
// are given. The dashboard (`GKGameCenterViewController`) says that Game Center isn't
// available and tells its delegate when the person taps Done.
#if os(WASI)
@_exported import WebFoundation
#else
import Foundation
#endif
import UIKit

// MARK: - Errors

/// Game Center's errors (`GKErrorDomain`), with the codes Apple's have.
public struct GKError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Code: Int, Sendable {
        case unknown = 0
        case cancelled = 2
        case communicationsFailure = 3
        case userDenied = 4
        case invalidCredentials = 5
        case notAuthenticated = 6
        case authenticationInProgress = 7
        case invalidPlayer = 8
        case underage = 14
        case gameUnrecognized = 15
        case notSupported = 16
        case invalidParameter = 17
    }
    public static let errorDomain = "GKErrorDomain"
    public let code: Code
    public init(_ code: Code) { self.code = code }

    public static var unknown: Code { .unknown }
    public static var cancelled: Code { .cancelled }
    public static var communicationsFailure: Code { .communicationsFailure }
    public static var userDenied: Code { .userDenied }
    public static var invalidCredentials: Code { .invalidCredentials }
    public static var notAuthenticated: Code { .notAuthenticated }
    public static var authenticationInProgress: Code { .authenticationInProgress }
    public static var invalidPlayer: Code { .invalidPlayer }
    public static var underage: Code { .underage }
    public static var gameUnrecognized: Code { .gameUnrecognized }
    public static var notSupported: Code { .notSupported }
    public static var invalidParameter: Code { .invalidParameter }

    /// `catch GKError.notAuthenticated` matches an error with that code.
    public static func ~= (code: Code, error: any Error) -> Bool { (error as? GKError)?.code == code }

    public var errorCode: Int { code.rawValue }
    public var description: String {
        switch code {
        case .notSupported: return "Game Center isn't available on the web."
        case .notAuthenticated: return "The local player isn't signed in to Game Center."
        default: return "Game Center error \(code.rawValue)."
        }
    }
    public var localizedDescription: String { description }
}

public let GKErrorDomain = GKError.errorDomain

/// Runs a completion handler on the main actor after the call returns, as Game Center does.
private func _gkLater(_ body: @escaping @MainActor () -> Void) {
    Task { @MainActor in body() }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the local player's authentication changes (never, here: it stays signed out).
    public static let GKPlayerAuthenticationDidChangeNotificationName = Notification.Name("GKPlayerAuthenticationDidChangeNotificationName")
    /// Posted when a player's details change (never, here).
    public static let GKPlayerDidChangeNotificationName = Notification.Name("GKPlayerDidChangeNotificationName")
}

// MARK: - Players

/// What every player has.
open class GKBasePlayer: NSObject, @unchecked Sendable {
    /// The player's name to show (empty for a player Game Center hasn't described).
    open var displayName: String { _displayName }
    var _displayName = ""
}

/// A Game Center player.
open class GKPlayer: GKBasePlayer, @unchecked Sendable {
    /// The size of a player's photo.
    public enum PhotoSize: Int, Sendable { case small = 0, normal = 1 }

    /// The player's nickname.
    open var alias: String { _alias }
    var _alias = ""
    /// The player's ID in this game (empty: no player is signed in here).
    open var gamePlayerID: String { _gamePlayerID }
    var _gamePlayerID = ""
    /// The player's ID across the team's games.
    open var teamPlayerID: String { _teamPlayerID }
    var _teamPlayerID = ""
    @available(*, deprecated, message: "Use gamePlayerID or teamPlayerID")
    open var playerID: String { _gamePlayerID }
    /// A guest's identifier, for guest players the app makes.
    open private(set) var guestIdentifier: String?
    /// Whether the player can be invited to a match (no one can, here).
    open var isInvitable: Bool { false }

    public required override init() { super.init() }

    /// A guest player the app makes for local play, named by its identifier.
    open class func anonymousGuestPlayer(withIdentifier guestIdentifier: String) -> Self {
        let player = Self()
        player.guestIdentifier = guestIdentifier
        player._alias = guestIdentifier
        player._displayName = guestIdentifier
        return player
    }

    /// Whether the player's IDs stay the same between launches (they do for a guest).
    open func scopedIDsArePersistent() -> Bool { true }

    /// The player's photo: none, as Game Center has none to give.
    @MainActor
    open func loadPhoto(for size: PhotoSize, withCompletionHandler completionHandler: (@MainActor (UIImage?, (any Error)?) -> Void)? = nil) {
        guard let completionHandler else { return }
        _gkLater { completionHandler(nil, GKError(.notAuthenticated)) }
    }

    @MainActor
    open func loadPhoto(for size: PhotoSize) async throws -> UIImage {
        throw GKError(.notAuthenticated)
    }
}

/// The player signed in on the device: here no one, so it never authenticates.
open class GKLocalPlayer: GKPlayer, @unchecked Sendable {
    private static let shared = GKLocalPlayer()

    /// The local player.
    open class var local: GKLocalPlayer { shared }
    @available(*, deprecated, renamed: "local")
    open class func localPlayer() -> GKLocalPlayer { shared }

    /// Whether a Game Center account is signed in (never, here).
    open var isAuthenticated: Bool { false }
    open var isUnderage: Bool { false }
    open var isMultiplayerGamingRestricted: Bool { true }
    open var isPersonalizedCommunicationRestricted: Bool { true }

    /// Called with a sign-in view controller or an error. Setting it calls it once, after the
    /// assignment returns, with no view controller and a `notSupported` error.
    open var authenticateHandler: (@MainActor (UIViewController?, (any Error)?) -> Void)? {
        didSet {
            guard let handler = authenticateHandler else { return }
            _gkLater { handler(nil, GKError(.notSupported)) }
        }
    }

    // MARK: Friends

    @MainActor
    open func loadFriends(_ completionHandler: @escaping @MainActor ([GKPlayer]?, (any Error)?) -> Void) {
        _gkLater { completionHandler(nil, GKError(.notAuthenticated)) }
    }

    @MainActor
    open func loadFriends() async throws -> [GKPlayer] { throw GKError(.notAuthenticated) }

    @MainActor
    open func loadChallengableFriends(completionHandler: (@MainActor ([GKPlayer]?, (any Error)?) -> Void)? = nil) {
        guard let completionHandler else { return }
        _gkLater { completionHandler(nil, GKError(.notAuthenticated)) }
    }

    @MainActor
    open func loadRecentPlayers(completionHandler: (@MainActor ([GKPlayer]?, (any Error)?) -> Void)? = nil) {
        guard let completionHandler else { return }
        _gkLater { completionHandler(nil, GKError(.notAuthenticated)) }
    }

    /// Whether the app may read the player's friends (it is never asked, here).
    public enum FriendsAuthorizationStatus: Int, Sendable { case notDetermined = 0, restricted, denied, authorized }

    @MainActor
    open func loadFriendsAuthorizationStatus(_ completionHandler: @escaping @MainActor (FriendsAuthorizationStatus, (any Error)?) -> Void) {
        _gkLater { completionHandler(.restricted, GKError(.notAuthenticated)) }
    }

    // MARK: Listeners

    /// Listeners are kept and told nothing, as no invitation or turn event reaches a page.
    private var listeners: [AnyObject] = []
    open func register(_ listener: AnyObject) { listeners.append(listener) }
    open func unregisterListener(_ listener: AnyObject) { listeners.removeAll { $0 === listener } }
    open func unregisterAllListeners() { listeners.removeAll() }
}

// MARK: - Achievements

/// A player's progress on an achievement. Progress an app sets stays on the object; reporting
/// it fails, as no one is signed in.
open class GKAchievement: NSObject, @unchecked Sendable {
    open var identifier: String
    /// How far along the player is, 0 to 100.
    open var percentComplete: Double = 0
    open var isCompleted: Bool { percentComplete >= 100 }
    /// Whether Game Center shows a banner when the achievement is completed.
    open var showsCompletionBanner = false
    open private(set) var lastReportedDate = Date()
    open private(set) var player: GKPlayer?

    public init(identifier: String?) {
        self.identifier = identifier ?? ""
        super.init()
    }

    public init(identifier: String?, player: GKPlayer) {
        self.identifier = identifier ?? ""
        self.player = player
        super.init()
    }

    public override convenience init() { self.init(identifier: nil) }

    /// The local player's achievements: none load, as no one is signed in.
    @MainActor
    open class func loadAchievements(completionHandler: (@MainActor ([GKAchievement]?, (any Error)?) -> Void)? = nil) {
        guard let completionHandler else { return }
        _gkLater { completionHandler(nil, GKError(.notAuthenticated)) }
    }

    @MainActor
    open class func loadAchievements() async throws -> [GKAchievement] { throw GKError(.notAuthenticated) }

    @MainActor
    open class func report(_ achievements: [GKAchievement], withCompletionHandler completionHandler: (@MainActor ((any Error)?) -> Void)? = nil) {
        guard let completionHandler else { return }
        _gkLater { completionHandler(GKError(.notAuthenticated)) }
    }

    @MainActor
    open class func report(_ achievements: [GKAchievement]) async throws { throw GKError(.notAuthenticated) }

    @MainActor
    open class func resetAchievements(completionHandler: (@MainActor ((any Error)?) -> Void)? = nil) {
        guard let completionHandler else { return }
        _gkLater { completionHandler(GKError(.notAuthenticated)) }
    }
}

/// An achievement's title and descriptions, as App Store Connect describes it (none load here).
open class GKAchievementDescription: NSObject, @unchecked Sendable {
    open private(set) var identifier: String = ""
    open private(set) var title: String = ""
    open private(set) var achievedDescription: String = ""
    open private(set) var unachievedDescription: String = ""
    open private(set) var maximumPoints: Int = 0
    open private(set) var isHidden = false
    open private(set) var isReplayable = false

    @MainActor
    open class func loadAchievementDescriptions(completionHandler: (@MainActor ([GKAchievementDescription]?, (any Error)?) -> Void)? = nil) {
        guard let completionHandler else { return }
        _gkLater { completionHandler(nil, GKError(.notAuthenticated)) }
    }
}

// MARK: - Leaderboards

/// A leaderboard. None load, and submitting a score fails, as no one is signed in.
open class GKLeaderboard: NSObject, @unchecked Sendable {
    public enum PlayerScope: Int, Sendable { case global = 0, friendsOnly }
    public enum TimeScope: Int, Sendable { case today = 0, week, allTime }
    public enum LeaderboardType: Int, Sendable { case classic = 0, recurring }

    open private(set) var baseLeaderboardID: String = ""
    open private(set) var title: String?
    open private(set) var type: LeaderboardType = .classic

    @MainActor
    open class func loadLeaderboards(IDs leaderboardIDs: [String]?, completionHandler: @escaping @MainActor ([GKLeaderboard]?, (any Error)?) -> Void) {
        _gkLater { completionHandler(nil, GKError(.notAuthenticated)) }
    }

    @MainActor
    open class func submitScore(_ score: Int, context: Int, player: GKPlayer, leaderboardIDs: [String],
                                completionHandler: @escaping @MainActor ((any Error)?) -> Void) {
        _gkLater { completionHandler(GKError(.notAuthenticated)) }
    }

    @MainActor
    open class func submitScore(_ score: Int, context: Int, player: GKPlayer, leaderboardIDs: [String]) async throws {
        throw GKError(.notAuthenticated)
    }
}

// MARK: - The dashboard

/// Which part of Game Center's dashboard to show.
public enum GKGameCenterViewControllerState: Int, Sendable {
    case `default` = -1, leaderboards = 0, achievements = 1, challenges = 2, localPlayerProfile = 3, dashboard = 4,
         localPlayerFriendsList = 5
}

/// Hears that the person closed the dashboard.
@MainActor
public protocol GKGameCenterControllerDelegate: AnyObject {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController)
}

/// Game Center's dashboard: here a screen that says Game Center isn't available, with a Done
/// button that tells the delegate.
open class GKGameCenterViewController: UINavigationController {
    open weak var gameCenterDelegate: (any GKGameCenterControllerDelegate)?
    /// The part the dashboard opens on (accepted: there is one screen).
    open var viewState: GKGameCenterViewControllerState = .default
    open var leaderboardIdentifier: String?

    public required init?(coder: NSCoder) { return nil }

    public override init(nibName: String? = nil, bundle: Bundle? = nil) {
        super.init(nibName: nibName, bundle: bundle)
        let screen = _GKUnavailableViewController()
        screen.dashboard = self
        setViewControllers([screen], animated: false)
    }

    public convenience init(state: GKGameCenterViewControllerState) {
        self.init(nibName: nil, bundle: nil)
        viewState = state
    }

    public convenience init(leaderboardID: String, playerScope: GKLeaderboard.PlayerScope, timeScope: GKLeaderboard.TimeScope) {
        self.init(nibName: nil, bundle: nil)
        viewState = .leaderboards
        leaderboardIdentifier = leaderboardID
    }

    public convenience init(achievementID: String) {
        self.init(nibName: nil, bundle: nil)
        viewState = .achievements
    }

    func _done() { gameCenterDelegate?.gameCenterViewControllerDidFinish(self) }
}

/// The dashboard's one screen.
final class _GKUnavailableViewController: UIViewController {
    weak var dashboard: GKGameCenterViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Game Center"
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Game Center isn't available on the web."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dashboard?._done()
        })
    }
}

// MARK: - The access point

/// The Game Center access point. It never shows, as no one is signed in.
@MainActor
public final class GKAccessPoint: NSObject {
    public enum Location: Int, Sendable { case topLeading = 0, topTrailing, bottomLeading, bottomTrailing }
    public static let shared = GKAccessPoint()
    public var isActive = false
    public var isVisible: Bool { false }
    public var isPresentingGameCenter: Bool { false }
    public var showHighlights = false
    public var location: Location = .topLeading
    public var frameInScreenCoordinates: CGRect { .zero }
    public func trigger(handler: @escaping @MainActor () -> Void) { _gkLater(handler) }
    public func trigger(state: GKGameCenterViewControllerState, handler: @escaping @MainActor () -> Void) { _gkLater(handler) }
}
