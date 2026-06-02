/// Geolocation value decoded from freeipapi and the pure helpers that turn it
/// into a menu row. No AppKit/Foundation UI — kept testable in isolation.

public struct GeoInfo: Decodable, Equatable, Sendable {
    public let ipAddress: String
    public let countryName: String
    public let countryCode: String

    public init(ipAddress: String, countryName: String, countryCode: String) {
        self.ipAddress = ipAddress
        self.countryName = countryName
        self.countryCode = countryCode
    }
}

/// Globe shown when a code can't map to a flag — never crash, always renderable.
public let fallbackFlag = "🌐"

/// Derive a flag emoji from an ISO 3166-1 alpha-2 code via regional-indicator
/// arithmetic ('A' 0x41 → 🇦 0x1F1E6). Lowercase tolerated; anything that isn't
/// exactly two ASCII letters falls back to the globe.
public func flagEmoji(for countryCode: String) -> String {
    let code = countryCode.uppercased()
    let letters = Array(code.unicodeScalars)
    guard letters.count == 2, letters.allSatisfy({ $0.value >= 0x41 && $0.value <= 0x5A }) else {
        return fallbackFlag
    }
    var view = String.UnicodeScalarView()
    for letter in letters {
        guard let scalar = Unicode.Scalar(0x1F1E6 + letter.value - 0x41) else { return fallbackFlag }
        view.append(scalar)
    }
    return String(view)
}

/// Assemble the disabled top row: `{flag} {country} · {ip}` (middle-dot separator).
public func displayLine(_ info: GeoInfo) -> String {
    "\(flagEmoji(for: info.countryCode)) \(info.countryName) · \(info.ipAddress)"
}
