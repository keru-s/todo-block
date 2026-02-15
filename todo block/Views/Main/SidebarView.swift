//
//  SidebarView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Query(sort: \DaySection.date, order: .reverse) private var allSections: [DaySection]

    @Binding var selectedDestination: SidebarDestination

    init(selectedDestination: Binding<SidebarDestination>) {
        self._selectedDestination = selectedDestination
    }

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
                LongTermRow(isSelected: selectedDestination == .longTerm)
                    .tag(SidebarDestination.longTerm)
                    .onDrop(
                        of: [.text],
                        delegate: SidebarLongTermDropDelegate(
                            store: TodoStore.shared,
                            selectedDestination: $selectedDestination
                        )
                    )
            }

            ForEach(groupedMonths, id: \.year) { yearGroup in
                Section {
                    ForEach(yearGroup.months, id: \.self) { month in
                        let destination = SidebarDestination.month(year: yearGroup.year, month: month)
                        MonthRow(
                            year: yearGroup.year,
                            month: month,
                            isSelected: selectedDestination == destination
                        )
                        .tag(destination)
                        .onDrop(
                            of: [.text],
                            delegate: SidebarMonthDropDelegate(
                                year: yearGroup.year,
                                month: month,
                                store: TodoStore.shared,
                                selectedDestination: $selectedDestination
                            )
                        )
                    }
                } header: {
                    Text("\(yearGroup.year) 年")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 150)
    }
}

struct LongTermRow: View {
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "infinity")
            if isSelected {
                Text("长期")
                    .bold()
            } else {
                Text("长期")
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

struct MonthRow: View {
    let year: Int
    let month: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            if isSelected {
                Text("\(month) 月")
                    .bold()
            } else {
                Text("\(month) 月")
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

struct SidebarLongTermDropDelegate: DropDelegate {
    let store: TodoStore
    let selectedDestination: Binding<SidebarDestination>

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard
                let idString = object as? String,
                let itemId = UUID(uuidString: idString)
            else {
                return
            }

            Task { @MainActor in
                guard let draggedItem = store.todoItemsCache[itemId] else { return }
                let newIndent = SidebarDropIndentResolver.resolveIndent(
                    draggedItem: draggedItem,
                    afterItem: nil
                )
                store.moveItemWithChildren(
                    draggedItem,
                    to: .longTerm(isUrgent: false),
                    afterItem: nil,
                    newIndentLevel: newIndent
                )
                selectedDestination.wrappedValue = .longTerm
            }
        }

        return true
    }
}

struct SidebarMonthDropDelegate: DropDelegate {
    let year: Int
    let month: Int
    let store: TodoStore
    let selectedDestination: Binding<SidebarDestination>

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard
                let idString = object as? String,
                let itemId = UUID(uuidString: idString)
            else {
                return
            }

            Task { @MainActor in
                guard let draggedItem = store.todoItemsCache[itemId] else { return }

                let target = store.tailItemForScheduledMonth(year: year, month: month)
                let newIndent = SidebarDropIndentResolver.resolveIndent(
                    draggedItem: draggedItem,
                    afterItem: nil
                )
                store.moveItemWithChildren(
                    draggedItem,
                    to: .scheduled(date: target.date),
                    afterItem: nil,
                    newIndentLevel: newIndent
                )
                selectedDestination.wrappedValue = .month(year: year, month: month)
            }
        }

        return true
    }
}

enum SidebarDropIndentResolver {
    static func resolveIndent(draggedItem: TodoItem, afterItem: TodoItem?) -> Int {
        if let afterItem {
            return min(draggedItem.indentLevel, afterItem.indentLevel + 1)
        }
        return 0
    }
}

#Preview {
    SidebarView(
        selectedDestination: .constant(
            .month(
                year: Calendar.current.component(.year, from: Date()),
                month: Calendar.current.component(.month, from: Date())
            )
        )
    )
    .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
