// OldOS's Game Center app and photo viewer: GameKit with no one signed in, and a view whose
// layer is an `AVPlayerLayer`, which the host shows as the player's video element.
import Testing
import GameKit
import AVFoundation
import UIKitWebCore
#if !os(WASI)
import Foundation
#endif

@Suite @MainActor struct GameCenterAndPlayerLayerTests {
    @Test func theLocalPlayerNeverSignsIn() async {
        let local = GKLocalPlayer.local
        #expect(local === GKLocalPlayer.local && !local.isAuthenticated)
        let answer: (Bool, GKError.Code?) = await withCheckedContinuation { done in
            local.authenticateHandler = { controller, error in
                done.resume(returning: (controller == nil, (error as? GKError)?.code))
            }
        }
        #expect(answer.0 && answer.1 == .notSupported)
        local.authenticateHandler = nil

        let friends: ([GKPlayer]?, Bool) = await withCheckedContinuation { done in
            local.loadChallengableFriends { players, error in
                var matched = false
                if let error { switch error { case GKError.notAuthenticated: matched = true; default: break } }
                done.resume(returning: (players, matched))
            }
        }
        #expect(friends.0 == nil && friends.1)
        #expect(Notification.Name.GKPlayerAuthenticationDidChangeNotificationName.rawValue == "GKPlayerAuthenticationDidChangeNotificationName")
    }

    @Test func achievementsKeepTheirProgressButDoNotReport() async {
        let achievement = GKAchievement(identifier: "first_launch")
        achievement.percentComplete = 100
        achievement.showsCompletionBanner = true
        #expect(achievement.identifier == "first_launch" && achievement.isCompleted)
        await #expect(throws: GKError(.notAuthenticated)) { try await GKAchievement.report([achievement]) }
        await #expect(throws: GKError(.notAuthenticated)) { _ = try await GKAchievement.loadAchievements() }
        let guest = GKPlayer.anonymousGuestPlayer(withIdentifier: "Player 2")
        #expect(guest.guestIdentifier == "Player 2" && guest.alias == "Player 2" && GKPlayer().alias.isEmpty)
    }

    @Test func theDashboardSaysGameCenterIsUnavailable() {
        let dashboard = GKGameCenterViewController(state: .achievements)
        #expect(dashboard.viewState == .achievements && dashboard.viewControllers.count == 1)
        let screen = dashboard.viewControllers[0]
        screen.loadViewIfNeeded()
        #expect(screen.title == "Game Center" && screen.navigationItem.rightBarButtonItem != nil)
        #expect(GKGameCenterViewController(leaderboardID: "scores", playerScope: .global, timeScope: .allTime).leaderboardIdentifier == "scores")
    }

    @Test func aPlayerLayerShowsTheItemAsTheHostsVideo() async throws {
        final class PlayerView: UIView {
            override static var layerClass: AnyClass { AVPlayerLayer.self }
            var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        }
        let view = PlayerView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let layer = view.playerLayer
        #expect(layer._hostElementKind == nil && !layer.isReadyForDisplay)
        let url = URL(string: "https://example.com/clip.mp4")!
        let player = AVPlayer(url: url)
        layer.player = player
        layer.videoGravity = .resizeAspectFill
        #expect(layer.isReadyForDisplay && layer.videoRect == layer.bounds)
        #expect(layer._hostElementKind == .video(url: url.absoluteString, playing: false, muted: false, loops: false, controls: false,
                                                 rate: 0, seek: 0, seeks: 0, gravity: "AVLayerVideoGravityResizeAspectFill"))
        player.play()
        player.isMuted = true
        #expect(layer._hostElementKind == .video(url: url.absoluteString, playing: true, muted: true, loops: false, controls: false,
                                                 rate: 1, seek: 0, seeks: 0, gravity: "AVLayerVideoGravityResizeAspectFill"))
        layer.videoGravity = .resize
        if case .video(_, _, _, _, _, _, _, _, let gravity) = layer._hostElementKind { #expect(gravity == "AVLayerVideoGravityResize") }
        else { Issue.record("no video element") }
        layer.player = nil
        #expect(layer._hostElementKind == nil)
    }
}
