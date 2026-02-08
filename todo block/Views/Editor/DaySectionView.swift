//
//  DaySectionView.swift
//  todo block
//
//  Created by Claude on 2026/1/17.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 拖拽状态（通用）

enum TodoListDropState: Equatable {
    case none
    case insertAt(index: Int, indentLevel: Int)
}

struct DaySectionView: View {
    @Bindable var section: DaySection
    @Bindable var selectionManager: SelectionManager
    var onItemCreated: ((UUID) -> Void)?

    @State private var isEditingTitle: Bool = false
    @State private var editingTitle: String = ""
    @State private var dropState: TodoListDropState = .none
    @State private var showDatePicker: Bool = false
    @State private var selectedDate: Date = Date()
    @FocusState private var isTitleFocused: Bool

    private var store: TodoStore { TodoStore.shared }

    private var todoItems: [TodoItem] {
        store.items(for: section.date)
    }

    private let indentWidth: CGFloat = 24
    private let itemHeight: CGFloat = 28  // 每个 item 的高度（含 padding）

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 日期标题
            titleView

            // 待办事项列表（带拖拽支持）
            todoListView
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
        )
        .onAppear {
            selectedDate = section.date
        }
    }

    // MARK: - 待办列表视图

    private var todoListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if todoItems.isEmpty {
                // 空列表时显示添加按钮
                Button(action: addNewItem) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("添加待办")
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
            } else {
                ForEach(Array(todoItems.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 0) {
                        // 插入线（在当前项上方）
                        if case .insertAt(let insertIndex, let indentLevel) = dropState,
                            insertIndex == index
                        {
                            insertionIndicator(indentLevel: indentLevel)
                        }

                        TodoItemView(
                            item: item,
                            allItems: todoItems,
                            focusedItemId: $selectionManager.focusedItemId,
                            isSelected: selectionManager.selectedItemIds.contains(item.id),
                            hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                            cursorPosition: selectionManager.cursorPosition,
                            onSelect: { shiftPressed in
                                selectionManager.handleSelect(
                                    item: item, allItems: todoItems, shiftPressed: shiftPressed)
                            },
                            onFocus: { shiftPressed, cursorPosition in
                                selectionManager.handleSelect(
                                    item: item, allItems: todoItems, shiftPressed: shiftPressed,
                                    cursorPosition: cursorPosition)
                            },
                            onEnterPressed: { createNewItemAfter(item) },
                            onDeletePressed: {
                                if selectionManager.selectedItemIds.contains(item.id) {
                                    selectionManager.deleteSelectedItems(store: store) { date in
                                        store.items(for: date)
                                    }
                                }
                            },
                            onMoveUp: { position in
                                selectionManager.moveFocusUp(
                                    from: item, allItems: todoItems, cursorPosition: position)
                            },
                            onMoveDown: { position in
                                selectionManager.moveFocusDown(
                                    from: item, allItems: todoItems, cursorPosition: position)
                            }
                        )
                        .id(item.id)
                    }
                }

                // 插入线（在列表末尾）
                if case .insertAt(let insertIndex, let indentLevel) = dropState,
                    insertIndex == todoItems.count
                {
                    insertionIndicator(indentLevel: indentLevel)
                }
            }
        }
        .onDrop(
            of: [.text],
            delegate: TodoDropDelegate(
                targetDate: section.date,
                todoItems: todoItems,
                store: store,
                dropState: $dropState,
                indentWidth: indentWidth,
                itemHeight: itemHeight
            ))
    }

    // MARK: - 插入线指示器

    private func insertionIndicator(indentLevel: Int) -> some View {
        HStack(spacing: 0) {
            // 左侧缩进空间（拖拽句柄宽度 + 缩进）
            Spacer()
                .frame(width: 20 + CGFloat(indentLevel) * indentWidth)

            // 红色圆点
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            // 红色线条
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .frame(height: 4)
        .transition(.opacity)
    }

    // MARK: - 标题视图

    private var titleView: some View {
        HStack {
            Text(section.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
                .onTapGesture {
                    selectedDate = section.date
                    showDatePicker = true
                }
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
                                updateSectionDate(to: selectedDate)
                                showDatePicker = false
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

    // MARK: - 操作方法

    private func updateSectionDate(to newDate: Date) {
        let oldDate = section.date
        let newDateStart = Calendar.current.startOfDay(for: newDate)

        // 如果日期没变，直接返回
        guard newDateStart != oldDate else { return }

        // 检查目标日期是否已有 Section
        if let existingSection = store.daySectionsCache.values.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: newDateStart) && $0.id != section.id
        }) {
            // 目标日期已有 Section，将当前待办移动到已有 Section
            let itemsToMove = store.items(for: oldDate)
            for item in itemsToMove {
                item.dayDate = existingSection.date
                item.updatedAt = Date()
            }

            // 删除当前 Section
            store.deleteSection(section)
        } else {
            // 目标日期没有 Section，更新当前 Section
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd"
            section.title = formatter.string(from: newDateStart)
            section.date = newDateStart

            // 同步更新所有待办的 dayDate
            let itemsToUpdate = store.items(for: oldDate)
            for item in itemsToUpdate {
                item.dayDate = newDateStart
                item.updatedAt = Date()
            }
        }

        store.scheduleSave()
    }

    private func addNewItem() {
        let newItem = store.createItem(dayDate: section.date)
        selectionManager.handleSelect(
            item: newItem, allItems: store.items(for: section.date), shiftPressed: false)
        onItemCreated?(newItem.id)
    }

    private func createNewItemAfter(_ item: TodoItem) {
        let newItem = store.createItem(
            dayDate: section.date,
            afterItem: item,
            indentLevel: item.indentLevel
        )
        selectionManager.handleSelect(
            item: newItem, allItems: store.items(for: section.date), shiftPressed: false)
        onItemCreated?(newItem.id)
    }
}

// MARK: - 拖拽代理

struct TodoDropDelegate: DropDelegate {
    let targetDate: Date
    let todoItems: [TodoItem]
    let store: TodoStore
    @Binding var dropState: TodoListDropState
    let indentWidth: CGFloat
    let itemHeight: CGFloat

    func dropEntered(info: DropInfo) {
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropState(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropState = .none
    }

    func performDrop(info: DropInfo) -> Bool {
        guard case .insertAt(let insertIndex, let indentLevel) = dropState else {
            dropState = .none
            return false
        }

        // 获取拖拽的 item ID
        let providers = info.itemProviders(for: [.text])
        guard let provider = providers.first else {
            dropState = .none
            return false
        }

        provider.loadObject(ofClass: NSString.self) { data, error in
            guard let idString = data as? String,
                let draggedId = UUID(uuidString: idString)
            else {
                return
            }

            DispatchQueue.main.async {
                self.performMove(
                    draggedId: draggedId, toIndex: insertIndex, indentLevel: indentLevel)
            }
        }

        dropState = .none
        return true
    }

    // MARK: - 私有方法

    private func updateDropState(info: DropInfo) {
        let y = info.location.y
        let x = info.location.x

        // 计算插入位置（基于 Y 坐标）
        let insertIndex = min(max(0, Int(y / itemHeight)), todoItems.count)

        // 计算缩进层级（基于 X 坐标）
        // 基准 X 位置是拖拽句柄宽度（20）
        let baseX: CGFloat = 20
        let relativeX = max(0, x - baseX)
        var indentLevel = Int(relativeX / indentWidth)

        // 限制缩进层级：
        // 1. 不能超过前一项的 indentLevel + 1
        // 2. 最大为 3
        if insertIndex > 0 {
            let prevItem = todoItems[insertIndex - 1]
            indentLevel = min(indentLevel, prevItem.indentLevel + 1)
        } else {
            indentLevel = 0  // 第一项只能是顶级
        }
        indentLevel = min(indentLevel, 3)

        dropState = .insertAt(index: insertIndex, indentLevel: indentLevel)
    }

    private func performMove(draggedId: UUID, toIndex: Int, indentLevel: Int) {
        guard let draggedItem = store.todoItemsCache[draggedId] else {
            return
        }

        // 计算 afterItem
        let afterItem: TodoItem?
        if toIndex > 0 {
            // 需要考虑如果拖拽的是列表中的项，索引可能需要调整
            let filteredItems = todoItems.filter { $0.id != draggedId }
            let adjustedIndex = min(toIndex - 1, filteredItems.count - 1)
            if adjustedIndex >= 0 && adjustedIndex < filteredItems.count {
                afterItem = filteredItems[adjustedIndex]
            } else if !filteredItems.isEmpty {
                afterItem = filteredItems.last
            } else {
                afterItem = nil
            }
        } else {
            afterItem = nil
        }

        // 移动项目及其子项
        store.moveItemWithChildren(
            draggedItem, toDate: targetDate, afterItem: afterItem, newIndentLevel: indentLevel)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TodoItem.self, DaySection.self, configurations: config)

    let section = DaySection(date: Date(), title: "01-17")
    container.mainContext.insert(section)

    TodoStore.shared.initialize(with: container.mainContext)

    return DaySectionView(
        section: section,
        selectionManager: SelectionManager()
    )
    .modelContainer(container)
    .padding()
}
