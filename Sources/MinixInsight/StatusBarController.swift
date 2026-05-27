import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configurePopover()
        configureStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 560, height: 540)
        popover.contentViewController = NSHostingController(
            rootView: MenuView()
                .environmentObject(appState)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: appState.status.isConnected && appState.isLogging ? "keyboard.fill" : "keyboard",
            accessibilityDescription: "Minix Insight"
        )
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
