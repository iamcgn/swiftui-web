// Map, VideoPlayer and WebView (sw-frameworks, Docs/elements/Frameworks.md): the frames are
// compared; the pixels are Apple's frameworks' on macOS and the stand-ins' or OpenStreetMap's
// here, so the pixel tiers skip these (`frameworks/` is frames-only).
import SwiftUI
import FixtureKit
#if canImport(MapKit) && canImport(AVKit) && canImport(WebKit)
import MapKit
import AVKit
import WebKit

public enum FrameworkFixtures {
    /// A video player over a title; the URL has no media, so Apple's view shows its empty state.
    public static let video = Fixture("frameworks/video", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 8) {
            Text("Video").probe("title")
            VideoPlayer(player: AVPlayer(url: URL(fileURLWithPath: "/nonexistent/clip.mp4")))
                .probe("player")
        }
        .padding(16)
    }

    /// A web view on a blank page.
    public static let web = Fixture("frameworks/web", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 8) {
            Text("Web").probe("title")
            Group {
                if #available(macOS 26.0, iOS 26.0, *) {
                    WebView(url: URL(string: "about:blank"))
                } else {
                    Color.white
                }
            }
            .probe("web")
        }
        .padding(16)
    }

    /// A map of the Ferry Building with a marker.
    public static let map = Fixture("frameworks/map", size: CGSize(width: 320, height: 240)) {
        VStack(spacing: 8) {
            Text("Map").probe("title")
            Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.7955, longitude: -122.3937),
                                                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.03)))) {
                Marker("Ferry Building", coordinate: CLLocationCoordinate2D(latitude: 37.7955, longitude: -122.3937))
            }
            .probe("map")
        }
        .padding(16)
    }

    public static let all: [Fixture] = [video, web, map]
}
#else
public enum FrameworkFixtures {
    public static let all: [Fixture] = []
}
#endif
