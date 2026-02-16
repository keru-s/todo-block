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
