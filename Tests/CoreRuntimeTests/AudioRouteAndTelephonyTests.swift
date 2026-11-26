// OldOS's voice memos, status bar and YouTube player: the audio session's ports and route, the
// network info of a page with no cellular radio, and the player members its YouTube view reads.
// This file imports MediaPlayer and not AVFoundation, as OldOS's shared file does: Apple's
// MediaPlayer brings AVFoundation's names (`AVAudioSession`) with it.
import Testing
import MediaPlayer
import CoreTelephony
// The macOS and Linux builds of these modules import Foundation without passing it on.
#if !os(WASI)
import Foundation
#else
import SwiftUI   // NSValue is WebGraphics' on wasm, which SwiftUI passes on
#endif

@Suite @MainActor struct AudioRouteAndTelephonyTests {
    @Test func theSessionRoutesTheMicrophoneOnlyWhenItRecords() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
        #expect(session.currentRoute.inputs.isEmpty)
        #expect(session.currentRoute.outputs.map(\.portType) == [.builtInSpeaker])
        try session.setCategory(.playAndRecord)
        let mic = try #require(session.availableInputs?.first { $0.portType == .builtInMic })
        try session.setPreferredInput(mic)
        #expect(session.preferredInput === mic)
        #expect(session.currentRoute.inputs.first?.portType == .builtInMic)
        try session.setPreferredInputNumberOfChannels(session.maximumInputNumberOfChannels)
        #expect(session.preferredInputNumberOfChannels == 1)
        #expect(mic.channels?.count == 1)
        try session.setCategory(.record)
        #expect(session.currentRoute.outputs.isEmpty)
        try session.setCategory(.soloAmbient)
        #expect(AVAudioSession.routeChangeNotification.rawValue == "AVAudioSessionRouteChangeNotification")
    }

    @Test func aPageHasNoCarrier() {
        let info = CTTelephonyNetworkInfo()
        #expect(info.serviceSubscriberCellularProviders == nil)
        #expect(info.serviceCurrentRadioAccessTechnology == nil)
        #expect(info.serviceSubscriberCellularProviders?.first?.value.carrierName == nil)
        #expect(CTCellularData().restrictedState == .notRestricted)
        #expect(Notification.Name.CTServiceRadioAccessTechnologyDidChange.rawValue == "kCTServiceRadioAccessTechnologyDidChangeNotification")
    }

    @Test func thePlayerAnswersWhatTheYouTubeViewReads() {
        let item = AVPlayerItem(asset: AVURLAsset(url: URL(string: "https://example.com/video.m3u8")!))
        item.preferredForwardBufferDuration = 6
        #expect(item.preferredForwardBufferDuration == 6)
        #expect(item.error == nil && item.loadedTimeRanges.isEmpty)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        #expect(!player.automaticallyWaitsToMinimizeStalling)
        #expect(player.reasonForWaitingToPlay == nil && player.error == nil)
        player.playImmediately(atRate: 1)
        #expect(player.timeControlStatus == .playing)
        #expect(item.asset.duration == .invalid)
        let range = CMTimeRange(start: CMTime(seconds: 2), duration: CMTime(seconds: 3))
        #expect(range.end == CMTime(seconds: 5) && range.containsTime(CMTime(seconds: 4)) && !range.containsTime(CMTime(seconds: 5)))
        #expect(NSValue(timeRange: range).timeRangeValue == range)
        // Mixed timescales add in their least common multiple, as CMTimeAdd does: 1/1 + 1/4 is 5/4.
        let mixed = CMTimeRangeGetEnd(CMTimeRange(start: CMTime(value: 1, timescale: 1), duration: CMTime(value: 1, timescale: 4)))
        #expect(mixed.value == 5 && mixed.timescale == 4 && mixed.seconds == 1.25)
        let between = CMTimeRange(start: CMTime(value: 1, timescale: 1), end: CMTime(value: 7, timescale: 4))
        #expect(between.duration.value == 3 && between.duration.timescale == 4)
        #expect(CMTimeAdd(CMTime(value: 1, timescale: 30), CMTime(value: 1, timescale: 25)).timescale == 150)
    }
}

