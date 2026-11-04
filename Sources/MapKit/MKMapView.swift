// MKMapView for UIKit code and `UIViewRepresentable` wrappers: it keeps the camera, map type and
// annotations apps set and read back, and paints a plain land-coloured backdrop. Tiles and
// annotation views are not drawn yet (SwiftUI's `Map` draws them); recorded as approximate.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// An object that provides map-related data to a map view.
public protocol MKAnnotation: AnyObject, NSObjectProtocol {
    var coordinate: CLLocationCoordinate2D { get }
    var title: String? { get }
    var subtitle: String? { get }
}

extension MKAnnotation {
    public var title: String? { nil }
    public var subtitle: String? { nil }
}

/// An annotation at a point, with a title and subtitle.
open class MKPointAnnotation: NSObject, MKAnnotation {
    open var coordinate: CLLocationCoordinate2D
    open var title: String?
    open var subtitle: String?
    public override init() {
        coordinate = CLLocationCoordinate2D()
        super.init()
    }
    public init(coordinate: CLLocationCoordinate2D, title: String? = nil, subtitle: String? = nil) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}

/// The type of map to display.
public enum MKMapType: UInt, Sendable {
    case standard = 0, satellite, hybrid, satelliteFlyover, hybridFlyover, mutedStandard
}

/// The view that presents an annotation on the map.
@preconcurrency @MainActor
open class MKAnnotationView: UIView {
    public required init?(coder: NSCoder) { return nil }
    open var annotation: MKAnnotation?
    open private(set) var reuseIdentifier: String?
    open var image: UIImage?
    open var canShowCallout = false
    open var isDraggable = false
    open var centerOffset = CGPoint.zero
    open var leftCalloutAccessoryView: UIView?
    open var rightCalloutAccessoryView: UIView?
    open var detailCalloutAccessoryView: UIView?
    open var clusteringIdentifier: String?
    public init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        self.annotation = annotation
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
    }
    public override init(frame: CGRect) { super.init(frame: frame) }
    open func prepareForReuse() {}
}

/// An annotation view drawn as a balloon marker.
@preconcurrency @MainActor
open class MKMarkerAnnotationView: MKAnnotationView {
    public required init?(coder: NSCoder) { return nil }
    open var markerTintColor: UIColor?
    open var glyphTintColor: UIColor?
    open var glyphText: String?
    open var glyphImage: UIImage?
    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    }
    public override init(frame: CGRect) { super.init(frame: frame) }
}

/// Methods a map view calls on its delegate; each has a do-nothing default.
@MainActor
public protocol MKMapViewDelegate: AnyObject {
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool)
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool)
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView?
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView)
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView)
}

extension MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {}
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {}
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? { nil }
    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {}
    public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {}
    public func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {}
}

/// An embeddable map interface, similar to the one that the Maps app provides.
@preconcurrency @MainActor
open class MKMapView: UIView {
    public required init?(coder: NSCoder) { return nil }

    open weak var delegate: MKMapViewDelegate?
    open var mapType: MKMapType = .standard
    open var showsUserLocation = false
    open var showsCompass = true
    open var showsScale = false
    open var showsTraffic = false
    open var showsBuildings = true
    open var isZoomEnabled = true
    open var isScrollEnabled = true
    open var isRotateEnabled = true
    open var isPitchEnabled = true
    open private(set) var annotations: [MKAnnotation] = []
    open var selectedAnnotations: [MKAnnotation] = []

    /// The area the map shows; setting it tells the delegate the region changed.
    open var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.33, longitude: -122.03),
                                         span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)) {
        didSet {
            delegate?.mapView(self, regionDidChangeAnimated: false)
            delegate?.mapViewDidChangeVisibleRegion(self)
        }
    }
    open var centerCoordinate: CLLocationCoordinate2D {
        get { region.center }
        set { region.center = newValue }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 242 / 255, green: 239 / 255, blue: 233 / 255, alpha: 1)
    }

    open func setRegion(_ region: MKCoordinateRegion, animated: Bool) { self.region = region }
    open func setCenter(_ coordinate: CLLocationCoordinate2D, animated: Bool) { centerCoordinate = coordinate }
    open func regionThatFits(_ region: MKCoordinateRegion) -> MKCoordinateRegion { region }

    open func addAnnotation(_ annotation: MKAnnotation) { annotations.append(annotation) }
    open func addAnnotations(_ annotations: [MKAnnotation]) { self.annotations += annotations }
    open func removeAnnotation(_ annotation: MKAnnotation) { annotations.removeAll { $0 === annotation } }
    open func removeAnnotations(_ annotations: [MKAnnotation]) {
        for annotation in annotations { removeAnnotation(annotation) }
    }
    open func selectAnnotation(_ annotation: MKAnnotation, animated: Bool) { selectedAnnotations = [annotation] }
    open func deselectAnnotation(_ annotation: MKAnnotation?, animated: Bool) {
        selectedAnnotations.removeAll { $0 === annotation }
    }
    open func showAnnotations(_ annotations: [MKAnnotation], animated: Bool) {
        guard let first = annotations.first else { return }
        var minLat = first.coordinate.latitude, maxLat = minLat
        var minLon = first.coordinate.longitude, maxLon = minLon
        for annotation in annotations.dropFirst() {
            minLat = min(minLat, annotation.coordinate.latitude); maxLat = max(maxLat, annotation.coordinate.latitude)
            minLon = min(minLon, annotation.coordinate.longitude); maxLon = max(maxLon, annotation.coordinate.longitude)
        }
        region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                    span: MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.2), longitudeDelta: max(0.01, (maxLon - minLon) * 1.2)))
    }

    /// Registration is accepted; dequeuing with an annotation makes a marker view each time.
    open func register(_ viewClass: AnyClass?, forAnnotationViewWithReuseIdentifier identifier: String) {}
    open func dequeueReusableAnnotationView(withIdentifier identifier: String) -> MKAnnotationView? { nil }
    open func dequeueReusableAnnotationView(withIdentifier identifier: String, for annotation: MKAnnotation) -> MKAnnotationView {
        MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
    }
    open func view(for annotation: MKAnnotation) -> MKAnnotationView? { nil }
}
