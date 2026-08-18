//
//  TodoEditorDragSession.swift
//  todo block
//

import CoreGraphics
import Foundation

@MainActor
@Observable
final class TodoEditorDragSession {
    static let shared = TodoEditorDragSession()

    typealias ObserverID = UUID

    private struct Observer {
        let onSidebarTargetInvalidated: (SidebarDestination) -> Void
        let onExternalAction: () -> Void
    }

    private(set) var draggedItemId: UUID?
    private(set) var hoveredSidebarDestination: SidebarDestination?
    @ObservationIgnored
    private var sidebarFrames: [SidebarDestination: CGRect] = [:]
    @ObservationIgnored
    private var observers: [ObserverID: Observer] = [:]

    private init() {}

    var isDragging: Bool {
        draggedItemId != nil
    }

    /// 外部按钮、菜单或快捷键即将执行动作时，通知当前编辑器先收尾连续过程。
    /// 这个回调不改变拖动数据本身，具体的结束/取消规则仍由编辑器控制器负责。
    func notifyExternalAction() {
        for observer in observers.values {
            observer.onExternalAction()
        }
    }

    @discardableResult
    func addObserver(
        onSidebarTargetInvalidated: @escaping (SidebarDestination) -> Void,
        onExternalAction: @escaping () -> Void
    ) -> ObserverID {
        let id = ObserverID()
        observers[id] = Observer(
            onSidebarTargetInvalidated: onSidebarTargetInvalidated,
            onExternalAction: onExternalAction
        )
        return id
    }

    func removeObserver(_ id: ObserverID) {
        observers[id] = nil
    }

    private func notifySidebarTargetInvalidated(_ destination: SidebarDestination) {
        for observer in observers.values {
            observer.onSidebarTargetInvalidated(destination)
        }
    }

    func begin(itemId: UUID, screenLocation: CGPoint) {
        draggedItemId = itemId
        update(screenLocation: screenLocation)
    }

    func update(screenLocation: CGPoint) {
        hoveredSidebarDestination = sidebarFrames.first { _, frame in
            frame.contains(screenLocation)
        }?.key
    }

    func end() {
        draggedItemId = nil
        hoveredSidebarDestination = nil
    }

    func registerSidebarTarget(_ destination: SidebarDestination, frame: CGRect) {
        guard sidebarFrames[destination] != frame else { return }
        sidebarFrames[destination] = frame
    }

    func unregisterSidebarTarget(_ destination: SidebarDestination) {
        sidebarFrames[destination] = nil
        if hoveredSidebarDestination == destination {
            hoveredSidebarDestination = nil
            notifySidebarTargetInvalidated(destination)
        }
    }

    func isSidebarTargetRegistered(_ destination: SidebarDestination) -> Bool {
        sidebarFrames[destination] != nil
    }

    func clearSidebarTargets() {
        let invalidatedDestination = hoveredSidebarDestination
        sidebarFrames.removeAll()
        hoveredSidebarDestination = nil
        if let invalidatedDestination {
            notifySidebarTargetInvalidated(invalidatedDestination)
        }
    }
}
