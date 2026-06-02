import Foundation
import SpeedletCore

/// Fetches the current public IP + country from freeipapi. No IP param → the
/// service uses the request's egress IP. No key, HTTPS. No cache — each call is
/// a fresh request. Returns nil on any failure (the menu shows "Unavailable").
struct GeoClient {
    private let endpoint = URL(string: "https://free.freeipapi.com/api/json")!

    func fetch() async -> GeoInfo? {
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(GeoInfo.self, from: data)
        } catch {
            return nil
        }
    }
}
