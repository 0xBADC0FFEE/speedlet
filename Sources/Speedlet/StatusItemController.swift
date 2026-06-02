import AppKit
import Symbols
import SpeedletCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let idleIcon: NSImage?
    private let startingIcon: NSImage?
    private var spinner: NSImageView?
    private var runner: SpeedTestRunner!

    private let menu = NSMenu()
    private let geoItem = NSMenuItem()
    private let launchItem = NSMenuItem(title: "Launch at login", action: nil, keyEquivalent: "")
    private let geoClient = GeoClient()
    private var geoTask: Task<Void, Never>?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        idleIcon = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Speedlet")
        idleIcon?.isTemplate = true
        startingIcon = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Speedlet — starting")
        startingIcon?.isTemplate = true
        super.init()
        runner = SpeedTestRunner(onState: { [weak self] state in self?.apply(state) })
        buildMenu()
        apply(.idle)
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
        // The menu carries an NSMenuDelegate; menuWillOpen drives the geo fetch.
        // Attach for this click only so left-click keeps toggling the runner.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() {
        menu.delegate = self

        geoItem.isEnabled = false
        menu.addItem(geoItem)
        menu.addItem(.separator())

        let run = NSMenuItem(title: "Run test", action: #selector(didTapRun), keyEquivalent: "")
        run.target = self
        menu.addItem(run)

        launchItem.action = #selector(didTapLaunchAtLogin)
        launchItem.target = self
        menu.addItem(launchItem)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let about = NSMenuItem(title: "About Speedlet v\(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(didTapQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        setGeoRow(flag: nil, text: "…")
        // No cache: every open starts a fresh request. Live-update the row
        // when it returns (NSMenu reflects item changes while open).
        geoTask?.cancel()
        geoTask = Task { [weak self] in
            guard let self else { return }
            let info = await self.geoClient.fetch()
            if Task.isCancelled { return }
            if let info {
                self.setGeoRow(flag: flagEmoji(for: info.countryCode), text: "\(info.countryName) · \(info.ipAddress)")
            } else {
                self.setGeoRow(flag: nil, text: "Unavailable")
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        geoTask?.cancel()
        geoTask = nil
    }

    // Flag rides the state-image gutter (where the checkmark sits) so the text
    // column lines up with the other items. The slot is always a fixed flag-
    // sized image (transparent while loading) so the gutter doesn't widen when
    // the flag arrives mid-open.
    private func setGeoRow(flag: String?, text: String) {
        geoItem.title = text
        geoItem.onStateImage = Self.flagSlot(flag)
        geoItem.state = .on
    }

    private static let menuFont = NSFont.menuFont(ofSize: 0)

    // Width of a regional-indicator pair — the gutter is pinned to this.
    private static let flagSlotSize: NSSize = {
        let s = ("🇳🇱" as NSString).size(withAttributes: [.font: menuFont])
        return NSSize(width: ceil(s.width), height: ceil(s.height))
    }()

    private static func flagSlot(_ flag: String?) -> NSImage {
        let image = NSImage(size: flagSlotSize)
        image.lockFocus()
        (flag ?? "").draw(at: .zero, withAttributes: [.font: menuFont])
        image.unlockFocus()
        return image
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

    private func apply(_ state: SpeedTestState) {
        switch state {
        case .idle:    showIdle()
        case .starting: showStarting()
        case .running(let mbps): showMbps(mbps)
        }
    }

    private func showIdle() {
        render(image: idleIcon, title: "", spinning: false)
    }

    private func showStarting() {
        // button.image stays set to a real SF Symbol so NSStatusBarButton sizes
        // identically to idle; contentTintColor=.clear hides it under the overlay.
        render(image: startingIcon, title: "", spinning: true)
    }

    private func showMbps(_ mbps: Int) {
        render(image: nil, title: "\(mbps)", spinning: false)
    }

    private func render(image: NSImage?, title: String, spinning: Bool) {
        guard let button = statusItem.button else { return }
        removeSpinner()
        button.contentTintColor = spinning ? .clear : nil
        button.image = image
        button.title = title
        if spinning, let icon = image { installSpinner(in: button, icon: icon) }
    }

    private func installSpinner(in button: NSStatusBarButton, icon: NSImage) {
        button.layoutSubtreeIfNeeded()
        // NSButtonCell positions button.image so the image's alignmentRect midpoint
        // sits at the cell's imageRect midpoint; mirror that for the overlay.
        let cellRect = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds) ?? button.bounds
        let ar = icon.alignmentRect
        let iv = NSImageView(frame: NSRect(
            x: cellRect.midX - ar.midX,
            y: cellRect.midY - ar.midY,
            width: icon.size.width,
            height: icon.size.height
        ))
        iv.image = icon
        iv.imageScaling = .scaleNone
        iv.imageAlignment = .alignBottomLeft
        button.addSubview(iv)
        iv.addSymbolEffect(.rotate, options: .repeat(.continuous))
        spinner = iv
    }

    private func removeSpinner() {
        spinner?.removeFromSuperview()
        spinner = nil
    }
}
