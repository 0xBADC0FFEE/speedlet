import Foundation
import Network
import SpeedletCore

/// Watches the system network path and fires `onChange` once the path settles
/// after a real change. Dumb plumbing around the pure core (`PathFingerprint` /
/// `evaluate`): builds a fingerprint per `NWPath` update, classifies the
/// transition, and applies a trailing debounce. Holds no policy about what to do
/// on change — that's the caller's `onChange`, invoked on the main queue.
///
/// All monitor state lives on a single serial queue; `NWPathMonitor` delivers
/// its callbacks there too, so the fingerprint, the previous snapshot, and the
/// debounce timer share one isolation domain.
final class NetworkChangeMonitor {
    /// Trailing debounce window. A single connect emits a burst of path events,
    /// and a VPN server switch tears the tunnel down and back up (~770ms spread
    /// measured in the probe, #13); 1s of path-quiet coalesces either into one
    /// run. Sits ~230ms above the observed switch spread — the one tuning knob:
    /// widen it if a server switch ever yields a double run.
    static let debounceInterval: TimeInterval = 1.0

    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "dev.vawerv.speedlet.pathmonitor")
    private var monitor: NWPathMonitor?
    private var previous: PathFingerprint?
    private var debounce: DispatchWorkItem?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
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

    /// Stop watching and drop any pending debounced fire. Does not touch a run
    /// already in flight — that's the caller's concern.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.monitor?.cancel()
            self.monitor = nil
            self.debounce?.cancel()
            self.debounce = nil
        }
    }

    // Runs on `queue`.
    private func handle(_ path: NWPath) {
        let current = fingerprint(from: path)
        let change = evaluate(previous: previous, current: current)
        previous = current
        guard change == .changed else { return }

        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
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
