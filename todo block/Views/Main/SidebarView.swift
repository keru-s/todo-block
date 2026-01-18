//
//  SidebarView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DaySection.date, order: .reverse) private var allSections: [DaySection]
    
    @Binding var selectedYear: Int
    @Binding var selectedMonth: Int
    
    private var groupedMonths: [(year: Int, months: [Int])] {
        var yearMonths: [Int: Set<Int>] = [:]
        
        for section in allSections {
            let year = section.year
            let month = section.month
            yearMonths[year, default: []].insert(month)
        }
        
        // 添加当前年月（确保总有可选项）
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentMonth = Calendar.current.component(.month, from: Date())
        yearMonths[currentYear, default: []].insert(currentMonth)
        
        return yearMonths.keys.sorted(by: >).map { year in
            (year: year, months: yearMonths[year]!.sorted(by: >))
        }
    }
    
    var body: some View {
        List(selection: Binding(
            get: { "\(selectedYear)-\(selectedMonth)" },
            set: { newValue in
                if let value = newValue {
                    let parts = value.split(separator: "-")
                    if parts.count == 2,
                       let year = Int(parts[0]),
                       let month = Int(parts[1]) {
                        selectedYear = year
                        selectedMonth = month
                    }
                }
            }
        )) {
            ForEach(groupedMonths, id: \.year) { yearGroup in
                Section {
                    ForEach(yearGroup.months, id: \.self) { month in
                        MonthRow(year: yearGroup.year, month: month, isSelected: selectedYear == yearGroup.year && selectedMonth == month)
                            .tag("\(yearGroup.year)-\(month)")
                    }
                } header: {
                    Text("\(String(yearGroup.year)) 年")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 150)
    }
}

struct MonthRow: View {
    let year: Int
    let month: Int
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Text("\(month) 月")
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    SidebarView(
        selectedYear: .constant(2026),
        selectedMonth: .constant(1)
    )
    .modelContainer(for: [TodoItem.self, DaySection.self], inMemory: true)
}
