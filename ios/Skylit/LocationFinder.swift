import CoreLocation
import SkylitCore

enum LocationFailure: Error {
    case denied
    case unavailable

    var message: String {
        switch self {
        case .denied: return "Location access is off for Skylit. Search for your city instead, or allow it in Settings."
        case .unavailable: return "Couldn't work out where this phone is. Search for your city instead."
        }
    }
}

final class LocationFinder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func current() async throws -> FrameLocation {
        let fix: CLLocation = try await withCheckedThrowingContinuation { continuation in
            waiting?.resume(throwing: CancellationError())
            waiting = continuation
            proceed()
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(fix).first
        guard let name = placemark.flatMap(Self.cityName) else { throw LocationFailure.unavailable }
        return Self.frameLocation(name: name, fix.coordinate, placemark?.timeZone ?? .current)
    }

    static func search(_ text: String) async -> [FrameLocation] {
        let placemarks = (try? await CLGeocoder().geocodeAddressString(text)) ?? []
        return placemarks.compactMap { placemark in
            guard let coordinate = placemark.location?.coordinate, let name = cityName(placemark) else { return nil }
            let region = [placemark.administrativeArea, placemark.country].compactMap { $0 }.filter { $0 != name }.joined(separator: ", ")
            return frameLocation(name: region.isEmpty ? name : "\(name), \(region)", coordinate, placemark.timeZone)
        }
    }

    private static func cityName(_ placemark: CLPlacemark) -> String? {
        placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? placemark.name
    }

    private static func frameLocation(name: String, _ coordinate: CLLocationCoordinate2D, _ zone: TimeZone?) -> FrameLocation {
        FrameLocation(name: String(name.prefix(Limits.nameLength)),
                      latitude: (coordinate.latitude * 100).rounded() / 100,
                      longitude: (coordinate.longitude * 100).rounded() / 100,
                      timezone: zone?.identifier)
    }

    private func proceed() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(.failure(LocationFailure.denied))
        default: manager.requestLocation()
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        waiting?.resume(with: result)
        waiting = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if waiting != nil, manager.authorizationStatus != .notDetermined { proceed() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let fix = locations.last { finish(.success(fix)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(LocationFailure.unavailable))
    }
}
