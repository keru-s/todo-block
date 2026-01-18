//
//  DaySectionView.swift
//  notion to do
//
//  Created by Claude on 2026/1/17.
//

import SwiftUI
import SwiftData
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
    }
    
    // MARK: - 待办列表视图
    
    private var todoListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(todoItems.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 0) {
                    // 插入线（在当前项上方）
                    if case .insertAt(let insertIndex, let indentLevel) = dropState, insertIndex == index {
                        insertionIndicator(indentLevel: indentLevel)
                    }
                    
                    TodoItemView(
                        item: item,
                        allItems: todoItems,
                        focusedItemId: $selectionManager.focusedItemId,
                        isSelected: selectionManager.selectedItemIds.contains(item.id),
                        hasMultipleSelection: selectionManager.selectedItemIds.count > 1,
                        onSelect: { shiftPressed in
                            selectionManager.handleSelect(item: item, allItems: todoItems, shiftPressed: shiftPressed)
                        },
                        onFocus: { shiftPressed in
                            selectionManager.handleSelect(item: item, allItems: todoItems, shiftPressed: shiftPressed)
                        },
                        onEnterPressed: { createNewItemAfter(item) },
                        onDeletePressed: {
                            if selectionManager.selectedItemIds.contains(item.id) {
                                selectionManager.deleteSelectedItems(store: store) { date in
                                    store.items(for: date)
                                }
                            }
                        },
                        onMoveUp: { selectionManager.moveFocusUp(from: item, allItems: todoItems) },
                        onMoveDown: { selectionManager.moveFocusDown(from: item, allItems: todoItems) }
                    )
                    .id(item.id)
                }
            }
            
            // 插入线（在列表末尾）
            if case .insertAt(let insertIndex, let indentLevel) = dropState, insertIndex == todoItems.count {
                insertionIndicator(indentLevel: indentLevel)
            }
        }
        .onDrop(of: [.text], delegate: TodoDropDelegate(
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
        Group {
            if isEditingTitle {
                TextField("日期标题", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold))
                    .focused($isTitleFocused)
                    .onSubmit {
                        section.title = editingTitle
                        isEditingTitle = false
                        store.scheduleSave()
                    }
                    .onExitCommand {
                        isEditingTitle = false
                    }
            } else {
                Text(section.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .onTapGesture {
                        editingTitle = section.title
                        isEditingTitle = true
                        isTitleFocused = true
                    }
            }
        }
        .padding(.bottom, 4)
    }
    
    // MARK: - 操作方法
    
    private func createNewItemAfter(_ item: TodoItem) {
        let newItem = store.createItem(
            dayDate: section.date,
            afterItem: item,
            indentLevel: item.indentLevel
        )
        selectionManager.handleSelect(item: newItem, allItems: store.items(for: section.date), shiftPressed: false)
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
                  let draggedId = UUID(uuidString: idString) else {
                return
            }
            
            DispatchQueue.main.async {
                self.performMove(draggedId: draggedId, toIndex: insertIndex, indentLevel: indentLevel)
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
        
        // 更新缩进层级
        draggedItem.indentLevel = indentLevel
        
        // 移动项目
        store.moveItem(draggedItem, toDate: targetDate, afterItem: afterItem)
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
