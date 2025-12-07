import Foundation
import Combine
import CoreLocation

@MainActor
final class HomeViewModel: NSObject, ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case success
        case error(String)
    }

    @Published var location: CLLocation?
    @Published var weather: Weather?
    @Published var recommendation: Recommendation?
    @Published var state: LoadState = .idle

    private let api = APIClient.shared
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        // Request authorization and attempt to get a location
        let status = CLLocationManager.authorizationStatus()
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        } else {
            // Do nothing for denied — the app UI should handle prompting
        }
    }

    func refresh() async {
        guard let loc = location else {
            // If we don't have a location, request one and let delegate trigger fetch
            locationManager.requestLocation()
            return
        }

        await fetchWeatherAndRecommendation(for: loc.coordinate)
    }

    private func fetchWeatherAndRecommendation(for coord: CLLocationCoordinate2D) async {
        state = .loading

        do {
            async let w = api.fetchWeather(latitude: coord.latitude, longitude: coord.longitude)
            async let r = api.recommend(latitude: coord.latitude, longitude: coord.longitude)

            let (weatherRes, recRes) = try await (w, r)

            self.weather = weatherRes
            self.recommendation = recRes
            state = .success
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension HomeViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            await self.fetchWeatherAndRecommendation(for: loc.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .error(error.localizedDescription)
        }
    }

    // confirmWearメソッドを追加 (着用ボタン用)
    func confirmWear() async {
        guard let rec = recommendation else { return }
        let ids = rec.clothes.map { $0.id }
        do {
            try await api.wear(clothIds: ids)
            // 成功したら状態をリセットしたり、トーストを出すなど
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
