// MediaPlayer (Sources/MediaPlayer/MediaPlayer.swift) and the map pieces OldOS's iPod and Maps
// apps use (Sources/MapKit/MKDirections.swift): an empty library, players that keep their queue
// and modes, remote commands that call their handlers, directions that find no route, tile
// URLs from a template, distances in the locale's units, and `isKind(of:)` on any annotation.
import Testing
import SwiftUI
import MapKit
import MediaPlayer

private final class Song: MPMediaItem, @unchecked Sendable {
    let name: String
    init(_ name: String) {
        self.name = name
        super.init()
    }
    override var title: String? { name }
}

@Suite @MainActor struct MediaPlayerTests {
    /// OldOS's iPod: the library's songs and albums, and the player's now-playing item.
    @Test func theLibraryIsEmptyAndAccessIsDenied() {
        #expect(MPMediaQuery.songs().items?.isEmpty == true)
        #expect(MPMediaQuery.albums().collections?.isEmpty == true)
        #expect(MPMediaLibrary.authorizationStatus() == .denied)
        var answered: MPMediaLibraryAuthorizationStatus?
        MPMediaLibrary.requestAuthorization { answered = $0 }
        #expect(answered == .denied)
        let query = MPMediaQuery.artists()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: "Beck", forProperty: MPMediaItemPropertyArtist))
        #expect(query.filterPredicates?.count == 1)
        #expect(query.groupingType == .artist)
    }

    @Test func aPlayerKeepsItsQueueAndModesAndStaysStopped() {
        let player = MPMusicPlayerController.applicationMusicPlayer
        let first = Song("One"), second = Song("Two")
        let album = MPMediaItemCollection(items: [first, second])
        #expect(album.count == 2)
        #expect(album.representativeItem === first)
        player.setQueue(with: album)
        #expect(player.nowPlayingItem === first)
        player.skipToNextItem()
        #expect(player.nowPlayingItem?.title == "Two")
        #expect(player.indexOfNowPlayingItem == 1)
        player.shuffleMode = .songs
        player.repeatMode = .all
        #expect(player.shuffleMode == .songs && player.repeatMode == .all)
        player.play()
        #expect(player.playbackState == .stopped)
        #expect(MPMusicPlayerController.systemMusicPlayer !== player)
        #expect(MPMediaItemCollection(items: []).representativeItem == nil)
    }

    @Test func remoteCommandsCallTheirHandlers() {
        let command = MPRemoteCommandCenter.shared().togglePlayPauseCommand
        var calls = 0
        let token = command.addTarget { _ in
            calls += 1
            return .success
        }
        #expect(command._send() == .success)
        #expect(calls == 1)
        command.removeTarget(token)
        #expect(command._hasTargets == false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "One"]
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "One")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    @Test func theVolumeViewHoldsASlider() {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
        #expect(view.subviews.count == 1)
        #expect(view.subviews.first is UISlider)
        view.showsVolumeSlider = false
        #expect(view.subviews.first?.isHidden == true)
    }

    /// OldOS's map asks each annotation whether it is the user's location.
    @Test func anyAnnotationAnswersIsKind() {
        #expect(MKPolyline(coordinates: [], count: 0).isKind(of: MKShape.self))
        #expect(MKUserLocation().isMember(of: MKUserLocation.self))
        // Linux's Foundation keeps isKind(of:) on NSObject alone, not on NSObjectProtocol.
        #if !os(Linux)
        let pin: any MKAnnotation = MKPointAnnotation()
        let me: any MKAnnotation = MKUserLocation()
        #expect(me.isKind(of: MKUserLocation.self))
        #expect(!pin.isKind(of: MKUserLocation.self))
        #expect(pin.isKind(of: NSObject.self))
        #expect(!pin.isMember(of: NSObject.self))
        #endif
    }

    @Test func tileURLsFillTheTemplate() {
        let overlay = MKTileOverlay(urlTemplate: "https://tiles.example/{z}/{x}/{y}@{scale}x.png")
        let url = overlay.url(forTilePath: MKTileOverlayPath(x: 3, y: 5, z: 4, contentScaleFactor: 2))
        #expect(url.absoluteString == "https://tiles.example/4/3/5@2x.png")
        overlay.isGeometryFlipped = true
        #expect(overlay.url(forTilePath: MKTileOverlayPath(x: 3, y: 5, z: 4)).absoluteString == "https://tiles.example/4/3/10@1x.png")
        #expect(MKTileOverlayRenderer(tileOverlay: overlay).overlay === overlay)
    }

    @Test func distancesUseTheLocalesUnits() {
        let formatter = MKDistanceFormatter()
        formatter.locale = Locale(identifier: "en_US")
        #expect(formatter.string(fromDistance: 152) == "500 ft")
        #expect(formatter.string(fromDistance: 1931) == "1.2 mi")
        formatter.locale = Locale(identifier: "de_DE")
        #expect(formatter.string(fromDistance: 500) == "500 m")
        #expect(formatter.string(fromDistance: 25_000) == "25 km")
        formatter.unitStyle = .full
        #expect(formatter.string(fromDistance: 1000) == "1 kilometer")
    }

    @Test func directionsFindNoRoute() async {
        let request = MKDirections.Request()
        request.transportType = .walking
        do {
            _ = try await MKDirections(request: request).calculate()
            Issue.record("a route came back")
        } catch {
            #expect((error as? MKError)?.code == .directionsNotFound)
        }
    }
}
