// Map, VideoPlayer and WebView (sw-frameworks, Docs/elements/Frameworks.md): the host elements
// the runtime reports after a render (kind, frame, the clip they show through, the player's
// state), and the map's Web Mercator placement of tiles and markers.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import MapKit
import AVKit
import WebKit

#if !os(WASI)
@Suite @MainActor struct FrameworksTests {
    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 240)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()   // ChartsTests: 11 pt labels 14 tall
        runtime.mount(view)
        runtime.layout(in: size)
        _ = runtime.render(scale: 2)
        return runtime
    }

    @Test func videoPlayerReportsItsElementAndFollowsThePlayer() {
        let player = AVPlayer(url: URL(fileURLWithPath: "/clip.mp4"))
        let runtime = render(VideoPlayer(player: player).padding(16))
        let elements = runtime.hostElements()
        #expect(elements.count == 1)
        #expect(elements[0].frame == CGRect(x: 16, y: 16, width: 288, height: 208) && elements[0].visibleFrame == elements[0].frame)
        if case .video(let url, let playing, let muted, let loops, let controls, let rate) = elements[0].kind {
            #expect(url.hasSuffix("/clip.mp4") && !playing && !muted && !loops && controls && rate == 0)
        } else {
            Issue.record("expected a video element")
        }
        // The stand-in paints black under the element.
        let list = runtime.render(scale: 2)
        #expect(list.commands.contains { if case .fillRect(let rect, let color) = $0 { return color.red == 0 && color.green == 0 && color.blue == 0 && rect.width == 288 } else { return false } })
        // Playing and muting reach the next render.
        player.play()
        player.isMuted = true
        runtime.layout(in: CGSize(width: 320, height: 240))
        _ = runtime.render(scale: 2)
        if case .video(_, let playing, let muted, _, _, let rate) = runtime.hostElements()[0].kind {
            #expect(playing && muted && rate == 1)
        }
        player.pause()
        #expect(player.timeControlStatus == .paused && player.currentTime() == .zero)
    }

    @Test func webViewReportsItsPage() {
        let page = WebPage()
        page.load(URL(string: "https://example.com")!)
        let runtime = render(VStack(spacing: 0) {
            WebView(url: URL(string: "about:blank")).frame(height: 100)
            WebView(page)
        })
        let elements = runtime.hostElements()
        #expect(elements.count == 2)
        #expect(elements[0].kind == .web(url: "about:blank", html: nil) && elements[0].frame == CGRect(x: 0, y: 0, width: 320, height: 100))
        #expect(elements[1].kind == .web(url: "https://example.com", html: nil) && elements[1].frame == CGRect(x: 0, y: 100, width: 320, height: 140))
        page.load(html: "<p>Hi</p>")
        runtime.layout(in: CGSize(width: 320, height: 240))
        _ = runtime.render(scale: 2)
        #expect(runtime.hostElements()[1].kind == .web(url: nil, html: "<p>Hi</p>"))
        #expect(elements[0].identifier != elements[1].identifier)
    }

    /// A `WKWebView` inside a representable (Ember's reader and sign-in sheets, decision 0021).
    struct HostedWebView: UIViewRepresentable {
        let url: URL
        func makeUIView(context: Context) -> UIView {
            let container = UIView()
            container.clipsToBounds = true
            let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            webView.load(URLRequest(url: url))
            container.addSubview(webView)
            webView.frame = CGRect(x: 0, y: 20, width: 320, height: 200)   // below a bar of its own
            return container
        }
        func updateUIView(_ uiView: UIView, context: Context) {}
    }

    @Test func aUIKitWebViewIsAHostElementWhereItIs() {
        let runtime = render(VStack(spacing: 0) {
            Color.red.frame(height: 40)
            HostedWebView(url: URL(string: "https://news.ycombinator.com/login")!).frame(height: 120)
        })
        let elements = runtime.hostElements()
        #expect(elements.count == 1)
        #expect(elements[0].kind == .web(url: "https://news.ycombinator.com/login", html: nil))
        // The view's frame in the window (the stack's 160 pt sit 40 down in 240; the web view 20
        // into its container), clipped to the container that clips.
        #expect(elements[0].frame == CGRect(x: 0, y: 100, width: 320, height: 200), "\(elements[0].frame)")
        #expect(elements[0].visibleFrame == CGRect(x: 0, y: 100, width: 320, height: 100), "\(elements[0].visibleFrame)")
        // The identifier lasts across frames.
        runtime.layout(in: CGSize(width: 320, height: 240))
        _ = runtime.render(scale: 2)
        #expect(runtime.hostElements().first?.identifier == elements[0].identifier)
    }

    /// A controller that dismisses itself, as `SFSafariViewController`'s Done does.
    final class Closer: UIViewController {
        func close() { dismiss(animated: false) }
    }
    struct CloserView: UIViewControllerRepresentable {
        let keep: (Closer) -> Void
        func makeUIViewController(context: Context) -> Closer { let c = Closer(); keep(c); return c }
        func updateUIViewController(_ controller: Closer, context: Context) {}
    }
    @Observable final class SheetModel { var shown = true }

    @Test func aHostedControllersDismissClosesTheSheetAround() {
        let model = SheetModel()
        var closer: Closer?
        let runtime = render(Text("Page").sheet(isPresented: Binding(get: { model.shown }, set: { model.shown = $0 })) {
            CloserView { closer = $0 }
        })
        #expect(runtime.hasPresentations && closer != nil)
        closer?.close()
        #expect(!model.shown, "the sheet's dismiss ran")
        runtime.layout(in: CGSize(width: 320, height: 240))
        #expect(!runtime.hasPresentations)
    }

    @Test func elementsInsideScrollViewsAreClippedAndCulled() {
        let runtime = render(ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 150)
                WebView(url: URL(string: "about:blank")).frame(height: 200)
                Color.blue.frame(height: 2000)
                WebView(url: URL(string: "about:blank")).frame(height: 100)
            }
        }, size: CGSize(width: 200, height: 200))
        let elements = runtime.hostElements()
        // The first frame shows 50 of the first web view; the second is far below and not painted.
        #expect(elements.count == 1)
        #expect(elements[0].frame == CGRect(x: 0, y: 150, width: 200, height: 200))
        #expect(elements[0].visibleFrame == CGRect(x: 0, y: 150, width: 200, height: 50))
    }

    @Test func mercatorPlacesTilesAndMarkers() {
        // The null island at zoom 0 is the middle of the one tile; London is north-west of it.
        let origin = _MapTiles.worldPoint(CLLocationCoordinate2D(latitude: 0, longitude: 0), zoom: 0)
        #expect(abs(origin.x - 128) < 1e-6 && abs(origin.y - 128) < 1e-6)
        let london = _MapTiles.worldPoint(CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12), zoom: 10)
        #expect(london.x < 131072 && london.y < 131072 && abs(london.x - 130984.6) < 1 && abs(london.y - 87178.2) < 1)
        // The Ferry Building fixture's zoom: the 0.02° latitude span over 184 pt is the tighter fit (12.66; the longitude alone would allow 13.7).
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.7955, longitude: -122.3937), span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.03))
        let tiles = _MapTiles(region: region, size: CGSize(width: 288, height: 184), items: [])
        #expect(tiles.zoom > 12.6 && tiles.zoom < 12.7)
        // A region by metres: 2 km across at the equator is about 0.018°.
        let metres = MKCoordinateRegion(center: CLLocationCoordinate2D(), latitudinalMeters: 2000, longitudinalMeters: 2000)
        #expect(abs(metres.span.latitudeDelta - 0.01797) < 0.0005 && abs(metres.span.longitudeDelta - 0.01797) < 0.0005)
        // Automatic positions fit the markers.
        let fitted = Map<EmptyMapContent>.automaticRegion(for: [
            _MapItem(coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 10)),
            _MapItem(coordinate: CLLocationCoordinate2D(latitude: 12, longitude: 14)),
        ])
        #expect(fitted.center == CLLocationCoordinate2D(latitude: 11, longitude: 12) && abs(fitted.span.latitudeDelta - 2.8) < 1e-9)
        let distance = CLLocation(latitude: 0, longitude: 0).distance(from: CLLocation(latitude: 0, longitude: 1))
        #expect(abs(distance - 111_195) < 100)
    }

    @Test func mapLaysOutTilesAndMarkerAtTheCoordinate() {
        let ferry = CLLocationCoordinate2D(latitude: 37.7955, longitude: -122.3937)
        let runtime = render(Map(initialPosition: .region(MKCoordinateRegion(center: ferry, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.03)))) {
            Marker("Ferry Building", coordinate: ferry)
        }, size: CGSize(width: 288, height: 184))
        // The marker's title is a semantics text centred under the balloon (its frame before the
        // offset's translation: 36 below the coordinate plus the 2 pt spacing and 1 pt padding).
        let title = runtime.semanticsTree().first { $0.label == "Ferry Building" }
        #expect(title != nil && abs(title!.frame.midX - 144) < 1 && abs(title!.frame.minY - (92 + 36 + 3)) < 1 && title!.frame.width > 40, "title \(String(describing: title?.frame))")
        // The balloon's tip (a filled path ending at the coordinate) is at the centre: the path
        // is painted 36 below through the offset's translation.
        let commands = runtime.render(scale: 2).commands
        let balloon = commands.compactMap { command -> CGRect? in
            if case .fillPath(let path, let color, _) = command, color.red == 1, color.green < 0.3 { return path.boundingRect }
            return nil
        }
        #expect(balloon.count == 1 && abs(balloon[0].midX - 144) < 1 && abs(balloon[0].maxY - 36 - 92) < 1, "balloon \(balloon)")
        #expect(commands.contains { if case .concat(let t) = $0 { return t.ty == -36 } else { return false } })
        let text = commands.compactMap { command -> CGPoint? in
            if case .drawText("Ferry Building", _, let origin, _) = command { return origin }
            return nil
        }
        #expect(text.count == 1 && text[0].x < 144 && text[0].x > 90 && text[0].y > 92 + 36)
    }
}
#endif
