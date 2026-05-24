//
//  DaySectionView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI

struct DaySectionView: View {
    @Bindable var section: DaySection
    @Bindable var selectionManager: SelectionManager
    var onItemCreated: ((UUID) -> Void)?
    var onInteraction: (() -> Void)?

    @State private var dropState: TodoListDropState = .none
    @State private var showDatePicker: Bool = false
    @State private var selectedDate: Date = Date()

    private var store: TodoStore { TodoStore.shared }
    private var coordinator: TodoDragCoordinator { TodoDragCoordinator.shared }

    private var todoItems: [TodoItem] {
        store.items(for: section.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DaySectionHeaderView(
                title: section.title,
                showDatePicker: $showDatePicker,
                selectedDate: $selectedDate,
                onTitleTap: onDateTitleTapped,
                onConfirm: confirmDateSelection
            )

            TodoDroppableList(
                items: todoItems,
                destination: .scheduled(date: section.date),
                dropCoordinateSpaceName:
                    "day-section-drop-\(section.date.timeIntervalSince1970)",
                selectionManager: selectionManager,
                dropState: $dropState,
                store: store,
                onInteraction: onInteraction,
                onCreateItemAfter: createNewItemAfter,
                emptyContent: {
                    DaySectionEmptyStateView(onAddItem: addNewItem)
                }
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: TodoDesignTokens.bucketCornerRadius)
                .fill(TodoDesignTokens.bucketTint)
        )
        .onAppear {
            selectedDate = section.date
        }
        .onChange(of: todoItems.dropResetSnapshot) { _, _ in
            if coordinator.isDragging == false {
                dropState = .none
            }
        }
        .onChange(of: store.dropIndicatorResetTrigger) { _, _ in
            dropState = .none
        }
    }

    private func onDateTitleTapped() {
        selectedDate = section.date
        showDatePicker = true
    }

    private func confirmDateSelection(_ newDate: Date) {
        store.updateSectionDate(section, to: newDate)
        showDatePicker = false
    }

    private func addNewItem() {
        let newItem = store.createItem(dayDate: section.date)
        selectionManager.handleSelect(
            item: newItem,
            allItems: store.items(for: section.date),
            shiftPressed: false
        )
        onItemCreated?(newItem.id)
    }

    private func createNewItemAfter(_ item: TodoItem) {
        let newItem = store.createItem(
            dayDate: section.date,
            afterItem: item,
            indentLevel: item.indentLevel
        )
        selectionManager.handleSelect(
            item: newItem,
            allItems: store.items(for: section.date),
            shiftPressed: false
        )
        onItemCreated?(newItem.id)
    }
}

private struct DaySectionHeaderView: View {
    let title: String
    @Binding var showDatePicker: Bool
    @Binding var selectedDate: Date
    let onTitleTap: () -> Void
    let onConfirm: (Date) -> Void

    var body: some View {
        HStack {
            Button(title) {
                onTitleTap()
            }
            .buttonStyle(.plain)
            .font(.title3)
            .bold()
            .foregroundStyle(.primary)
            .popover(isPresented: $showDatePicker) {
                VStack(spacing: 12) {
                    DatePicker(
                        "选择日期",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    HStack {
                        Button("取消") {
                            showDatePicker = false
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button("确认") {
                            onConfirm(selectedDate)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .frame(width: 300)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }
}


private struct DaySectionEmptyStateView: View {
    let onAddItem: () -> Void

    var body: some View {
        Button(action: onAddItem) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                Text("添加待办")
            }
            .font(.system(size: 14))
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }
}

#Preview {
    let container = TodoPreviewSupport.bootstrap()

    let section = DaySection(date: Date(), title: "01-17")
    container.mainContext.insert(section)

    return DaySectionView(
        section: section,
        selectionManager: SelectionManager()
    )
    .modelContainer(container)
    .padding()
}
