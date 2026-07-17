import Foundation
import Darwin

enum SpeedTestState {
    case idle
    case starting
    case running(Int)
}

final class SpeedTestRunner {
    private var process: Process?
    private var masterHandle: FileHandle?
    private var buffer = ""
    // Set by restart() before terminating a live run; the termination handler
    // then flashes idle and relaunches instead of just settling to idle.
    private var restartPending = false
    private let onState: (SpeedTestState) -> Void

    private static let downlinkRegex = try! NSRegularExpression(
        pattern: #"Downlink:?\s*capacity:?\s+([\d.]+)\s+Mbps"#
    )

    // On restart, hold the idle icon this long before relaunching, so the stop
    // reads as a clear visible beat (stop → idle → start) rather than a seamless
    // swap. Tuning knob for how long the idle icon shows between runs.
    private static let restartFlashDelay: TimeInterval = 0.3

    init(onState: @escaping (SpeedTestState) -> Void) {
        self.onState = onState
    }

    var isRunning: Bool { process != nil }

    func start() {
        guard process == nil else { return }

        var master: Int32 = -1
        var slave: Int32 = -1
        // networkQuality only streams per-second "Downlink: capacity X.XXX Mbps"
        // lines when its stdout is a tty. Piped stdout gives a single end-of-run
        // summary instead — useless for live updates. So give it a pty slave.
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            NSLog("Speedlet: openpty failed (errno \(errno))")
            DispatchQueue.main.async { self.onState(.idle) }
            return
        }

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        proc.arguments = ["-v", "-s", "-u"]
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle

        masterHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self?.ingest(chunk)
        }

        proc.terminationHandler = { [weak self] _ in
            masterHandle.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.process = nil
                self?.masterHandle = nil
                self?.buffer = ""
                self?.onState(.idle)
                if self?.restartPending == true {
                    self?.restartPending = false
                    // Show idle briefly, then relaunch (process is now nil, so
                    // start()'s guard passes).
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartFlashDelay) {
                        self?.start()
                    }
                }
            }
        }

        do {
            try proc.run()
        } catch {
            NSLog("Speedlet: failed to start networkQuality: \(error)")
            close(slave)
            DispatchQueue.main.async { self.onState(.idle) }
            return
        }

        close(slave)
        self.process = proc
        self.masterHandle = masterHandle
        DispatchQueue.main.async { self.onState(.starting) }
    }

    func stop() {
        process?.terminate()
    }

    /// Stop the live run (if any) and start a fresh one right after it exits,
    /// with a brief visible idle in between. If idle, start immediately. Used by
    /// auto-run so a network change swaps to a new test with a short, deliberate
    /// gap rather than the full settle window.
    func restart() {
        guard let proc = process else {
            start()
            return
        }
        restartPending = true
        proc.terminate()
    }

    func stopAndWait() {
        guard let proc = process else { return }
        proc.terminate()
        proc.waitUntilExit()
    }

    private func ingest(_ chunk: String) {
        buffer += chunk
        let ns = buffer as NSString
        let matches = Self.downlinkRegex.matches(in: buffer, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last,
              let valueRange = Range(last.range(at: 1), in: buffer),
              let value = Double(buffer[valueRange]) else { return }
        let mbps = Int(value.rounded())
        DispatchQueue.main.async { self.onState(.running(mbps)) }
        let lastEnd = last.range.upperBound
        if lastEnd <= ns.length {
            buffer = ns.substring(from: lastEnd)
        }
    }
}
