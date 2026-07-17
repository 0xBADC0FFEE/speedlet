import Foundation

/// Persisted opt-in for auto-running the speed test on network change. Off by
/// default (absent key reads as `false`), so the "only phones home when I open
/// the menu" invariant holds until the user opts in. Mirrors `LaunchAtLogin`'s
/// shape: a thin static wrapper over the system store.
enum AutoRunPreference {
    private static let key = "autoRunOnNetworkChange"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }
}
