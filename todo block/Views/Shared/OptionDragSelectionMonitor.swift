//
//  OptionDragSelectionMonitor.swift
//  todo block
//

import AppKit
import SwiftUI

/// 用 `NSEvent.addLocalMonitorForEvents` 接管 `⌥ Option` + 左键拖动事件,
/// 实现跨多个 todo item 的框选。
///
/// 不按住 Option 时事件完全透传,NSTextView 的文本选择行为不受影响;
/// 按住 Option 起手时事件被吞掉,改走 SelectionManager 的 begin/update/endDragSelection。
@MainActor
final class OptionDragSelectionMonitor {
    static let shared = OptionDragSelectionMonitor()

    struct Registration {
        let id: String
        let frameTracker: DropFrameTracker
        let itemsProvider: () -> [TodoItem]
        let selectionManager: SelectionManager
        let onInteraction: (() -> Void)?
    }

    private var registrations: [String: Registration] = [:]
    private var localMonitor: Any?
    private var activeId: String?

    private init() {}

    func register(_ registration: Registration) {
        registrations[registration.id] = registration
        installMonitorIfNeeded()
    }

    func unregister(id: String) {
        registrations.removeValue(forKey: id)
        if activeId == id {
            activeId = nil
        }
        if registrations.isEmpty {
            removeMonitor()
        }
    }

    // MARK: - Monitor lifecycle

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { event in
            MainActor.assumeIsolated {
                Self.shared.handle(event: event)
            }
        }
    }

    private func removeMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        activeId = nil
    }

    // MARK: - Event dispatch

    private func handle(event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            return handleMouseDown(event)
        case .leftMouseDragged:
            return handleMouseDragged(event)
        case .leftMouseUp:
            return handleMouseUp(event)
        default:
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.option) else { return event }
        guard let window = event.window, let point = swiftUIPoint(from: event, in: window) else {
            return event
        }

        for (id, registration) in registrations {
            let listFrame = registration.frameTracker.listGlobalFrame
            guard listFrame.width > 0, listFrame.contains(point) else { continue }

            let items = registration.itemsProvider()
            guard items.isEmpty == false else { continue }

            let localPoint = CGPoint(
                x: point.x - listFrame.origin.x,
                y: point.y - listFrame.origin.y
            )
            guard
                let hitId = TodoDragSelectionHitTester.nearestItemId(
                    at: localPoint,
                    items: items,
                    itemFrames: registration.frameTracker.itemFrames
                ),
                let target = items.first(where: { $0.id == hitId })
            else { continue }

            registration.onInteraction?()
            registration.selectionManager.beginDragSelection(item: target, allItems: items)
            activeId = id
            return nil
        }

        return event
    }

    private func handleMouseDragged(_ event: NSEvent) -> NSEvent? {
        guard let activeId, let registration = registrations[activeId] else { return event }
        guard registration.selectionManager.isDragSelecting else { return event }
        guard let window = event.window, let point = swiftUIPoint(from: event, in: window) else {
            return nil
        }

        let listFrame = registration.frameTracker.listGlobalFrame
        let localPoint = CGPoint(
            x: point.x - listFrame.origin.x,
            y: point.y - listFrame.origin.y
        )
        let items = registration.itemsProvider()
        if
            let hitId = TodoDragSelectionHitTester.nearestItemId(
                at: localPoint,
                items: items,
                itemFrames: registration.frameTracker.itemFrames
            ),
            let target = items.first(where: { $0.id == hitId })
        {
            registration.selectionManager.updateDragSelection(to: target, allItems: items)
        }
        return nil
    }

    private func handleMouseUp(_ event: NSEvent) -> NSEvent? {
        guard let activeId, let registration = registrations[activeId] else { return event }
        self.activeId = nil
        guard registration.selectionManager.isDragSelecting else { return event }
        registration.selectionManager.endDragSelection()
        return nil
    }

    // MARK: - Coordinate conversion

    /// 把 AppKit `event.locationInWindow` (左下原点) 转成 SwiftUI `.global` 坐标 (左上原点)。
    /// 等同于 NSHostingView 内部 `proxy.frame(in: .global)` 所用的坐标系。
    private func swiftUIPoint(from event: NSEvent, in window: NSWindow) -> CGPoint? {
        guard let contentView = window.contentView else { return nil }
        let pointInWindow = event.locationInWindow
        return CGPoint(x: pointInWindow.x, y: contentView.bounds.height - pointInWindow.y)
    }
}
