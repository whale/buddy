import Foundation
import Observation
import SwiftUI

// MARK: - WeatherService
// A calm ornament in the date header — a faithful port of the Mac's weather logic:
// IP-based location (ipwho.is, no permission prompt) → Open-Meteo current weather_code +
// is_day → a Lucide glyph key (wx-<key> assets). Caches the last-known for 1h in
// UserDefaults and paints it instantly; every failure is silent (keep the last icon).
@Observable
final class WeatherService {
    var iconKey: String = "moon"          // shown until a fetch resolves

    private let cacheKey = "buddy.weather.v1"
    private struct Cache: Codable { var ts: Double; var key: String }

    init() { if let c = load() { iconKey = c.key } }

    /// Paint last-known instantly; fetch only if forced or the cache is older than an hour.
    func refresh(force: Bool = false) {
        if let c = load() {
            iconKey = c.key
            if !force, Date().timeIntervalSince1970 - c.ts < 3600 { return }
        }
        Task { await fetch() }
    }

    private func fetch() async {
        do {
            let loc = try await geoIP()
            let w = try await forecast(lat: loc.0, lon: loc.1)
            await MainActor.run {
                iconKey = Self.key(code: w.0, isDay: w.1)
                save(Cache(ts: Date().timeIntervalSince1970, key: iconKey))
            }
        } catch { /* silent — keep whatever is shown */ }
    }

    private func geoIP() async throws -> (Double, Double) {
        struct R: Codable { var latitude: Double?; var longitude: Double?; var success: Bool? }
        let url = URL(string: "https://ipwho.is/?fields=latitude,longitude,success")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let r = try JSONDecoder().decode(R.self, from: data)
        guard r.success != false, let lat = r.latitude, let lon = r.longitude else { throw URLError(.badServerResponse) }
        return (lat, lon)
    }

    private func forecast(lat: Double, lon: Double) async throws -> (Int, Bool) {
        struct Cur: Codable { var weather_code: Int; var is_day: Int }
        struct R: Codable { var current: Cur }
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=weather_code,is_day")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let r = try JSONDecoder().decode(R.self, from: data)
        return (r.current.weather_code, r.current.is_day == 1)
    }

    // Open-Meteo WMO weathercode → icon key (day/night aware). Mirrors the Mac wxKey().
    static func key(code: Int, isDay: Bool) -> String {
        switch code {
        case 0:                return isDay ? "sun" : "moon"
        case 1, 2:             return isDay ? "cloud-sun" : "cloud-moon"
        case 3:                return "cloud"
        case 45, 48:           return "cloud-fog"
        case 51...55:          return "cloud-drizzle"
        case 56, 57, 66, 67:   return "cloud-hail"
        case 61...65:          return "cloud-rain"
        case 71...77, 85, 86:  return "cloud-snow"
        case 80...82:          return isDay ? "cloud-sun-rain" : "cloud-moon-rain"
        case 95...:            return "cloud-lightning"
        default:               return isDay ? "cloud-sun" : "cloud-moon"
        }
    }

    private func load() -> Cache? {
        guard let d = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: d)
    }
    private func save(_ c: Cache) {
        if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: cacheKey) }
    }
}

// MARK: - Weather glyph
struct WeatherIcon: View {
    let key: String
    let size: CGFloat
    var body: some View {
        Image("wx-\(key)").renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size)
    }
}
