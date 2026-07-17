/// The pure decision core for auto-run on network change: a value type that
/// fingerprints a network path and a function that classifies the transition
/// between two fingerprints. No `NWPathMonitor`, no timers, no AppKit — kept
/// testable in isolation, mirroring the `GeoInfo`/`flagEmoji` split.

/// A snapshot of what makes one network path distinct from another: the set of
/// active interface names plus the set of gateways. Both are stored as `Set`s so
/// repeated entries collapse (`NWPath` lists each interface once per IPv4/IPv6
/// endpoint, e.g. `en0, en0`) and order never matters — the whole "what counts
/// as a change" rule, normalization included, lives here in the tested core.
/// Captures both {interfaces} and {gateways} so it fires on VPN attach/detach
/// (interface set changes) and Wi-Fi↔Wi-Fi roaming (gateway changes).
public struct PathFingerprint: Equatable, Sendable {
    public let interfaces: Set<String>
    public let gateways: Set<String>

    public init(interfaces: [String], gateways: [String]) {
        self.interfaces = Set(interfaces)
        self.gateways = Set(gateways)
    }
}

/// The three outcomes of observing a path update.
public enum PathChange: Equatable, Sendable {
    /// First observation — seed the fingerprint, do NOT fire.
    case baseline
    /// Identical to the last fingerprint — drop the duplicate callback.
    case unchanged
    /// A real change — fire (debounced).
    case changed
}

/// Classify a path update against the previously seen fingerprint.
public func evaluate(previous: PathFingerprint?, current: PathFingerprint) -> PathChange {
    guard let previous else { return .baseline }
    return previous == current ? .unchanged : .changed
}
