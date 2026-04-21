import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let idleIcon: NSImage?
    private var runner: SpeedTestRunner!

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        idleIcon = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "NetMeter")
        idleIcon?.isTemplate = true
        super.init()
        runner = SpeedTestRunner(
            onMbps: { [weak self] mbps in self?.showMbps(mbps) },
            onExit: { [weak self] in self?.showIdle() }
        )
        showIdle()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(didClick)
    }

    @objc private func didClick() {
        if runner.isRunning {
            runner.stop()
        } else {
            runner.start()
        }
    }

    private func showIdle() {
        guard let button = statusItem.button else { return }
        button.image = idleIcon
        button.title = ""
    }

    private func showMbps(_ mbps: Int) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.title = "\(mbps)"
    }
}
