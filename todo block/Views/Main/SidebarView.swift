//
//  SidebarView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI

struct SidebarView: View {
    @Query(sort: \DaySection.date, order: .reverse) private var allSections: [DaySection]

    @Binding var selectedDestination: SidebarDestination

    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

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
                SidebarDropTargetRow(destination: .longTerm) {
                    LongTermRow(isSelected: selectedDestination == .longTerm)
                }
                .tag(SidebarDestination.longTerm)
            }

            ForEach(groupedMonths, id: \.year) { yearGroup in
                Section {
                    ForEach(yearGroup.months, id: \.self) { month in
                        let destination = SidebarDestination.month(year: yearGroup.year, month: month)
                        SidebarDropTargetRow(destination: destination) {
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

/// Wraps a sidebar row to register its frame as a drag-and-drop target
/// and show a highlight when the pointer hovers during a drag.
private struct SidebarDropTargetRow<Content: View>: View {
    let destination: SidebarDestination
    @ViewBuilder let content: Content

    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    private var isHighlighted: Bool {
        coordinator.hoveredSidebarDestination == destination
    }

    var body: some View {
        content
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear {
                            coordinator.registerSidebarTarget(destination, frame: frame)
                        }
                        .onChange(of: frame) { _, newValue in
                            coordinator.registerSidebarTarget(destination, frame: newValue)
                        }
                }
            }
            .listRowBackground(
                isHighlighted
                    ? Color.accentColor.opacity(0.2)
                    : nil
            )
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
