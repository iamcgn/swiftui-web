// CoreLocation (pf-corelocation) against a fake browser: authorization as the browser's prompt
// and permission, the one-shot request, updates with a distance filter, circular regions
// entered and left, live updates, and the geocoder's no-service answer. Without a host:
// location services are off, a request answers denied and updates fail.
import Testing
import CoreLocation

#if !os(WASI)
@Suite(.serialized) @MainActor struct CoreLocationTests {
    final class Recorder: NSObject, CLLocationManagerDelegate {
        var statuses: [CLAuthorizationStatus] = []
        var changes = 0
        var locations: [CLLocationCoordinate2D] = []
        var errors: [CLError.Code] = []
        var events: [String] = []
        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { changes += 1 }
        func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) { statuses.append(status) }
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            self.locations += locations.map(\.coordinate)
        }
        func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
            if let error = error as? CLError { errors.append(error.code) }
        }
        func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) { events.append("start \(region.identifier)") }
        func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
            events.append("state \(region.identifier) \(state.rawValue)")
        }
        func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { events.append("enter \(region.identifier)") }
        func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { events.append("exit \(region.identifier)") }
        func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {
            events.append("fail \(region?.identifier ?? "") \((error as? CLError)?.code.rawValue ?? -1)")
        }
        func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint, error: any Error) {
            events.append("ranging \((error as? CLError)?.code.rawValue ?? -1)")
        }
    }

    /// The browser: a permission state, pending one-shot requests and live watches.
    final class Browser {
        nonisolated(unsafe) static var state: String? = "prompt"
        nonisolated(unsafe) static var requests: [(highAccuracy: Bool, completion: _CoreLocationHost.Update)] = []
        nonisolated(unsafe) static var watches: [Int: (highAccuracy: Bool, update: _CoreLocationHost.Update)] = [:]
        nonisolated(unsafe) static var cleared: [Int] = []
        nonisolated(unsafe) static var nextID = 1
        /// Delivered to each new watch, after the call that made it returns.
        nonisolated(unsafe) static var queued: [Result<_CoreLocationHost.Position, _CoreLocationHost.Failure>] = []

        static func install() {
            state = "prompt"
            requests = []
            watches = [:]
            cleared = []
            queued = []
            _CoreLocationHost.permission = { Browser.state }
            _CoreLocationHost.locate = { high, completion in Browser.requests.append((high, completion)) }
            _CoreLocationHost.watch = { high, update in
                let id = Browser.nextID
                Browser.nextID += 1
                Browser.watches[id] = (high, update)
                let queued = Browser.queued
                if !queued.isEmpty { Task { @MainActor in for result in queued { update(result) } } }
                return id
            }
            _CoreLocationHost.clearWatch = { id in Browser.cleared.append(id); Browser.watches[id] = nil }
        }

        static func remove() {
            _CoreLocationHost.permission = nil
            _CoreLocationHost.locate = nil
            _CoreLocationHost.watch = nil
            _CoreLocationHost.clearWatch = nil
        }

        static func position(_ latitude: Double, _ longitude: Double) -> _CoreLocationHost.Position {
            _CoreLocationHost.Position(latitude: latitude, longitude: longitude, accuracy: 5, altitude: 12, altitudeAccuracy: 3,
                                       heading: .nan, speed: 1.5, timestamp: 1_700_000_000_000)
        }

        @MainActor static func answerRequest(_ result: Result<_CoreLocationHost.Position, _CoreLocationHost.Failure>) {
            requests.removeFirst().completion(result)
        }

        @MainActor static func move(to latitude: Double, _ longitude: Double) {
            for watch in watches.values { watch.update(.success(position(latitude, longitude))) }
        }
    }

    /// Callbacks are main-actor tasks after the call returns: waits, bounded, until `condition` holds.
    private func settled(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    private func manager(_ recorder: Recorder) async -> CLLocationManager {
        let manager = CLLocationManager()
        manager.delegate = recorder
        await settled { recorder.changes == 1 }
        return manager
    }

    @Test func withoutAHostServicesAreOffAndUpdatesFail() async {
        Browser.remove()
        CLLocationManager._resetForTesting()
        let recorder = Recorder()
        let manager = await manager(recorder)
        #expect(!CLLocationManager.locationServicesEnabled())
        #expect(recorder.statuses == [.notDetermined])   // setting the delegate reports the status
        manager.requestWhenInUseAuthorization()
        await settled { recorder.statuses.count == 2 }
        #expect(recorder.statuses == [.notDetermined, .denied] && manager.authorizationStatus == .denied)
        manager.startUpdatingLocation()
        manager.requestLocation()
        await settled { recorder.errors.count == 2 }
        #expect(recorder.errors == [.denied, .denied] && manager.location == nil)
        manager.startMonitoring(for: CLCircularRegion(center: CLLocationCoordinate2D(), radius: 100, identifier: "home"))
        await settled { !recorder.events.isEmpty }
        #expect(recorder.events == ["fail home 5"])
    }

    @Test func thePromptGrantsAndUpdatesFollowTheBrowser() async {
        Browser.install()
        CLLocationManager._resetForTesting()
        let recorder = Recorder()
        let manager = await manager(recorder)
        #expect(CLLocationManager.locationServicesEnabled() && manager.authorizationStatus == .notDetermined)
        manager.requestWhenInUseAuthorization()
        #expect(Browser.requests.count == 1 && Browser.requests[0].highAccuracy == false)
        Browser.answerRequest(.success(Browser.position(51.5, -0.12)))
        #expect(recorder.statuses == [.notDetermined, .authorizedWhenInUse] && recorder.changes == 2)
        // The prompt's position is the manager's location; it is not an update.
        #expect(manager.location?.coordinate == CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12) && recorder.locations.isEmpty)
        #expect(manager.location?.altitude == 12 && manager.location?.verticalAccuracy == 3 && manager.location?.speed == 1.5)
        #expect(manager.location?.course == -1 && manager.location?.timestamp == Date(timeIntervalSince1970: 1_700_000_000))

        manager.distanceFilter = 100
        manager.startUpdatingLocation()
        #expect(Browser.watches.count == 1 && Browser.watches.values.first?.highAccuracy == true)
        Browser.move(to: 0, 0)
        Browser.move(to: 0, 0.0005)   // about 56 m: filtered
        Browser.move(to: 0, 0.002)    // about 222 m from the last delivered
        #expect(recorder.locations == [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 0, longitude: 0.002)])
        let id = Browser.watches.keys.first!
        manager.stopUpdatingLocation()
        #expect(Browser.cleared == [id] && Browser.watches.isEmpty)

        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestLocation()
        #expect(Browser.requests.count == 1 && Browser.requests[0].highAccuracy == false)
        Browser.answerRequest(.failure(.timeout))
        #expect(recorder.errors == [.locationUnknown])
    }

    @Test func aRefusalIsDeniedAndThePermissionAPIWins() async {
        Browser.install()
        CLLocationManager._resetForTesting()
        let recorder = Recorder()
        let manager = await manager(recorder)
        manager.requestAlwaysAuthorization()
        Browser.answerRequest(.failure(.denied))
        #expect(manager.authorizationStatus == .denied && recorder.statuses == [.notDetermined, .denied])
        manager.requestWhenInUseAuthorization()   // decided: no second prompt
        #expect(Browser.requests.isEmpty)
        manager.requestLocation()
        Browser.answerRequest(.failure(.denied))
        let error = CLError(recorder.errors.first ?? .network)
        #expect(CLError.denied ~= error)
        // The user allows it in the browser's settings: the Permissions API reports the change.
        Browser.state = "granted"
        _CoreLocationHost.permissionDidChange()
        #expect(recorder.statuses.last == .authorizedWhenInUse && CLLocationManager.authorizationStatus() == .authorizedWhenInUse)
        _CoreLocationHost.permissionDidChange()   // unchanged: nothing reported
        #expect(recorder.statuses.count == 3)
    }

    @Test func circularRegionsAreEnteredAndLeft() async {
        Browser.install()
        CLLocationManager._resetForTesting()
        Browser.state = "granted"
        let recorder = Recorder()
        let manager = await manager(recorder)
        #expect(CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) && !CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self))
        let office = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 10, longitude: 10), radius: 200, identifier: "office")
        office.notifyOnEntry = true
        manager.startMonitoring(for: office)
        await settled { !recorder.events.isEmpty }
        #expect(recorder.events == ["start office"] && manager.monitoredRegions.count == 1 && Browser.watches.count == 1)
        Browser.move(to: 10, 10.001)   // about 110 m from the centre: inside, first known state
        Browser.move(to: 10, 10.01)    // about 1.1 km: left
        Browser.move(to: 10, 10)       // back
        #expect(recorder.events == ["start office", "state office 1", "exit office", "state office 2", "enter office", "state office 1"])
        #expect(recorder.locations.isEmpty)   // regions alone deliver no locations
        manager.stopMonitoring(for: office)
        #expect(Browser.watches.isEmpty && manager.monitoredRegions.isEmpty)

        recorder.events = []
        let beacons = CLBeaconRegion(uuid: UUID(), major: 1, identifier: "beacons")
        manager.startMonitoring(for: beacons)
        manager.startRangingBeacons(satisfying: beacons.beaconIdentityConstraint)
        await settled { recorder.events.count == 2 }
        #expect(recorder.events == ["fail beacons 5", "ranging 16"] && beacons.major == NSNumber(value: 1) && beacons.minor == nil)
    }

    @Test func liveUpdatesYieldTheBrowsersPositions() async throws {
        Browser.install()
        CLLocationManager._resetForTesting()
        Browser.queued = [.success(Browser.position(1, 2)), .failure(.denied)]
        var seen: [CLLocationUpdate] = []
        for try await update in CLLocationUpdate.liveUpdates(.fitness) {
            seen.append(update)
            if seen.count == 2 { break }
        }
        #expect(seen.count == 2 && Browser.nextID > 1)
        #expect(seen.first?.location?.coordinate == CLLocationCoordinate2D(latitude: 1, longitude: 2) && seen.first?.authorizationDenied == false)
        #expect(seen.last?.location == nil && seen.last?.authorizationDenied == true)
        // Leaving the loop ends the browser's watch.
        await settled { Browser.watches.isEmpty }
        #expect(Browser.watches.isEmpty && Browser.cleared.count == 1)
    }

    @Test func theGeocoderHasNoServiceAndCancels() async {
        let geocoder = CLGeocoder()
        var answers: [CLError.Code] = []
        geocoder.geocodeAddressString("1 Infinite Loop") { placemarks, error in
            #expect(placemarks == nil)
            answers.append((error as? CLError)?.code ?? .locationUnknown)
        }
        #expect(geocoder.isGeocoding)
        await settled { !answers.isEmpty }
        #expect(answers == [.network] && !geocoder.isGeocoding)
        geocoder.reverseGeocodeLocation(CLLocation(latitude: 1, longitude: 2)) { _, error in answers.append((error as? CLError)?.code ?? .locationUnknown) }
        geocoder.cancelGeocode()
        for _ in 0..<20 { await Task.yield() }
        #expect(answers == [.network, .geocodeCanceled])
        do {
            _ = try await CLGeocoder().geocodeAddressString("Cupertino")
            Issue.record("geocoded without a service")
        } catch {
            #expect(error as? CLError == CLError(.network))
        }
        let placemark = CLPlacemark(placemark: CLPlacemark(location: CLLocation(latitude: 1, longitude: 2), name: "Park", locality: "Town"))
        #expect(placemark.name == "Park" && placemark.locality == "Town" && placemark.location?.coordinate.latitude == 1)
    }

    @Test func valuesMatchApplesShapes() {
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.33233141, longitude: -122.0312186), altitude: 10,
                                  horizontalAccuracy: 5, verticalAccuracy: 2, course: 90, speed: 3, timestamp: Date(timeIntervalSince1970: 0))
        #expect(location.course == 90 && location.speed == 3 && location.courseAccuracy == -1 && location.floor == nil)
        #expect(location.description.hasPrefix("<+37.33233141,-122.03121860> +/- 5.00m (speed 3.00 mps / course 90.00) @ "))
        #expect(CLLocation(latitude: 1, longitude: 2).horizontalAccuracy == 0 && CLLocation(latitude: 1, longitude: 2).speed == -1)
        #expect(CLLocationCoordinate2DMake(1, 2) == CLLocationCoordinate2D(latitude: 1, longitude: 2))
        #expect(CLAuthorizationStatus.authorizedWhenInUse.rawValue == 4 && CLActivityType.fitness.rawValue == 3 && CLDeviceOrientation.faceDown.rawValue == 6)
        #expect(CLError.Code.geocodeFoundNoResult.rawValue == 8 && CLError.errorDomain == kCLErrorDomain && CLError(.network).errorCode == 2)
        #expect(CLError(.denied) == CLError(.denied) && CLError(.denied) != CLError(.network))
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), radius: 1000, identifier: "r")
        #expect(region.contains(CLLocationCoordinate2D(latitude: 0, longitude: 0.005)) && !region.contains(CLLocationCoordinate2D(latitude: 0, longitude: 0.02)))
        let uuid = UUID()
        #expect(CLBeaconIdentityConstraint(uuid: uuid, major: 1) == CLBeaconIdentityConstraint(uuid: uuid, major: 1))
        #expect(CLBeaconIdentityConstraint(uuid: uuid, major: 1) != CLBeaconIdentityConstraint(uuid: uuid, major: 1, minor: 2))
        #expect(kCLLocationAccuracyBest == -1 && kCLLocationAccuracyHundredMeters == 100 && CLLocationDistanceMax > 1e300)
    }
}
#endif
