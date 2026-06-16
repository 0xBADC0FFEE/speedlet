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

/// Flag for the status bar: a real flag emoji for a valid 2-letter code, or
/// `nil` for anything `flagEmoji` would resolve to the globe fallback. Unlike
/// `flagEmoji`, the status bar wants flag-or-nothing (no `🌐` placeholder).
public func statusBarFlag(for countryCode: String?) -> String? {
    guard let countryCode else { return nil }
    let flag = flagEmoji(for: countryCode)
    return flag == fallbackFlag ? nil : flag
}

/// Text half of the geo row: `{country} · {ip}` (middle-dot separator). The
/// flag renders separately in the row's icon gutter, so it's not included here.
public func detailLine(_ info: GeoInfo) -> String {
    "\(info.countryName) · \(info.ipAddress)"
}
