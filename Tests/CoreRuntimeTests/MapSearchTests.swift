// Place search (Sources/MapKit/MKLocalSearch.swift): with no search service, searches and
// completers fail as Apple's do when the service can't be reached, after the call returns, and
// the values apps build (requests, map items, placemarks, filters) hold what they're given.
import Testing
import SwiftUI
import MapKit

// Temporary: marks each test's start and end on stderr, which isn't buffered, to find which one
// crashes the Linux test process.
private func _diag(_ text: String) {
    #if os(Linux)
    FileHandle.standardError.write(("DIAG " + text + "\n").data(using: .utf8)!)
    #endif
}

#if !os(WASI)
private final class Listener: MKLocalSearchCompleterDelegate {
    var failures: [MKError.Code] = []
    var updates = 0
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { updates += 1 }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        failures.append((error as? MKError)?.code ?? .unknown)
    }
}

@Suite @MainActor struct MapSearchTests {
    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    /// SwiftUIExperiments' map explore: a restaurant search around a coordinate, whose handler
    /// keeps the current restaurant when nothing comes back.
    @Test func aSearchFailsAfterItStartsAndCancelsQuietly() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant"
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.7268, longitude: -73.9845),
                                            latitudinalMeters: 1000, longitudinalMeters: 1000)
        let search = MKLocalSearch(request: request)
        request.naturalLanguageQuery = "cafe"
        #expect(search.request.naturalLanguageQuery == "restaurant")
        var answers: [MKError.Code] = []
        search.start { response, error in
            #expect(response == nil)
            answers.append((error as? MKError)?.code ?? .unknown)
        }
        #expect(search.isSearching && answers.isEmpty)
        await settle()
        #expect(answers == [.serverFailure] && !search.isSearching)
        // A second start while the first runs leaves the first running and fails at once.
        var order: [String] = []
        search.start { _, error in order.append("A \((error as? MKError)?.code ?? .decodingFailed)") }
        search.start { _, error in order.append("B \((error as? MKError)?.code ?? .decodingFailed)") }
        await settle()
        #expect(order.sorted() == ["A serverFailure", "B unknown"] && !search.isSearching)
        search.start { _, _ in answers.append(.unknown) }
        search.cancel()
        await settle()
        #expect(answers == [.serverFailure] && !search.isSearching)
        do {
            _ = try await MKLocalSearch(request: MKLocalPointsOfInterestRequest(center: request.region.center, radius: 500)).start()
            Issue.record("searched without a service")
        } catch {
            #expect(error as? MKError == MKError(.serverFailure))
        }
        #expect(MKError.errorDomain == "MKErrorDomain" && MKError(.placemarkNotFound).errorCode == 4)
    }

    @Test func aCompleterTellsItsDelegateOnceForEachFragment() async {
        let completer = MKLocalSearchCompleter()
        let listener = Listener()
        completer.delegate = listener
        completer.resultTypes = .pointOfInterest
        completer.queryFragment = "Nore"
        completer.queryFragment = "Noreetuh"
        #expect(completer.isSearching)
        await settle()
        #expect(listener.failures == [.serverFailure] && listener.updates == 0 && completer.results.isEmpty && !completer.isSearching)
        completer.queryFragment = "Noreetuh"
        completer.queryFragment = ""
        await settle()
        #expect(listener.failures == [.serverFailure])
        completer.queryFragment = "Cafe"
        completer.cancel()
        await settle()
        #expect(listener.failures == [.serverFailure] && !completer.isSearching)
        let completion = MKLocalSearchCompletion(title: "Noreetuh", subtitle: "New York, NY")
        #expect(MKLocalSearch.Request(completion: completion).naturalLanguageQuery == "Noreetuh, New York, NY")
    }

    @Test func mapItemsCarryTheirPlacemarks() {
        let coordinate = CLLocationCoordinate2D(latitude: 40.7268, longitude: -73.9845)
        let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: [
            "Name": "Noreetuh", "Street": "128 1st Avenue", "City": "New York", "State": "NY", "ZIP": "10009",
            "Country": "United States", "CountryCode": "US",
        ])
        #expect(placemark.title == "128 1st Avenue, New York, NY 10009, United States")
        #expect(placemark.coordinate == coordinate && placemark.countryCode == "US" && placemark.locality == "New York")
        let item = MKMapItem(placemark: placemark)
        #expect(item.name == "Noreetuh" && item.placemark === placemark && item.coordinate == coordinate && !item.isCurrentLocation)
        #expect(MKPlacemark(coordinate: coordinate).title == nil)
        #expect(MKPlacemark(placemark: placemark).postalCode == "10009")
        let here = MKMapItem.forCurrentLocation()
        #expect(here.isCurrentLocation && here.placemark.location == nil)
        let restaurants = MKPointOfInterestFilter(including: [.restaurant, .cafe])
        #expect(restaurants.includes(.cafe) && restaurants.excludes(.museum))
        #expect(MKPointOfInterestFilter.includingAll.includes(.zoo) && MKPointOfInterestFilter.excludingAll.excludes(.zoo))
        #expect(MKPointOfInterestCategory.restaurant.rawValue == "MKPOICategoryRestaurant")
    }

    /// CriticalMaps' "Open in Maps" for a ride's meeting point: Apple Maps' web link, with
    /// directions when a mode is asked for, and nothing to open for the current location alone.
    @Test func openingInMapsLinksToTheItem() {
        _diag("openingInMapsLinksToTheItem begin"); defer { _diag("openingInMapsLinksToTheItem end") }
        let start = MKMapItem(coordinate: CLLocationCoordinate2D(latitude: 52.5, longitude: 13.25), name: "Start")
        let meeting = MKMapItem(coordinate: CLLocationCoordinate2D(latitude: 52.25, longitude: 13.5), name: "Mariannenplatz Berlin")
        let show = MKMapItem.mapsURL(for: [meeting], launchOptions: [:])
        #expect(show?.absoluteString == "https://maps.apple.com/?ll=52.25,13.5&q=Mariannenplatz%20Berlin")
        let walk = MKMapItem.mapsURL(for: [meeting], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        #expect(walk?.absoluteString == "https://maps.apple.com/?daddr=52.25,13.5&dirflg=w")
        let route = MKMapItem.mapsURL(for: [start, meeting], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        #expect(route?.absoluteString == "https://maps.apple.com/?saddr=52.5,13.25&daddr=52.25,13.5")
        let fromHere = MKMapItem.mapsURL(for: [.forCurrentLocation(), meeting], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        #expect(fromHere?.absoluteString == "https://maps.apple.com/?daddr=52.25,13.5&dirflg=d")
        #expect(MKMapItem.mapsURL(for: [.forCurrentLocation()], launchOptions: [:]) == nil)
        #expect(MKMapItem.mapsURL(for: [], launchOptions: [:]) == nil)
    }
}
#endif
