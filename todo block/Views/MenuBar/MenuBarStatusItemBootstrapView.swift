//
//  MenuBarStatusItemBootstrapView.swift
//  todo block
//
//  Created by Codex on 2026/2/22.
//

import AppKit
import SwiftData
import SwiftUI

struct MenuBarStatusItemBootstrapView: View {
    @Environment(\.openWindow) private var openWindow

    let modelContainer: ModelContainer

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .task {
                TodoHistoryPresentationCoordinator.shared.install {
                    openWindow(id: "mainWindow")
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuBarStatusItemController.shared.installIfNeeded(
                    modelContainer: modelContainer,
                    openMainWindow: {
                        openWindow(id: "mainWindow")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            }
    }
}
