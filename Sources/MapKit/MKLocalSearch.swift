// Searching for places (MKLocalSearch, its completer and points-of-interest requests). A page has
// no place search: Apple's is a network service behind the device, and the browser has none of
// its own (the map's OpenStreetMap tiles are pictures, with no search behind them). So, as
// CLGeocoder does here, every search fails as Apple's does when its service can't be reached
// (`MKError.serverFailure`), after the call returns, and an app's "nothing found" path runs. A
// completer's fragment gets no completions and its delegate hears the same failure. Requests,
// responses, completions and categories are complete values for apps that build their own.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// MapKit's errors, in `MKErrorDomain`.
public let MKErrorDomain = "MKErrorDomain"

public struct MKError: CustomNSError, Hashable, @unchecked Sendable {
    public enum Code: Int, Sendable {
        case unknown = 1
        case serverFailure = 2
        case loadingThrottled = 3
        case placemarkNotFound = 4
        case directionsNotFound = 5
        case decodingFailed = 6
    }

    public let code: Code
    public let userInfo: [String: Any]
    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        self.code = code
        self.userInfo = userInfo
    }

    public static var errorDomain: String { MKErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { userInfo }

    public static func == (lhs: MKError, rhs: MKError) -> Bool { lhs.code == rhs.code }
    public func hash(into hasher: inout Hasher) { hasher.combine(code) }

    public static var unknown: Code { .unknown }
    public static var serverFailure: Code { .serverFailure }
    public static var loadingThrottled: Code { .loadingThrottled }
    public static var placemarkNotFound: Code { .placemarkNotFound }
    public static var directionsNotFound: Code { .directionsNotFound }
    public static var decodingFailed: Code { .decodingFailed }
}

/// A kind of place, as a search result or a filter names it.
public struct MKPointOfInterestCategory: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    private init(_ name: String) { rawValue = "MKPOICategory" + name }

    public static let airport = Self("Airport")
    public static let amusementPark = Self("AmusementPark")
    public static let aquarium = Self("Aquarium")
    public static let atm = Self("ATM")
    public static let bakery = Self("Bakery")
    public static let bank = Self("Bank")
    public static let beach = Self("Beach")
    public static let brewery = Self("Brewery")
    public static let cafe = Self("Cafe")
    public static let campground = Self("Campground")
    public static let carRental = Self("CarRental")
    public static let evCharger = Self("EVCharger")
    public static let fireStation = Self("FireStation")
    public static let fitnessCenter = Self("FitnessCenter")
    public static let foodMarket = Self("FoodMarket")
    public static let gasStation = Self("GasStation")
    public static let hospital = Self("Hospital")
    public static let hotel = Self("Hotel")
    public static let laundry = Self("Laundry")
    public static let library = Self("Library")
    public static let marina = Self("Marina")
    public static let movieTheater = Self("MovieTheater")
    public static let museum = Self("Museum")
    public static let nationalPark = Self("NationalPark")
    public static let nightlife = Self("Nightlife")
    public static let park = Self("Park")
    public static let parking = Self("Parking")
    public static let pharmacy = Self("Pharmacy")
    public static let police = Self("Police")
    public static let postOffice = Self("PostOffice")
    public static let publicTransport = Self("PublicTransport")
    public static let restaurant = Self("Restaurant")
    public static let restroom = Self("Restroom")
    public static let school = Self("School")
    public static let stadium = Self("Stadium")
    public static let store = Self("Store")
    public static let theater = Self("Theater")
    public static let university = Self("University")
    public static let winery = Self("Winery")
    public static let zoo = Self("Zoo")
}

/// Which kinds of place a search or a map shows.
public struct MKPointOfInterestFilter: Hashable, Sendable {
    private let included: Set<MKPointOfInterestCategory>?
    private let excluded: Set<MKPointOfInterestCategory>
    public init(including categories: [MKPointOfInterestCategory]) { included = Set(categories); excluded = [] }
    public init(excluding categories: [MKPointOfInterestCategory]) { included = nil; excluded = Set(categories) }
    public static let includingAll = MKPointOfInterestFilter(excluding: [])
    public static let excludingAll = MKPointOfInterestFilter(including: [])
    public func includes(_ category: MKPointOfInterestCategory) -> Bool {
        if let included { return included.contains(category) }
        return !excluded.contains(category)
    }
    public func excludes(_ category: MKPointOfInterestCategory) -> Bool { !includes(category) }
}

/// Points of interest around a centre or within a region.
open class MKLocalPointsOfInterestRequest: NSObject, @unchecked Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let radius: CLLocationDistance
    public let region: MKCoordinateRegion
    open var pointOfInterestFilter: MKPointOfInterestFilter?
    public init(center coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) {
        self.coordinate = coordinate
        self.radius = radius
        region = MKCoordinateRegion(center: coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        super.init()
    }
    public init(coordinateRegion region: MKCoordinateRegion) {
        coordinate = region.center
        radius = 0
        self.region = region
        super.init()
    }
}

/// A completion a search completer offers for what the person has typed so far.
open class MKLocalSearchCompletion: NSObject, @unchecked Sendable {
    open var title: String
    open var subtitle: String
    public init(title: String, subtitle: String = "") {
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}

/// Carries a value the compiler can't prove sendable into the main actor's callback.
private final class _Carried<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// A search for places by a query or a kind of place, within a region.
open class MKLocalSearch: NSObject, @unchecked Sendable {
    public typealias CompletionHandler = (MKLocalSearch.Response?, (any Error)?) -> Void

    /// What the search returns: addresses, points of interest, or physical features.
    public struct ResultType: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let address = ResultType(rawValue: 1 << 0)
        public static let pointOfInterest = ResultType(rawValue: 1 << 1)
        public static let physicalFeature = ResultType(rawValue: 1 << 2)
    }

    /// What to search for and where.
    open class Request: NSObject, @unchecked Sendable {
        open var naturalLanguageQuery: String?
        open var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                             span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))
        open var resultTypes: ResultType = [.address, .pointOfInterest]
        open var pointOfInterestFilter: MKPointOfInterestFilter?
        open var regionPriority: RegionPriority = .default

        public enum RegionPriority: Int, Sendable { case `default`, required }

        public override init() { super.init() }
        public convenience init(naturalLanguageQuery: String) {
            self.init()
            self.naturalLanguageQuery = naturalLanguageQuery
        }
        public convenience init(naturalLanguageQuery: String, region: MKCoordinateRegion) {
            self.init(naturalLanguageQuery: naturalLanguageQuery)
            self.region = region
        }
        /// A request for what a completer offered: its title and subtitle as the query.
        public convenience init(completion: MKLocalSearchCompletion) {
            self.init()
            naturalLanguageQuery = completion.subtitle.isEmpty ? completion.title : completion.title + ", " + completion.subtitle
        }
    }

    /// The places a search found, and the region that holds them.
    open class Response: NSObject, @unchecked Sendable {
        public let mapItems: [MKMapItem]
        public let boundingRegion: MKCoordinateRegion
        public init(mapItems: [MKMapItem], boundingRegion: MKCoordinateRegion) {
            self.mapItems = mapItems
            self.boundingRegion = boundingRegion
            super.init()
        }
    }

    public let request: Request
    open private(set) var isSearching = false
    private var pending: CompletionHandler?
    private var generation = 0

    public init(request: Request) {
        let copy = Request()
        copy.naturalLanguageQuery = request.naturalLanguageQuery
        copy.region = request.region
        copy.resultTypes = request.resultTypes
        copy.pointOfInterestFilter = request.pointOfInterestFilter
        copy.regionPriority = request.regionPriority
        self.request = copy
        super.init()
    }
    public init(request: MKLocalPointsOfInterestRequest) {
        let copy = Request()
        copy.region = request.region
        copy.resultTypes = .pointOfInterest
        copy.pointOfInterestFilter = request.pointOfInterestFilter
        self.request = copy
        super.init()
    }

    /// Searches, and calls the handler on the main actor after this returns: with
    /// `MKError.serverFailure`, since a page has no place search.
    open func start(completionHandler: @escaping CompletionHandler) {
        generation += 1
        pending = completionHandler
        isSearching = true
        let token = generation, search = _Carried(self)
        Task { @MainActor in
            let search = search.value
            guard search.generation == token, let completion = search.pending else { return }
            search.finish()
            completion(nil, MKError(.serverFailure))
        }
    }

    open func start() async throws -> Response {
        throw MKError(.serverFailure)
    }

    /// Ends the search in flight without calling its handler.
    open func cancel() { finish() }

    private func finish() {
        pending = nil
        isSearching = false
        generation += 1
    }
}

/// What a completer's delegate hears. Both methods do nothing unless the delegate implements them.
public protocol MKLocalSearchCompleterDelegate: AnyObject {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter)
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error)
}

extension MKLocalSearchCompleterDelegate {
    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {}
    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {}
}

/// Completions for a partly typed place name. Setting the fragment asks for completions; here the
/// delegate hears `MKError.serverFailure` on the main actor after the change, and `results` stays
/// empty.
open class MKLocalSearchCompleter: NSObject, @unchecked Sendable {
    /// What completions to offer: addresses, points of interest, or search queries.
    public struct ResultType: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let address = ResultType(rawValue: 1 << 0)
        public static let pointOfInterest = ResultType(rawValue: 1 << 1)
        public static let query = ResultType(rawValue: 1 << 2)
    }

    open weak var delegate: (any MKLocalSearchCompleterDelegate)?
    open var queryFragment = "" { didSet { if queryFragment != oldValue { ask() } } }
    open var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                         span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))
    open var resultTypes: ResultType = [.address, .pointOfInterest, .query]
    open var pointOfInterestFilter: MKPointOfInterestFilter?
    open private(set) var results: [MKLocalSearchCompletion] = []
    open private(set) var isSearching = false
    private var generation = 0

    public override init() { super.init() }

    /// Stops asking for the fragment's completions; the delegate hears nothing for it.
    open func cancel() {
        generation += 1
        isSearching = false
    }

    private func ask() {
        generation += 1
        results = []
        guard !queryFragment.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        let token = generation, completer = _Carried(self)
        Task { @MainActor in
            let completer = completer.value
            guard completer.generation == token else { return }
            completer.isSearching = false
            completer.delegate?.completer(completer, didFailWithError: MKError(.serverFailure))
        }
    }
}
