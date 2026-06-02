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
    private let geoRow = GeoRowView()
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
        geoItem.view = geoRow
        menu.addItem(geoItem)
        menu.addItem(.separator())

        // The geo row carries a leading flag/spinner at the state-image gutter
        // (text at x=22). AppKit only reserves that gutter while some item shows
        // a state image, so with "Launch at login" off the native rows collapse
        // text to x=14 and the columns disagree. A transparent off-state image on
        // every plain row keeps the gutter reserved → all rows indent to x=22.
        // Width matches the rendered checkmark (13pt) so the reserved gutter, and
        // thus the native text column, lands at x=22 — the geo row's text column.
        let gutter = NSImage(size: NSSize(width: 13, height: 13))

        let run = NSMenuItem(title: "Run test", action: #selector(didTapRun), keyEquivalent: "")
        run.target = self
        run.offStateImage = gutter
        menu.addItem(run)

        launchItem.action = #selector(didTapLaunchAtLogin)
        launchItem.target = self
        launchItem.offStateImage = gutter
        menu.addItem(launchItem)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let about = NSMenuItem(title: "About Speedlet v\(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        about.offStateImage = gutter
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(didTapQuit), keyEquivalent: "q")
        quit.target = self
        quit.offStateImage = gutter
        menu.addItem(quit)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        geoRow.showLoading()
        // No cache: every open starts a fresh request. Live-update the row
        // when it returns (NSMenu reflects item changes while open).
        geoTask?.cancel()
        geoTask = Task { [weak self] in
            guard let self else { return }
            let info = await self.geoClient.fetch()
            if Task.isCancelled { return }
            if let info {
                self.geoRow.show(flag: flagEmoji(for: info.countryCode), text: detailLine(info))
            } else {
                self.geoRow.show(flag: nil, text: "Unavailable")
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        geoTask?.cancel()
        geoTask = nil
        geoRow.stopSpinner()
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

// Single view backing the geo row in both states, so the row never changes
// height: only the leading icon swaps in place (spinner ⇄ flag, sharing one
// center so one morphs into the other) and the text updates. Insets line the
// icon up with the state-image gutter and the text with the items below.
@MainActor
private final class GeoRowView: NSView {
    private let spinner = NSProgressIndicator()
    private let flag = NSTextField(labelWithString: "")
    private let label = NSTextField(labelWithString: "")
    private static let font = NSFont.menuFont(ofSize: 0)

    // Matched to the live native layout (measured via the menu view tree): a
    // checkmark sits at x=9 w=13 (centre 15.5) and titles indent to x=22 when a
    // state image is present; native rows are 24pt tall. The geo row carries an
    // icon (flag/spinner), so it mirrors that checkmarked layout exactly.
    private let iconCenterX: CGFloat = 15.5   // = native checkmark centre
    private let textLeading: CGFloat = 24     // → label frame x≈22 (2pt cell inset)
    private let rowHeight: CGFloat = 24

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        flag.font = Self.font
        flag.alignment = .center
        flag.translatesAutoresizingMaskIntoConstraints = false

        label.font = Self.font
        label.textColor = .disabledControlTextColor   // matches the disabled row look
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(spinner)
        addSubview(flag)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: rowHeight),
            spinner.centerXAnchor.constraint(equalTo: leadingAnchor, constant: iconCenterX),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),
            flag.centerXAnchor.constraint(equalTo: leadingAnchor, constant: iconCenterX),
            flag.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func showLoading() {
        flag.isHidden = true
        spinner.startAnimation(nil)   // isDisplayedWhenStopped=false reveals it only while spinning
        label.stringValue = "Checking…"
    }

    func show(flag emoji: String?, text line: String) {
        spinner.stopAnimation(nil)
        flag.stringValue = emoji ?? ""
        flag.isHidden = (emoji == nil)
        label.stringValue = line
    }

    func stopSpinner() { spinner.stopAnimation(nil) }
}
