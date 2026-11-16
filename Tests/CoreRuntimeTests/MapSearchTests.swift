// Place search (Sources/MapKit/MKLocalSearch.swift): with no search service, searches and
// completers fail as Apple's do when the service can't be reached, after the call returns, and
// the values apps build (requests, map items, placemarks, filters) hold what they're given.
import Testing
import SwiftUI
import MapKit

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
}
#endif
