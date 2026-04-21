import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let icon = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "NetMeter")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.target = self
        statusItem.button?.action = #selector(didClick)
    }

    @objc private func didClick() {
        NSLog("NetMeter: status item clicked")
    }
}
