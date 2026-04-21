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
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(didClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // Monospaced digits so the title doesn't shimmy as values change.
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
        }
    }

    func shutdown() {
        runner.stopAndWait()
    }

    @objc private func didClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleRunner()
        }
    }

    private func toggleRunner() {
        if runner.isRunning { runner.stop() } else { runner.start() }
    }

    private func showContextMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let run = NSMenuItem(title: "Run test", action: #selector(didTapRun), keyEquivalent: "")
        run.target = self
        menu.addItem(run)

        let launch = NSMenuItem(title: "Launch at login", action: #selector(didTapLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launch)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let about = NSMenuItem(title: "About NetMeter v\(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(didTapQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func didTapRun() {
        toggleRunner()
    }

    @objc private func didTapLaunchAtLogin() {
        LaunchAtLogin.toggle()
    }

    @objc private func didTapQuit() {
        NSApp.terminate(nil)
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
