import CoreLocation
import SwiftUI

/// Weather from Open-Meteo (free, no account or API key). Location comes from Core Location,
/// or from a city the user picks in Settings.
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Place: Codable, Equatable, Identifiable, Hashable {
        var name: String
        var detail: String
        var latitude: Double
        var longitude: Double
        var id: String { "\(latitude),\(longitude)" }
    }

    struct Current: Equatable {
        var temperature: Double
        var feelsLike: Double
        var code: Int
        var isDay: Bool
        var wind: Double
        var humidity: Double
    }

    struct Hour: Identifiable, Equatable {
        var id: Date { time }
        var time: Date
        var temperature: Double
        var code: Int
        var isDay: Bool
        var precipitation: Int
    }

    struct Day: Identifiable, Equatable {
        var id: Date { date }
        var date: Date
        var code: Int
        var high: Double
        var low: Double
        var precipitation: Int
    }

    enum Status: Equatable { case idle, loading, ready, needsLocation, failed(String) }

    @Published private(set) var current: Current?
    @Published private(set) var hours: [Hour] = []
    @Published private(set) var days: [Day] = []
    @Published private(set) var placeName: String?
    @Published private(set) var status: Status = .idle
    @Published private(set) var manualPlace: Place?
    @Published private(set) var useFahrenheit: Bool
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var timer: Timer?
    private var lastFetch: Date?
    private(set) var isRunning = false

    override init() {
        let defaults = UserDefaults.standard
        if let f = defaults.object(forKey: "weatherFahrenheit") as? Bool {
            useFahrenheit = f
        } else {
            useFahrenheit = Locale.current.measurementSystem == .us
        }
        if let data = defaults.data(forKey: "weatherPlace") {
            manualPlace = try? JSONDecoder().decode(Place.self, from: data)
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationStatus = manager.authorizationStatus
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning, !isDemoMode else { return }
        isRunning = true
        refresh()
        timer = Timer.every(15 * 60) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func refreshIfStale() {
        guard isRunning else { return }
        if lastFetch.map({ Date().timeIntervalSince($0) > 10 * 60 }) ?? true { refresh() }
    }

    func refresh() {
        if let p = manualPlace {
            placeName = p.name
            fetch(latitude: p.latitude, longitude: p.longitude)
        } else if let c = coordinate {
            fetch(latitude: c.latitude, longitude: c.longitude)
        } else {
            requestLocation()
        }
    }

    // MARK: Settings

    func setFahrenheit(_ on: Bool) {
        useFahrenheit = on
        UserDefaults.standard.set(on, forKey: "weatherFahrenheit")
        if isRunning { refresh() }
    }

    /// nil = use the Mac's location.
    func setPlace(_ place: Place?) {
        manualPlace = place
        if let place, let data = try? JSONEncoder().encode(place) {
            UserDefaults.standard.set(data, forKey: "weatherPlace")
        } else {
            UserDefaults.standard.removeObject(forKey: "weatherPlace")
            placeName = nil
        }
        current = nil
        if isRunning { refresh() }
    }

    func search(_ query: String, completion: @escaping ([Place]) -> Void) {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "6"),
                        .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en")]
        struct Response: Decodable {
            struct R: Decodable { let name: String; let latitude: Double; let longitude: Double; let admin1: String?; let country: String? }
            let results: [R]?
        }
        URLSession.shared.dataTask(with: c.url!) { data, _, _ in
            let results = data.flatMap { try? JSONDecoder().decode(Response.self, from: $0) }?.results ?? []
            let places = results.map {
                Place(name: $0.name, detail: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                      latitude: $0.latitude, longitude: $0.longitude)
            }
            DispatchQueue.main.async { completion(places) }
        }.resume()
    }

    // MARK: Location

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .loading
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .needsLocation
        default:
            status = current == nil ? .loading : status
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
        guard isRunning, manualPlace == nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: status = .needsLocation
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, manualPlace == nil else { return }
        coordinate = loc.coordinate
        fetch(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(loc) { [weak self] marks, _ in
            DispatchQueue.main.async {
                self?.placeName = marks?.first?.locality ?? marks?.first?.name
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manualPlace == nil, coordinate == nil else { return }
        status = manager.authorizationStatus == .denied ? .needsLocation : .failed("Couldn't find your location")
    }

    // MARK: Forecast

    private func fetch(latitude: Double, longitude: Double) {
        if current == nil { status = .loading }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", latitude)),
            .init(name: "longitude", value: String(format: "%.3f", longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "6"),
            .init(name: "temperature_unit", value: useFahrenheit ? "fahrenheit" : "celsius"),
            .init(name: "wind_speed_unit", value: useFahrenheit ? "mph" : "kmh"),
        ]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, error in
            let parsed = data.flatMap { try? JSONDecoder().decode(ForecastResponse.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let parsed else {
                    if self.current == nil { self.status = .failed(error == nil ? "Weather unavailable" : "You're offline") }
                    return
                }
                self.apply(parsed)
            }
        }.resume()
    }

    private func apply(_ r: ForecastResponse) {
        let tz = TimeZone(secondsFromGMT: r.utc_offset_seconds) ?? .current
        let hourFmt = DateFormatter()
        hourFmt.locale = Locale(identifier: "en_US_POSIX")
        hourFmt.timeZone = tz
        hourFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let dayFmt = DateFormatter()
        dayFmt.locale = hourFmt.locale
        dayFmt.timeZone = tz
        dayFmt.dateFormat = "yyyy-MM-dd"

        current = Current(temperature: r.current.temperature_2m, feelsLike: r.current.apparent_temperature,
                          code: r.current.weather_code, isDay: r.current.is_day == 1,
                          wind: r.current.wind_speed_10m, humidity: r.current.relative_humidity_2m)
        let now = Date().addingTimeInterval(-3600)
        hours = r.hourly.time.indices.compactMap { i -> Hour? in
            guard let t = hourFmt.date(from: r.hourly.time[i]), t > now else { return nil }
            return Hour(time: t, temperature: r.hourly.temperature_2m[i], code: r.hourly.weather_code[i],
                        isDay: (r.hourly.is_day[safe: i] ?? 1) == 1,
                        precipitation: r.hourly.precipitation_probability?[safe: i].flatMap { $0 } ?? 0)
        }.prefix(8).map { $0 }
        days = r.daily.time.indices.compactMap { i -> Day? in
            guard let d = dayFmt.date(from: r.daily.time[i]) else { return nil }
            return Day(date: d, code: r.daily.weather_code[i], high: r.daily.temperature_2m_max[i],
                       low: r.daily.temperature_2m_min[i],
                       precipitation: r.daily.precipitation_probability_max?[safe: i].flatMap { $0 } ?? 0)
        }
        lastFetch = Date()
        status = .ready
    }

    func applyDemo() {
        placeName = "Cupertino"
        current = Current(temperature: 68, feelsLike: 67, code: 1, isDay: true, wind: 6, humidity: 48)
        let base = Calendar.current.date(bySetting: .minute, value: 0, of: Date()) ?? Date()
        let temps: [Double] = [68, 70, 71, 71, 69, 66, 63, 61]
        let codes = [1, 1, 2, 2, 3, 3, 61, 61]
        hours = temps.indices.map { Hour(time: base.addingTimeInterval(Double($0) * 3600), temperature: temps[$0],
                                         code: codes[$0], isDay: $0 < 5, precipitation: $0 >= 6 ? 60 : 5) }
        let dayData: [(Int, Double, Double)] = [(1, 72, 54), (61, 64, 51), (3, 66, 50), (0, 74, 53), (2, 71, 55), (0, 75, 56)]
        let today = Calendar.current.startOfDay(for: Date())
        days = dayData.indices.map {
            Day(date: today.addingTimeInterval(Double($0) * 86400), code: dayData[$0].0, high: dayData[$0].1,
                low: dayData[$0].2, precipitation: dayData[$0].0 == 61 ? 70 : 10)
        }
        useFahrenheit = true
        status = .ready
    }

    // MARK: Formatting

    func format(_ t: Double) -> String { "\(Int(t.rounded()))°" }

    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func describe(code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 65, 82: "Heavy Rain"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorms"
        default: "—"
        }
    }
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let weather_code: Int
        let is_day: Int
        let wind_speed_10m: Double
        let relative_humidity_2m: Double
    }
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
        let precipitation_probability: [Int?]?
        let is_day: [Int]
    }
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int?]?
    }
    let utc_offset_seconds: Int
    let current: Current
    let hourly: Hourly
    let daily: Daily
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
