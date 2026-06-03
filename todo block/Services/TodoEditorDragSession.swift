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

    private(set) var draggedItemId: UUID?
    private(set) var hoveredSidebarDestination: SidebarDestination?
    @ObservationIgnored
    private var sidebarFrames: [SidebarDestination: CGRect] = [:]

    private init() {}

    var isDragging: Bool {
        draggedItemId != nil
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
}
