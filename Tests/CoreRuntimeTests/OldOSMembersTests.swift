// Members OldOS calls: times in order, text a formatter writes, a map delegate's renderer of no
// overlay, and the microphone data sources its voice memos look through.
import Testing
import SwiftUI
import SwiftUIWebCore
import AVFoundation
import MapKit
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

@Suite @MainActor struct OldOSMembersTests {
    @Test func timesAreInOrder() {
        let half = CMTime(value: 1, timescale: 2), one = CMTime(seconds: 1)
        #expect(half < one && one > half)
        // CMTimeCompare puts an invalid time after every other, positive infinity included.
        #expect(half < CMTime.invalid && CMTime.positiveInfinity < CMTime.invalid && !(CMTime.invalid < half))
        #expect(CMTimeCompare(CMTime.invalid, CMTime.positiveInfinity) == 1 && CMTimeCompare(CMTime.invalid, CMTime.invalid) == 0)
        #expect(CMTimeMinimum(CMTime.invalid, half) == half && CMTimeMaximum(CMTime.invalid, half) == CMTime.invalid)
        #expect(CMTimeCompare(half, one) == -1 && CMTimeCompare(one, CMTime(value: 600, timescale: 600)) == 0
                && CMTimeCompare(one, half) == 1)
        #expect(CMTimeMaximum(half, one) == one && CMTimeMinimum(half, one) == half)
    }

    @Test func aFormatterWritesTheText() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = Date(timeIntervalSince1970: 1_775_000_000)
        let written = formatter.string(from: date)
        #expect(written.count == 10)
        #expect(Text(date, formatter: formatter).resolvedString == written)
        let key: LocalizedStringKey = "Edited \(date, formatter: formatter)"
        #expect(Text(key).resolvedString == "Edited \(written)")
    }

    @Test func aRendererOfNoOverlayDrawsAnEmptyLine() {
        let renderer = MKOverlayRenderer()
        #expect((renderer.overlay as? MKPolyline)?.pointCount == 0)
        #expect(MKPolylineRenderer().polyline?.pointCount == 0)
    }

    @Test func theBrowsersMicrophoneHasNoDataSourceToFace() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord)
        let mic = try #require(session.availableInputs?.first { $0.portType == .builtInMic })
        #expect(mic.dataSources?.first(where: { $0.orientation == .back }) == nil)
        #expect(AVAudioSession.Orientation.back.rawValue == "Back" && AVAudioSession.PolarPattern.cardioid != .omnidirectional)
        try session.setCategory(.playback)
    }
}
