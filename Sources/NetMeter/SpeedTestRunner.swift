import Foundation
import Darwin

final class SpeedTestRunner {
    private var process: Process?
    private var masterHandle: FileHandle?
    private var buffer = ""
    private let onMbps: (Int) -> Void
    private let onExit: () -> Void

    private static let downlinkRegex = try! NSRegularExpression(
        pattern: #"Downlink:?\s*capacity:?\s+([\d.]+)\s+Mbps"#
    )

    init(onMbps: @escaping (Int) -> Void, onExit: @escaping () -> Void) {
        self.onMbps = onMbps
        self.onExit = onExit
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
            NSLog("NetMeter: openpty failed (errno \(errno))")
            DispatchQueue.main.async { self.onExit() }
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
                self?.onExit()
            }
        }

        do {
            try proc.run()
        } catch {
            NSLog("NetMeter: failed to start networkQuality: \(error)")
            close(slave)
            DispatchQueue.main.async { self.onExit() }
            return
        }

        close(slave)
        self.process = proc
        self.masterHandle = masterHandle
    }

    func stop() {
        process?.terminate()
    }

    private func ingest(_ chunk: String) {
        buffer += chunk
        let ns = buffer as NSString
        let matches = Self.downlinkRegex.matches(in: buffer, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last,
              let valueRange = Range(last.range(at: 1), in: buffer),
              let value = Double(buffer[valueRange]) else { return }
        let mbps = Int(value.rounded())
        DispatchQueue.main.async { self.onMbps(mbps) }
        let lastEnd = last.range.upperBound
        if lastEnd <= ns.length {
            buffer = ns.substring(from: lastEnd)
        }
    }
}
