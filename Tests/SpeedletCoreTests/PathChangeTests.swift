import Testing
@testable import SpeedletCore

// The pure decision core: given a previous and current path descriptor, which
// outcome? Mirrors GeoTests — value-type equality, table-driven, no AppKit.

@Test func firstObservationSeedsBaseline() {
    let current = PathFingerprint(interfaces: ["en0"], gateways: ["192.168.1.1"])
    #expect(evaluate(previous: nil, current: current) == .baseline)
}

@Test func identicalFingerprintIsUnchanged() {
    let fp = PathFingerprint(interfaces: ["en0"], gateways: ["192.168.1.1"])
    #expect(evaluate(previous: fp, current: fp) == .unchanged)
}

@Test func addedTunInterfaceIsChanged() {
    let before = PathFingerprint(interfaces: ["en0"], gateways: ["192.168.1.1"])
    let after = PathFingerprint(interfaces: ["en0", "utun4"], gateways: ["192.168.1.1"])
    #expect(evaluate(previous: before, current: after) == .changed)
}

@Test func removedTunInterfaceIsChanged() {
    let before = PathFingerprint(interfaces: ["en0", "utun4"], gateways: ["192.168.1.1"])
    let after = PathFingerprint(interfaces: ["en0"], gateways: ["192.168.1.1"])
    #expect(evaluate(previous: before, current: after) == .changed)
}

@Test func sameInterfacesDifferentGatewayIsChanged() {
    let home = PathFingerprint(interfaces: ["en0"], gateways: ["192.168.1.1"])
    let cafe = PathFingerprint(interfaces: ["en0"], gateways: ["10.0.0.1"])
    #expect(evaluate(previous: home, current: cafe) == .changed)
}

// The probe showed NWPath lists each interface once per IPv4/IPv6 endpoint, so
// `en0, en0` must fold to a single `en0` — otherwise a dual-stack callback would
// read as a change against a single-stack one.
@Test func fingerprintDeDuplicatesRepeatedInterfaceNames() {
    let doubled = PathFingerprint(interfaces: ["en0", "en0"], gateways: ["192.168.1.1"])
    let single = PathFingerprint(interfaces: ["en0"], gateways: ["192.168.1.1"])
    #expect(doubled == single)
}

@Test func fingerprintIgnoresInterfaceOrder() {
    let a = PathFingerprint(interfaces: ["en0", "utun4"], gateways: [])
    let b = PathFingerprint(interfaces: ["utun4", "en0"], gateways: [])
    #expect(a == b)
}

// Same normalization for gateways, so raw NWPath.gateways ordering/duplication
// never reads as a change — the rule stays wholly in the pure core.
@Test func fingerprintNormalizesGatewayOrderAndDuplicates() {
    let a = PathFingerprint(interfaces: ["en0"], gateways: ["fe80::1", "192.168.1.1", "192.168.1.1"])
    let b = PathFingerprint(interfaces: ["en0"], gateways: ["192.168.1.1", "fe80::1"])
    #expect(a == b)
}

@Test func fingerprintsDifferByGateway() {
    let a = PathFingerprint(interfaces: ["en0"], gateways: ["192.168.1.1"])
    let b = PathFingerprint(interfaces: ["en0"], gateways: [])
    #expect(a != b)
}
