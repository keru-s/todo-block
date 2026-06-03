//
//  SidebarView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import AppKit
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Query(sort: \DaySection.date, order: .reverse) private var allSections: [DaySection]

    @Binding var selectedDestination: SidebarDestination
    @State private var dragSession = TodoEditorDragSession.shared

    private var groupedMonths: [(year: Int, months: [Int])] {
        var yearMonths: [Int: Set<Int>] = [:]

        for section in allSections {
            yearMonths[section.year, default: []].insert(section.month)
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        let currentMonth = Calendar.current.component(.month, from: Date())
        yearMonths[currentYear, default: []].insert(currentMonth)

        return yearMonths.keys.sorted(by: >).map { year in
            (year: year, months: yearMonths[year, default: []].sorted(by: >))
        }
    }

    init(selectedDestination: Binding<SidebarDestination>) {
        self._selectedDestination = selectedDestination
    }

    var body: some View {
        List(selection: Binding<SidebarDestination?>(
            get: { selectedDestination },
            set: { newValue in
                if let newValue {
                    selectedDestination = newValue
                }
            }
        )) {
            Section {
                SidebarDropTargetRow(destination: .longTerm, dragSession: dragSession) {
                    LongTermRow(isSelected: selectedDestination == .longTerm)
                }
                .tag(SidebarDestination.longTerm)
            }

            ForEach(groupedMonths, id: \.year) { yearGroup in
                Section {
                    ForEach(yearGroup.months, id: \.self) { month in
                        let destination = SidebarDestination.month(year: yearGroup.year, month: month)
                        SidebarDropTargetRow(destination: destination, dragSession: dragSession) {
                            MonthRow(
                                year: yearGroup.year,
                                month: month,
                                isSelected: selectedDestination == destination
                            )
                        }
                        .tag(destination)
                    }
                } header: {
                    Text(verbatim: "\(yearGroup.year) 年")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 150)
    }
}

private struct SidebarDropTargetRow<Content: View>: View {
    let destination: SidebarDestination
    @Bindable var dragSession: TodoEditorDragSession
    @ViewBuilder let content: Content

    private var isHighlighted: Bool {
        dragSession.hoveredSidebarDestination == destination
    }

    var body: some View {
        content
            .background {
                SidebarDropFrameReader(destination: destination, dragSession: dragSession)
            }
            .listRowBackground(
                isHighlighted
                    ? TodoDesignTokens.selectionTint
                    : nil
            )
    }
}

private struct SidebarDropFrameReader: NSViewRepresentable {
    let destination: SidebarDestination
    let dragSession: TodoEditorDragSession

    func makeNSView(context: Context) -> SidebarDropFrameView {
        let view = SidebarDropFrameView()
        view.destination = destination
        view.dragSession = dragSession
        return view
    }

    func updateNSView(_ nsView: SidebarDropFrameView, context: Context) {
        nsView.destination = destination
        nsView.dragSession = dragSession
        nsView.updateFrame()
    }
}

@MainActor
private final class SidebarDropFrameView: NSView {
    var destination: SidebarDestination?
    var dragSession: TodoEditorDragSession?
    private var registeredDestination: SidebarDestination?
    private weak var registeredDragSession: TodoEditorDragSession?
    private weak var observedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowObservers()
        updateFrame()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            unregisterCurrentTarget()
            removeWindowObservers()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateFrame()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        updateFrame()
    }

    func updateFrame() {
        guard let destination, let dragSession, let window else {
            unregisterCurrentTarget()
            return
        }

        if registeredDestination != destination || registeredDragSession !== dragSession {
            unregisterCurrentTarget()
        }

        let frameInWindow = convert(bounds, to: nil)
        let originInScreen = window.convertPoint(toScreen: frameInWindow.origin)
        let frameInScreen = CGRect(origin: originInScreen, size: frameInWindow.size)
        dragSession.registerSidebarTarget(destination, frame: frameInScreen)
        registeredDestination = destination
        registeredDragSession = dragSession
    }

    @objc private func windowGeometryChanged(_ notification: Notification) {
        updateFrame()
    }

    private func updateWindowObservers() {
        guard observedWindow !== window else { return }
        removeWindowObservers()
        guard let window else { return }
        observedWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowGeometryChanged(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowGeometryChanged(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    private func removeWindowObservers() {
        guard let observedWindow else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didMoveNotification,
            object: observedWindow
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didResizeNotification,
            object: observedWindow
        )
        self.observedWindow = nil
    }

    private func unregisterCurrentTarget() {
        guard let registeredDestination else { return }
        registeredDragSession?.unregisterSidebarTarget(registeredDestination)
        self.registeredDestination = nil
        registeredDragSession = nil
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()
    return SidebarView(
        selectedDestination: .constant(
            .month(
                year: Calendar.current.component(.year, from: Date()),
                month: Calendar.current.component(.month, from: Date())
            )
        )
    )
    .modelContainer(container)
}
