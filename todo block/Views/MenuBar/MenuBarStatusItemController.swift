//
//  MenuBarStatusItemController.swift
//  todo block
//
//  Created by Codex on 2026/2/22.
//

import AppKit
import SwiftData
import SwiftUI

@MainActor
final class MenuBarStatusItemController: NSObject {
    static let shared = MenuBarStatusItemController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let contextMenu = NSMenu()

    private var modelContainer: ModelContainer?
    private var openMainWindow: (() -> Void)?
    private var isInstalled = false

    private override init() {
        super.init()
        configurePopover()
        configureContextMenu()
        observePopoverLifecycle()
    }

    /// Installs the status bar item and creates the popover's hosting controller
    /// exactly once. Subsequent calls are no-ops — we deliberately keep the same
    /// NSHostingController so MenuBarView's SwiftUI state survives across popover
    /// show/close cycles, and so we never swap contentViewController while the
    /// popover is being shown (which has been observed to dismiss the popover
    /// unexpectedly on macOS).
    func installIfNeeded(
        modelContainer: ModelContainer,
        openMainWindow: @escaping () -> Void
    ) {
        if isInstalled { return }

        self.modelContainer = modelContainer
        self.openMainWindow = openMainWindow

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "待办")
        button.image?.isTemplate = true
        button.toolTip = "待办"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusItem = item
        installPopoverContent(modelContainer: modelContainer)
        isInstalled = true
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
    }

    /// We observe `NSPopover.willShowNotification` / `didCloseNotification`
    /// instead of becoming `popover.delegate = self`. In testing,
    /// setting the popover delegate caused UI test runners to hang on
    /// `app.terminate()` (XCTest's graceful terminate failed to complete,
    /// timing out at 60s). Notification-based observation is delegate-free
    /// and avoids that interaction.
    private func observePopoverLifecycle() {
        NotificationCenter.default.addObserver(
            forName: NSPopover.willShowNotification,
            object: popover,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .menuBarPopoverWillShow, object: nil)
        }
        NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .menuBarPopoverDidClose, object: nil)
        }
    }

    private func configureContextMenu() {
        let openItem = NSMenuItem(
            title: "打开应用",
            action: #selector(openMainWindowFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self

        contextMenu.removeAllItems()
        contextMenu.addItem(openItem)
        contextMenu.addItem(.separator())
        contextMenu.addItem(quitItem)
    }

    private func installPopoverContent(modelContainer: ModelContainer) {
        let rootView = MenuBarView(onOpenMainWindow: { [weak self] in
            self?.performOpenMainWindow()
        })
        .modelContainer(modelContainer)

        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(from: sender)
            return
        }

        let isControlLeftClick = event.type == .leftMouseUp && event.modifierFlags.contains(.control)
        if event.type == .rightMouseUp || isControlLeftClick {
            showContextMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        }

        statusItem?.menu = contextMenu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func performOpenMainWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        openMainWindow?()
    }

    @objc
    private func openMainWindowFromMenu() {
        performOpenMainWindow()
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}
