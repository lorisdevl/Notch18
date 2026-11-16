import Foundation
import SwiftUI

struct HourForecast: Identifiable {
    let id = UUID()
    let date: Date
    let temp: Double
    let code: Int
    let rain: Int?
}

struct WeatherData {
    let temp: Double
    let feels: Double
    let code: Int
    let isDay: Bool
    let wind: Double
    let gusts: Double?
    let humidity: Double?
    let max: Double
    let min: Double
    let rainProb: Int?
    let hours: [HourForecast]
}

private struct GeoResponse: Decodable { let results: [GeoResult]? }
private struct GeoResult: Decodable { let name: String; let latitude: Double; let longitude: Double }

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double?
        let weather_code: Int
        let wind_speed_10m: Double?
        let wind_gusts_10m: Double?
        let is_day: Int?
        let relative_humidity_2m: Double?
    }
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double?]
        let weather_code: [Int?]
        let precipitation_probability: [Double?]?
    }
    struct Daily: Decodable {
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let precipitation_probability_max: [Double?]?
    }
    let utc_offset_seconds: Int?
    let current: Current
    let hourly: Hourly
    let daily: Daily
}

/// Météo via Open-Meteo (gratuit, sans clé ni compte).
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published var data: WeatherData?
    @Published var cityLabel = ""
    @Published var error: String?
    private var timer: Timer?

    func start() {
        refresh()
        let t = Timer(timeInterval: 900, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh(force: Bool = false) {
        let d = UserDefaults.standard
        let city = (d.string(forKey: "weatherCity") ?? "Nantes").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { return }
        if !force, d.string(forKey: "weatherGeoCity") == city, d.object(forKey: "weatherLat") != nil {
            fetch(lat: d.double(forKey: "weatherLat"), lon: d.double(forKey: "weatherLon"),
                  label: d.string(forKey: "weatherLabel") ?? city)
        } else {
            geocode(city)
        }
    }

    private func geocode(_ city: String) {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "fr"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let res = try? JSONDecoder().decode(GeoResponse.self, from: data),
                  let g = res.results?.first else {
                DispatchQueue.main.async { self.error = "Ville « \(city) » introuvable" }
                return
            }
            DispatchQueue.main.async {
                let d = UserDefaults.standard
                d.set(city, forKey: "weatherGeoCity")
                d.set(g.latitude, forKey: "weatherLat")
                d.set(g.longitude, forKey: "weatherLon")
                d.set(g.name, forKey: "weatherLabel")
                self.fetch(lat: g.latitude, lon: g.longitude, label: g.name)
            }
        }.resume()
    }

    private func fetch(lat: Double, lon: Double, label: String) {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,wind_gusts_10m,is_day,relative_humidity_2m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data, let r = try? JSONDecoder().decode(ForecastResponse.self, from: data) else {
                DispatchQueue.main.async { self.error = "Météo indisponible" }
                return
            }
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
            parser.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds ?? 0)
            let now = Date()
            var hours: [HourForecast] = []
            for (i, t) in r.hourly.time.enumerated() {
                guard let date = parser.date(from: t), date > now,
                      i < r.hourly.temperature_2m.count, let temp = r.hourly.temperature_2m[i] else { continue }
                let code = i < r.hourly.weather_code.count ? (r.hourly.weather_code[i] ?? 0) : 0
                let rain = r.hourly.precipitation_probability.flatMap { i < $0.count ? $0[i] : nil }.map { Int($0) }
                hours.append(HourForecast(date: date, temp: temp, code: code, rain: rain))
                if hours.count >= 6 { break }
            }
            let weather = WeatherData(
                temp: r.current.temperature_2m,
                feels: r.current.apparent_temperature ?? r.current.temperature_2m,
                code: r.current.weather_code,
                isDay: (r.current.is_day ?? 1) == 1,
                wind: r.current.wind_speed_10m ?? 0,
                gusts: r.current.wind_gusts_10m,
                humidity: r.current.relative_humidity_2m,
                max: (r.daily.temperature_2m_max.first ?? nil) ?? r.current.temperature_2m,
                min: (r.daily.temperature_2m_min.first ?? nil) ?? r.current.temperature_2m,
                rainProb: (r.daily.precipitation_probability_max?.first ?? nil).map { Int($0) },
                hours: hours)
            DispatchQueue.main.async {
                self.data = weather
                self.cityLabel = label
                self.error = nil
            }
        }.resume()
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66: return "cloud.rain.fill"
        case 65, 67, 80, 81, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Ciel dégagé"
        case 1: return "Plutôt dégagé"
        case 2: return "Partiellement nuageux"
        case 3: return "Couvert"
        case 45, 48: return "Brouillard"
        case 51, 53, 55: return "Bruine"
        case 56, 57: return "Bruine verglaçante"
        case 61: return "Pluie faible"
        case 63: return "Pluie"
        case 65: return "Forte pluie"
        case 66, 67: return "Pluie verglaçante"
        case 71, 73, 75, 77: return "Neige"
        case 80, 81: return "Averses"
        case 82: return "Fortes averses"
        case 85, 86: return "Averses de neige"
        case 95: return "Orage"
        case 96, 99: return "Orage avec grêle"
        default: return "—"
        }
    }
}
