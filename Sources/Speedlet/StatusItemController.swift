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
    private let autoRunItem = NSMenuItem(title: "Auto-run on network change", action: nil, keyEquivalent: "")
    private let geoClient = GeoClient()
    private var geoTask: Task<Void, Never>?
    private var monitor: NetworkChangeMonitor!

    // Status-bar geo flag, fetched per run independently of the menu's geoTask.
    // statusFlag/currentMbps are the two data inputs renderStatus() composes.
    private var statusGeoTask: Task<Void, Never>?
    private var statusFlag: String?
    private var currentMbps: Int?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        idleIcon = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Speedlet")
        idleIcon?.isTemplate = true
        startingIcon = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Speedlet — starting")
        startingIcon?.isTemplate = true
        super.init()
        runner = SpeedTestRunner(onState: { [weak self] state in self?.apply(state) })
        // Auto-run reuses the manual runner via restart(), so the two paths
        // cannot drift; the per-run geo lookup already refreshes the flag.
        monitor = NetworkChangeMonitor(onChange: { [weak self] in self?.runner.restart() })
        buildMenu()
        apply(.idle)
        // Watch from launch only if the user opted in; a fresh launch on an
        // existing connection seeds the baseline and stays quiet.
        if AutoRunPreference.isEnabled { monitor.start() }
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(didClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // Monospaced digits so the title doesn't shimmy as values change.
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
            // Right-align the title so the trailing flag pins to the button's
            // right edge; without this the title centres and the flag drifts as
            // the digit count changes.
            button.alignment = .right
        }
    }

    func shutdown() {
        monitor.stop()
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

        autoRunItem.action = #selector(didTapAutoRun)
        autoRunItem.target = self
        autoRunItem.offStateImage = gutter
        menu.addItem(autoRunItem)

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
        autoRunItem.state = AutoRunPreference.isEnabled ? .on : .off
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

    @objc private func didTapAutoRun() {
        let enabled = !AutoRunPreference.isEnabled
        AutoRunPreference.set(enabled)
        // Turning off never disturbs a run already in flight — only future
        // automatic runs stop.
        if enabled { monitor.start() } else { monitor.stop() }
    }

    @objc private func didTapQuit() {
        NSApp.terminate(nil)
    }

    private func apply(_ state: SpeedTestState) {
        switch state {
        case .idle:
            // A late geo response must not paint a flag onto the idle icon.
            statusGeoTask?.cancel()
            statusGeoTask = nil
            statusFlag = nil
            currentMbps = nil
            showIdle()
        case .starting:
            currentMbps = nil
            startStatusGeo()   // fresh lookup per run, in parallel with the runner
            renderStatus()
        case .running(let mbps):
            currentMbps = mbps
            renderStatus()
        }
    }

    private func showIdle() {
        render(image: idleIcon, title: "", spinning: false)
    }

    // Compose the status item from the two data inputs. The flag, when present,
    // is the trailing glyph: since the status bar pins the button's right edge
    // and the button hugs its content, the flag sits a constant distance from the
    // trailing edge — it stays put as digits grow to its left. With no datum yet,
    // the spinner stands in at that same center; the first datum (flag or mbps)
    // retires it for the run.
    private func renderStatus() {
        let digits = currentMbps.map(String.init) ?? ""
        let flag = statusFlag ?? ""
        if digits.isEmpty && flag.isEmpty {
            // button.image stays a real SF Symbol so NSStatusBarButton sizes
            // identically to idle; contentTintColor=.clear hides it under the overlay.
            render(image: startingIcon, title: "", spinning: true)
        } else {
            let title = [digits, flag].filter { !$0.isEmpty }.joined(separator: " ")
            render(image: nil, title: title, spinning: false)
        }
    }

    // Dedicated per-run geo lookup, separate from the menu's menuWillOpen fetch.
    // Cancelled on return to .idle, so a late response is dropped (Task.isCancelled).
    private func startStatusGeo() {
        statusGeoTask?.cancel()
        statusGeoTask = Task { [weak self] in
            guard let self else { return }
            let info = await self.geoClient.fetch()
            if Task.isCancelled { return }
            guard let flag = statusBarFlag(for: info?.countryCode) else { return }
            self.statusFlag = flag
            self.renderStatus()
        }
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
