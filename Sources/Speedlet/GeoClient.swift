import Foundation
import SpeedletCore

/// Fetches the current public IP + country from freeipapi. No IP param → the
/// service uses the request's egress IP. No key, HTTPS. No cache — each call is
/// a fresh request. 5s timeout; returns nil on timeout or any network/decoding
/// failure (the menu shows "Unavailable"). Cancellation propagates: when the
/// menu closes the caller cancels its Task, aborting the in-flight request.
struct GeoClient {
    private let endpoint = URL(string: "https://free.freeipapi.com/api/json")!

    func fetch() async -> GeoInfo? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(GeoInfo.self, from: data)
        } catch {
            return nil
        }
    }
}
