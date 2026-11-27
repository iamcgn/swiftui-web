// The older SwiftUI forms Clendar calls: the region-bound map with an annotation for each item
// (`MapPin`, `MapMarker`, `MapAnnotation`), `Color(_:)` from a Core Graphics colour and the
// widget container background.
import Testing
import SwiftUI
import SwiftUIWebCore
import MapKit

#if !os(WASI)
@Suite @MainActor struct ClendarAPIsTests {
    private struct Spot: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
    }

    /// Clendar's event location: one red pin on a map whose region the view moves on appear.
    @Test func theOlderMapShowsAnAnnotationForEachItemAndFollowsItsRegion() {
        var region = MKCoordinateRegion(center: CLLocationCoordinate2D(), span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03))
        let binding = Binding(get: { region }, set: { region = $0 })
        let spots = [Spot(id: 1, coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 20)),
                     Spot(id: 2, coordinate: CLLocationCoordinate2D(latitude: 11, longitude: 21))]
        let pins = Map(coordinateRegion: binding, annotationItems: spots) { MapPin(coordinate: $0.coordinate, tint: .red) }
        var items: [_MapItem] = []
        pins.content._collect(into: &items)
        #expect(items.map(\.coordinate) == spots.map(\.coordinate) && items.allSatisfy { $0.tint == .red && $0.content == nil })
        // The map reads the bound region when it draws, so a change after it was made shows.
        region.center = spots[0].coordinate
        #expect(pins.regionBinding?.wrappedValue.center == spots[0].coordinate)

        let views = Map(coordinateRegion: binding, showsUserLocation: true, userTrackingMode: .constant(.follow), annotationItems: spots) {
            MapAnnotation(coordinate: $0.coordinate, anchorPoint: CGPoint(x: 0.5, y: 1)) { Circle().frame(width: 8, height: 8) }
        }
        items = []
        views.content._collect(into: &items)
        #expect(items.count == 2 && items.allSatisfy { $0.content != nil && $0.anchor == .bottom })
        let markers = Map(coordinateRegion: binding, annotationItems: spots[...1]) { MapMarker(coordinate: $0.coordinate) }
        items = []
        markers.content._collect(into: &items)
        #expect(items.count == 2 && items[0].tint == nil)
    }

    @Test func aCoreGraphicsColourMakesTheSameColourEitherWay() {
        let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1).cgColor
        #expect(Color(red) == Color(cgColor: red))
        #expect(ContainerBackgroundPlacement.widget.name == "widget")
    }
}
#endif
