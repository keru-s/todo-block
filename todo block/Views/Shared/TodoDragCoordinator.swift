//
//  TodoDragCoordinator.swift
//  todo block
//
//  Created by Codex on 2026/3/6.
//

import CoreGraphics
import Foundation
import Observation

/// Central coordinator for all drag-and-drop state.
/// Uses manual `DragGesture` instead of the system `.onDrag`/`.onDrop` path,
/// avoiding unreliable AppKit ↔ SwiftUI bridging when `NSViewRepresentable`
/// views (e.g. `CustomNSTextView`) are in the hierarchy.
@MainActor
@Observable
final class TodoDragCoordinator {
    static let shared = TodoDragCoordinator()

    /// The item currently being dragged.
    private(set) var draggedItemId: UUID?

    /// Current drag location in the `.global` SwiftUI coordinate space.
    private(set) var globalDragLocation: CGPoint?

    private init() {}

    var isDragging: Bool { draggedItemId != nil }

    func beginDrag(itemId: UUID) {
        draggedItemId = itemId
    }

    func updateDrag(globalLocation: CGPoint) {
        globalDragLocation = globalLocation
    }

    /// Ends the drag and returns the final item + location, or `nil` if no
    /// drag was active.
    @discardableResult
    func endDrag() -> (itemId: UUID, globalLocation: CGPoint)? {
        defer {
            draggedItemId = nil
            globalDragLocation = nil
            resetAllDropZoneStates()
        }
        guard let id = draggedItemId, let loc = globalDragLocation else { return nil }
        return (id, loc)
    }

    func cancelDrag() {
        draggedItemId = nil
        globalDragLocation = nil
        resetAllDropZoneStates()
    }

    // MARK: - Drop zone registration (list-level targets)

    struct DropZoneInfo {
        let destination: TodoDropDestination
        var frame: CGRect
        /// The drop state last computed by this zone while the pointer was over it.
        var currentDropState: TodoListDropState = .none
    }

    private var dropZones: [String: DropZoneInfo] = [:]

    /// The zone whose view-local `contains` check passed most recently.
    /// Set by each list from its own `updateDropStateFromCoordinator`,
    /// which avoids the stale-frame problem of `dropZone(at:)`.
    private(set) var activeDropZoneId: String?

    func registerDropZone(id: String, destination: TodoDropDestination, frame: CGRect) {
        dropZones[id] = DropZoneInfo(destination: destination, frame: frame)
    }

    func updateDropZoneFrame(id: String, frame: CGRect) {
        dropZones[id]?.frame = frame
    }

    func updateDropZoneState(id: String, state: TodoListDropState) {
        dropZones[id]?.currentDropState = state
    }

    func setActiveDropZone(_ id: String?) {
        activeDropZoneId = id
    }

    func dropZoneInfo(for id: String) -> DropZoneInfo? {
        dropZones[id]
    }

    func unregisterDropZone(id: String) {
        dropZones.removeValue(forKey: id)
        if activeDropZoneId == id { activeDropZoneId = nil }
    }

    private func resetAllDropZoneStates() {
        for key in dropZones.keys {
            dropZones[key]?.currentDropState = .none
        }
        activeDropZoneId = nil
    }

    // MARK: - Sidebar drop target registration

    private var sidebarTargets: [(destination: SidebarDestination, frame: CGRect)] = []

    func registerSidebarTarget(_ destination: SidebarDestination, frame: CGRect) {
        if let index = sidebarTargets.firstIndex(where: { $0.destination == destination }) {
            sidebarTargets[index] = (destination, frame)
        } else {
            sidebarTargets.append((destination, frame))
        }
    }

    func removeAllSidebarTargets() {
        sidebarTargets.removeAll()
    }

    /// Returns the sidebar destination at the given global point, if any.
    func sidebarTarget(at globalPoint: CGPoint) -> SidebarDestination? {
        sidebarTargets.first(where: { $0.frame.contains(globalPoint) })?.destination
    }

    /// The sidebar destination currently under the drag pointer, if any.
    var hoveredSidebarDestination: SidebarDestination? {
        guard let loc = globalDragLocation, isDragging else { return nil }
        return sidebarTarget(at: loc)
    }
}
