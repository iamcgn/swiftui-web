// The geocoder and placemarks (pf-corelocation). A page has no geocoding service: Apple's is a
// network service behind the device, and the browser has none of its own. So every request
// fails as Apple's does with no network (`CLError.network`), after the call returns, and an app's
// "couldn't find that place" path runs. Placemarks are complete values for apps that make or
// keep their own.

public typealias CLGeocodeCompletionHandler = ([CLPlacemark]?, (any Error)?) -> Void

/// A place's names and address parts, with its location.
open class CLPlacemark: NSObject, @unchecked Sendable {
    public let location: CLLocation?
    public let region: CLRegion?
    public let timeZone: TimeZone?
    public let name: String?
    public let thoroughfare: String?
    public let subThoroughfare: String?
    public let locality: String?
    public let subLocality: String?
    public let administrativeArea: String?
    public let subAdministrativeArea: String?
    public let postalCode: String?
    public let isoCountryCode: String?
    public let country: String?
    public let inlandWater: String?
    public let ocean: String?
    public let areasOfInterest: [String]?

    package init(location: CLLocation? = nil, region: CLRegion? = nil, timeZone: TimeZone? = nil, name: String? = nil,
                 thoroughfare: String? = nil, subThoroughfare: String? = nil, locality: String? = nil, subLocality: String? = nil,
                 administrativeArea: String? = nil, subAdministrativeArea: String? = nil, postalCode: String? = nil,
                 isoCountryCode: String? = nil, country: String? = nil, inlandWater: String? = nil, ocean: String? = nil,
                 areasOfInterest: [String]? = nil) {
        self.location = location
        self.region = region
        self.timeZone = timeZone
        self.name = name
        self.thoroughfare = thoroughfare
        self.subThoroughfare = subThoroughfare
        self.locality = locality
        self.subLocality = subLocality
        self.administrativeArea = administrativeArea
        self.subAdministrativeArea = subAdministrativeArea
        self.postalCode = postalCode
        self.isoCountryCode = isoCountryCode
        self.country = country
        self.inlandWater = inlandWater
        self.ocean = ocean
        self.areasOfInterest = areasOfInterest
    }

    public convenience init(placemark: CLPlacemark) {
        self.init(location: placemark.location, region: placemark.region, timeZone: placemark.timeZone, name: placemark.name,
                  thoroughfare: placemark.thoroughfare, subThoroughfare: placemark.subThoroughfare, locality: placemark.locality,
                  subLocality: placemark.subLocality, administrativeArea: placemark.administrativeArea,
                  subAdministrativeArea: placemark.subAdministrativeArea, postalCode: placemark.postalCode,
                  isoCountryCode: placemark.isoCountryCode, country: placemark.country, inlandWater: placemark.inlandWater,
                  ocean: placemark.ocean, areasOfInterest: placemark.areasOfInterest)
    }

    open override var description: String {
        let parts = [name, thoroughfare, locality, administrativeArea, postalCode, country].compactMap { $0 }
        var text = ""
        for part in parts { text += text.isEmpty ? part : ", " + part }
        if let location { text += (text.isEmpty ? "" : " @ ") + location.description }
        return text
    }
}

/// Carries a value the compiler can't prove sendable into the main actor's callback.
final class _Carried<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Converts between coordinates and place names. One request at a time, as on Apple platforms.
open class CLGeocoder: NSObject {
    open private(set) var isGeocoding = false
    private var pending: CLGeocodeCompletionHandler?
    private var generation = 0

    public override init() { super.init() }

    open func reverseGeocodeLocation(_ location: CLLocation, completionHandler: @escaping CLGeocodeCompletionHandler) {
        begin(completionHandler)
    }
    open func reverseGeocodeLocation(_ location: CLLocation, preferredLocale locale: Locale?, completionHandler: @escaping CLGeocodeCompletionHandler) {
        begin(completionHandler)
    }
    open func geocodeAddressString(_ addressString: String, completionHandler: @escaping CLGeocodeCompletionHandler) {
        begin(completionHandler)
    }
    open func geocodeAddressString(_ addressString: String, in region: CLRegion?, completionHandler: @escaping CLGeocodeCompletionHandler) {
        begin(completionHandler)
    }
    open func geocodeAddressString(_ addressString: String, in region: CLRegion?, preferredLocale locale: Locale?,
                                   completionHandler: @escaping CLGeocodeCompletionHandler) {
        begin(completionHandler)
    }

    open func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] { throw CLError(.network) }
    open func reverseGeocodeLocation(_ location: CLLocation, preferredLocale locale: Locale?) async throws -> [CLPlacemark] {
        throw CLError(.network)
    }
    open func geocodeAddressString(_ addressString: String) async throws -> [CLPlacemark] { throw CLError(.network) }
    open func geocodeAddressString(_ addressString: String, in region: CLRegion?) async throws -> [CLPlacemark] { throw CLError(.network) }
    open func geocodeAddressString(_ addressString: String, in region: CLRegion?, preferredLocale locale: Locale?) async throws -> [CLPlacemark] {
        throw CLError(.network)
    }

    /// Ends the request in flight; its handler hears `CLError.geocodeCanceled`.
    open func cancelGeocode() {
        guard let completion = pending else { return }
        finish()
        completion(nil, CLError(.geocodeCanceled))
    }

    private func begin(_ completion: @escaping CLGeocodeCompletionHandler) {
        if let earlier = pending {
            // A second request ends the first, as Apple's geocoder refuses to run two.
            finish()
            earlier(nil, CLError(.geocodeCanceled))
        }
        isGeocoding = true
        pending = completion
        generation += 1
        let token = generation, geocoder = _Carried(self)
        Task { @MainActor in
            let geocoder = geocoder.value
            guard geocoder.generation == token, let completion = geocoder.pending else { return }
            geocoder.finish()
            completion(nil, CLError(.network))
        }
    }

    private func finish() {
        pending = nil
        isGeocoding = false
        generation += 1
    }
}
