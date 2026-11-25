// The map view's camera (MKMapCamera) and its preferred configuration (MKMapConfiguration and
// its standard, imagery and hybrid kinds, iOS 16). A map view keeps both as apps set them and
// reads them back; the camera moves the region it shows. The backdrop doesn't change with the
// configuration's elevation, emphasis or points of interest yet (as `MKMapView` draws no tiles).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// A virtual camera for a map view: where it looks, from how far, and its pitch and heading.
open class MKMapCamera: NSObject, @unchecked Sendable {
    /// The point on the ground the camera looks at.
    open var centerCoordinate: CLLocationCoordinate2D
    /// The distance in metres from the camera to the centre coordinate.
    open var centerCoordinateDistance: CLLocationDistance
    /// The camera's angle from looking straight down, in degrees.
    open var pitch: CGFloat
    /// The compass heading of the camera, in degrees (0 is north).
    open var heading: CLLocationDirection

    /// The camera's height above the ground, from its distance and pitch.
    open var altitude: CLLocationDistance {
        get { centerCoordinateDistance * _cosDegrees(Double(pitch)) }
        set {
            let cosine = _cosDegrees(Double(pitch))
            centerCoordinateDistance = cosine > 0.0001 ? newValue / cosine : newValue
        }
    }

    public override init() {
        centerCoordinate = CLLocationCoordinate2D()
        centerCoordinateDistance = 0
        pitch = 0
        heading = 0
        super.init()
    }

    public init(lookingAtCenter centerCoordinate: CLLocationCoordinate2D, fromDistance distance: CLLocationDistance,
                pitch: CGFloat, heading: CLLocationDirection) {
        self.centerCoordinate = centerCoordinate
        centerCoordinateDistance = distance
        self.pitch = pitch
        self.heading = heading
        super.init()
    }

    /// A camera at an altitude straight above `eyeCoordinate`, turned to face the centre.
    public convenience init(lookingAtCenter centerCoordinate: CLLocationCoordinate2D,
                            fromEyeCoordinate eyeCoordinate: CLLocationCoordinate2D, eyeAltitude: CLLocationDistance) {
        let north = (centerCoordinate.latitude - eyeCoordinate.latitude) * 111_320
        let east = (centerCoordinate.longitude - eyeCoordinate.longitude) * 111_320
            * max(0.01, _cosDegrees(eyeCoordinate.latitude))
        let ground = (north * north + east * east).squareRoot()
        let distance = (ground * ground + eyeAltitude * eyeAltitude).squareRoot()
        let pitch = eyeAltitude > 0 ? _atan2(ground, eyeAltitude) * 180 / .pi : 90
        var heading = ground > 0 ? _atan2(east, north) * 180 / .pi : 0
        if heading < 0 { heading += 360 }
        self.init(lookingAtCenter: centerCoordinate, fromDistance: distance, pitch: CGFloat(pitch), heading: heading)
    }

    /// A camera over a map item, far enough out to show about two kilometres around it.
    public convenience init(lookingAt mapItem: MKMapItem, forViewSize viewSize: CGSize, allowPitch: Bool) {
        self.init(lookingAtCenter: mapItem.coordinate, fromDistance: 2000, pitch: 0, heading: 0)
    }

    /// The camera that shows `region` straight down.
    convenience init(_region region: MKCoordinateRegion) {
        self.init(lookingAtCenter: region.center, fromDistance: region.span.latitudeDelta * 111_320, pitch: 0, heading: 0)
    }
}

/// How a map view should draw the map: the base of the standard, imagery and hybrid kinds.
open class MKMapConfiguration: NSObject, @unchecked Sendable {
    /// Whether the map is drawn flat or with realistic terrain and buildings.
    public enum ElevationStyle: Int, Hashable, Sendable {
        case flat = 0
        case realistic = 1
    }

    open var elevationStyle: ElevationStyle = .flat

    public override init() { super.init() }
}

/// A street map with roads and their names.
open class MKStandardMapConfiguration: MKMapConfiguration, @unchecked Sendable {
    /// How strongly the map's colours stand out.
    public enum EmphasisStyle: Int, Hashable, Sendable {
        case `default` = 0
        case muted = 1
    }

    open var emphasisStyle: EmphasisStyle = .default
    open var pointOfInterestFilter: MKPointOfInterestFilter?
    open var showsTraffic = false

    public override init() { super.init() }
    public init(elevationStyle: MKMapConfiguration.ElevationStyle) {
        super.init()
        self.elevationStyle = elevationStyle
    }
    public init(elevationStyle: MKMapConfiguration.ElevationStyle, emphasisStyle: EmphasisStyle) {
        super.init()
        self.elevationStyle = elevationStyle
        self.emphasisStyle = emphasisStyle
    }
    public init(emphasisStyle: EmphasisStyle) {
        super.init()
        self.emphasisStyle = emphasisStyle
    }
}

/// Satellite imagery with no labels.
open class MKImageryMapConfiguration: MKMapConfiguration, @unchecked Sendable {
    public override init() { super.init() }
    public init(elevationStyle: MKMapConfiguration.ElevationStyle) {
        super.init()
        self.elevationStyle = elevationStyle
    }
}

/// Satellite imagery with roads and their names over it.
open class MKHybridMapConfiguration: MKMapConfiguration, @unchecked Sendable {
    open var pointOfInterestFilter: MKPointOfInterestFilter?
    open var showsTraffic = false

    public override init() { super.init() }
    public init(elevationStyle: MKMapConfiguration.ElevationStyle) {
        super.init()
        self.elevationStyle = elevationStyle
    }
}
