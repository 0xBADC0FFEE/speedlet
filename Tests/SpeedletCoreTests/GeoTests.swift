import Foundation
import Testing
@testable import SpeedletCore

@Test func decodesFreeipapiPayload() throws {
    let json = """
    {
      "ipVersion": 4,
      "ipAddress": "203.0.113.7",
      "latitude": 52.3676,
      "longitude": 4.9041,
      "countryName": "Netherlands",
      "countryCode": "NL",
      "isProxy": false
    }
    """.data(using: .utf8)!

    let info = try JSONDecoder().decode(GeoInfo.self, from: json)
    #expect(info == GeoInfo(ipAddress: "203.0.113.7", countryName: "Netherlands", countryCode: "NL"))
}

@Test func decodesIPv6Verbatim() throws {
    let json = #"{"ipAddress":"2001:db8::1","countryName":"Germany","countryCode":"DE"}"#.data(using: .utf8)!
    let info = try JSONDecoder().decode(GeoInfo.self, from: json)
    #expect(info.ipAddress == "2001:db8::1")
}

@Test func flagFromUppercaseCode() {
    #expect(flagEmoji(for: "NL") == "🇳🇱")
}

@Test func flagToleratesLowercase() {
    #expect(flagEmoji(for: "nl") == "🇳🇱")
}

@Test(arguments: ["", "N", "USA", "U1", "12", "  "])
func flagFallsBackForInvalidCode(_ code: String) {
    #expect(flagEmoji(for: code) == fallbackFlag)
}

@Test func displayLineAssemblesWithMiddleDot() {
    let info = GeoInfo(ipAddress: "203.0.113.7", countryName: "Netherlands", countryCode: "NL")
    #expect(displayLine(info) == "🇳🇱 Netherlands · 203.0.113.7")
}
