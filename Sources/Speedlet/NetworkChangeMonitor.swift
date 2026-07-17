import Foundation
import Network
import SpeedletCore

/// Watches the system network path and signals a change in two phases. Dumb
/// plumbing around the pure core (`PathFingerprint` / `evaluate`): builds a
/// fingerprint per `NWPath` update, classifies the transition, and on `.changed`
/// fires `onChangeBegan` at once (leading edge of a burst), then `onChangeSettled`
/// after the path goes quiet (trailing). Holds no policy — the caller decides
/// what each phase means. Both closures run on the main queue.
///
/// Two phases because one user action surfaces as *several distinct* states and
/// the right response differs per phase:
/// - **Began** — the moment anything moves, so the caller can stop a stale run
///   immediately (a VPN switch's first event is tunnel-down; keeping the old
///   test alive through the settle window would show a stale reading).
/// - **Settled** — once quiet, so the caller starts a fresh run against the
///   *final* state. A server switch is tunnel-down (egress = home IP) then
///   tunnel-up (egress = new server) ~770ms later; starting on settle means the
///   run and its geo lookup reflect the new server, not the transitional
///   home-country state.
///
/// All monitor state lives on a single serial queue; `NWPathMonitor` delivers
/// its callbacks there too, so the fingerprint, the previous snapshot, and the
/// settle timer share one isolation domain.
final class NetworkChangeMonitor {
    /// Trailing settle window. Must exceed the gap between a single action's
    /// phases, or `onChangeSettled` fires on the transitional state — the probe
    /// (#13) measured a server switch's teardown→recreate spread ~770ms, so 1s
    /// sits ~230ms above it. The one tuning knob: widen it if a switch still
    /// settles on the old country (slow tunnel), shorten it for snappier
    /// single-phase changes.
    static let settleWindow: TimeInterval = 1.0

    private let onChangeBegan: () -> Void
    private let onChangeSettled: () -> Void
    private let queue = DispatchQueue(label: "dev.vawerv.speedlet.pathmonitor")
    private var monitor: NWPathMonitor?
    private var previous: PathFingerprint?
    private var settle: DispatchWorkItem?

    init(onChangeBegan: @escaping () -> Void, onChangeSettled: @escaping () -> Void) {
        self.onChangeBegan = onChangeBegan
        self.onChangeSettled = onChangeSettled
    }

    /// Begin watching. The first callback seeds the baseline (`.baseline`) and
    /// does not fire, so enabling the feature is quiet until the path changes.
    /// Idempotent: a second call while running is a no-op.
    func start() {
        queue.async { [weak self] in
            guard let self, self.monitor == nil else { return }
            let monitor = NWPathMonitor()
            self.previous = nil
            monitor.pathUpdateHandler = { [weak self] path in self?.handle(path) }
            self.monitor = monitor
            monitor.start(queue: self.queue)
        }
    }

    /// Stop watching and drop any pending settle fire. Does not touch a run
    /// already in flight — that's the caller's concern.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.monitor?.cancel()
            self.monitor = nil
            self.settle?.cancel()
            self.settle = nil
        }
    }

    // Runs on `queue`.
    private func handle(_ path: NWPath) {
        let current = fingerprint(from: path)
        let change = evaluate(previous: previous, current: current)
        previous = current
        guard change == .changed else { return }

        // No timer armed → this is the leading edge of a fresh burst.
        if settle == nil {
            DispatchQueue.main.async { [weak self] in self?.onChangeBegan() }
        }
        // Re-arm on each change so the settle fires once, after the path quiets.
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.settle = nil   // burst over; the next change is a new leading edge
            DispatchQueue.main.async { self?.onChangeSettled() }
        }
        settle = work
        queue.asyncAfter(deadline: .now() + Self.settleWindow, execute: work)
    }

    private func fingerprint(from path: NWPath) -> PathFingerprint {
        // Raw lists straight from NWPath; PathFingerprint does the de-dup and
        // order-insensitivity, so the change rule stays wholly in the tested core.
        // A gateway's identity is its opaque description — enough for equality.
        PathFingerprint(
            interfaces: path.availableInterfaces.map(\.name),
            gateways: path.gateways.map { String(describing: $0) }
        )
    }
}
